// bill_stitching.cpp
#include "opencv2/opencv_modules.hpp"
#include <opencv2/core/utility.hpp>
#include "opencv2/stitching/detail/autocalib.hpp"
#include "opencv2/stitching/detail/blenders.hpp"
#include "opencv2/stitching/detail/camera.hpp"
#include "opencv2/stitching/detail/exposure_compensate.hpp"
#include "opencv2/stitching/detail/matchers.hpp"
#include "opencv2/stitching/detail/motion_estimators.hpp"
#include "opencv2/stitching/detail/seam_finders.hpp"
#include "opencv2/stitching/detail/warpers.hpp"
#include "opencv2/stitching/warpers.hpp"

#ifdef __ANDROID__
#include <android/log.h>
#endif
using namespace std;
using namespace cv;
using namespace cv::detail;

void stitching_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
#ifdef __ANDROID__
    __android_log_vprint(ANDROID_LOG_VERBOSE, "ndk", fmt, args);
#else
    vprintf(fmt, args);
#endif
    va_end(args);
}

cv::Rect adjustROI(const cv::Rect &roi, const cv::Mat &image) {
    int x = std::max(roi.x, 0);
    int y = std::max(roi.y, 0);
    int width = std::min(roi.width, image.cols - x);
    int height = std::min(roi.height, image.rows - y);
    return cv::Rect(x, y, width, height);
}

// Hàm kiểm tra xem phép biến đổi có hợp lệ không
bool isTransformValid(const Mat &H) {
    double det = determinant(H);
    if (det < 1e-6) {
        stitching_log("Transformation matrix is degenerate (det = %f)\n", det);
        return false;
    }
    return true;
}


Mat stitchBills(const std::vector <cv::Mat> &images) {
    double work_megapix = 0.2;   // Giảm xuống để tăng tốc độ
    double seam_megapix = 0.1;
    double compose_megapix = -1;
    string features_type = "orb"; // Sử dụng ORB cho tốc độ
    string matcher_type = "affine";
    string estimator_type = "homography";
//    string ba_cost_func = "affine";
//    bool do_wave_correct = true;
    string warp_type = "affine";  // Sử dụng affine warping cho bill hơi cong
    float match_conf = 0.5f;      // Tăng lên để lọc kết quả khớp tốt hơn
    bool try_cuda = true;
    double warped_image_scale = 1.0;
    double seam_work_aspect = 1.0;
    std::string seam_find_type = "dp_color";
    std::string blend_type = "multiband";
//    int multi_band_levels = 5;
//    float feather_sharpness = 0.02f;

    int num_images = static_cast<int>(images.size());
    if (num_images < 2) {
        stitching_log("Need more images\n");
        return Mat();
    }

    vector<Mat> resized_images;
    double scale = 1.0;
    if (work_megapix > 0) {
        scale = min(1.0, sqrt(work_megapix * 1e6 / images[0].total()));
    }
    for (const auto & img : images) {
        Mat resized;
        if (scale < 1.0) {
            resize(img, resized, Size(), scale, scale);
        } else {
            resized = img.clone();
        }
        stitching_log("Resized image size: width=%d, height=%d\n", resized.cols, resized.rows);
        resized_images.push_back(resized);
    }

    //=== 1. Tìm features & Tạo matcher ===
    stitching_log("Finding features...\n");
    Ptr <Feature2D> finder;
    if (features_type == "orb") {
        finder = ORB::create(5500); // Giảm số lượng features tối đa
    } else if (features_type == "akaze") {
        finder = AKAZE::create();
    } else if (features_type == "sift") {
        finder = SIFT::create();
    } else {
        stitching_log("Unknown 2D features type: '%s'\n", features_type.c_str());
        return Mat();
    }

    vector <ImageFeatures> features(num_images);

    for (int i = 0; i < num_images; ++i) {
        vector <KeyPoint> keypoints;
        Mat descriptors;
        // Detect keypoints and compute descriptors for the current image
        finder->detectAndCompute(resized_images[i], noArray(), keypoints, descriptors);
        features[i].img_idx = i;
        features[i].keypoints = keypoints;
        descriptors.clone().copyTo(features[i].descriptors);
        // Loại bỏ điểm đặc trưng trùng lặp
        auto dist_thresh = 4;
        vector <Point2f> points;
        for (size_t j = 0; j < features[i].keypoints.size(); ++j) {
            bool keep = true;
            for (size_t k = 0; k < j; ++k) {
                if (norm(features[i].keypoints[j].pt - features[i].keypoints[k].pt) <
                    dist_thresh) {
                    keep = false;
                    break;
                }
            }
            if (keep) {
                points.push_back(features[i].keypoints[j].pt);
            }
        }
        features[i].keypoints.clear();
        for (const auto &pt: points) {
            features[i].keypoints.emplace_back(pt, 1.f);
        }
    }

    stitching_log("Features found\n");

    vector <MatchesInfo> pairwise_matches;
    Ptr <FeaturesMatcher> matcher;
    if (matcher_type == "affine")
        matcher = makePtr<AffineBestOf2NearestMatcher>(false, try_cuda, match_conf);
    else if (matcher_type == "homography")
        matcher = makePtr<BestOf2NearestMatcher>(false, match_conf, try_cuda);
    else {
        stitching_log("Unknown matcher type: '%s'\n", matcher_type.c_str());
        return Mat();
    }

    stitching_log("Matching features...\n");
    (*matcher)(features, pairwise_matches);
    stitching_log("Features matched\n");

    matcher->collectGarbage();

    // Estimate camera parameters
    vector <CameraParams> cameras;
    Ptr <Estimator> estimator;
    if (estimator_type == "homography") {
        estimator = makePtr<HomographyBasedEstimator>();
    } else {
        stitching_log("Unknown estimator type: '%s'\n", estimator_type.c_str());
        return Mat();
    }

    if (!(*estimator)(features, pairwise_matches, cameras)) {
        stitching_log("Camera parameters estimation failed.\n");
        return Mat();
    }

    for (size_t i = 0; i < cameras.size(); ++i) {
        if (!isTransformValid(cameras[i].R)) {
            // Nếu ma trận R không hợp lệ, thử lại với AffineBasedEstimator
            stitching_log(
                    "Homography estimation failed for image %d. Trying affine estimation...\n",
                    static_cast<int>(i));
            Ptr <Estimator> affineEstimator = makePtr<AffineBasedEstimator>();
            if (!(*affineEstimator)(features, pairwise_matches, cameras)) {
                stitching_log("Affine estimation also failed for image %d. Skipping...\n",
                              static_cast<int>(i));
                continue;
            }
            stitching_log("Affine estimation succeeded for image %d.\n", static_cast<int>(i));
        }
        Mat R;
        cameras[i].R.convertTo(R, CV_32F);
        cameras[i].R = R;
    }

    cv::Ptr<cv::WarperCreator> warper_creator;
    // Warp images (cylindrical warping)
    if (warp_type == "cylindrical")
        warper_creator = cv::makePtr<cv::CylindricalWarper>();
    else if (warp_type == "spherical")
        warper_creator = cv::makePtr<cv::SphericalWarper>();
    else if (warp_type == "plane")
        warper_creator = cv::makePtr<cv::PlaneWarper>();
    else if (warp_type == "affine")
        warper_creator = cv::makePtr<cv::AffineWarper>();
    else {
        stitching_log("Unknown warper type: '%s'\n", warp_type.c_str());
        return Mat();
    }

    stitching_log("Using warper type: '%s'\n", warp_type.c_str());

    auto warper = warper_creator->create(static_cast<float>(warped_image_scale * seam_work_aspect));

    stitching_log("Warper created\n");

    vector <Point> corners(num_images);
    vector <UMat> masks_warped(num_images);
    vector <UMat> images_warped(num_images);
    vector <Size> sizes(num_images);

    stitching_log("Warping images...\n");

    for (int i = 0; i < num_images; ++i) {
        Mat R = cameras[i].R;

        Mat_<float> K;
        cameras[i].K().convertTo(K, CV_32F);

        float swa = (float) seam_work_aspect;
        K(0, 0) *= swa;
        K(0, 2) *= swa;
        K(1, 1) *= swa;
        K(1, 2) *= swa;

        stitching_log("Warping image %d\n", i);

        // Điều chỉnh ROI trước khi warping
        cv::Rect roiBeforeWarping(0, 0, resized_images[i].cols, resized_images[i].rows);
        stitching_log("roiBeforeWarping: x=%d, y=%d, width=%d, height=%d\n", roiBeforeWarping.x,
                      roiBeforeWarping.y, roiBeforeWarping.width, roiBeforeWarping.height);
        cv::Rect adjustedRoi = adjustROI(roiBeforeWarping, resized_images[i]);
        stitching_log("adjustedRoi: x=%d, y=%d, width=%d, height=%d\n", adjustedRoi.x,
                      adjustedRoi.y, adjustedRoi.width, adjustedRoi.height);

        // Kiểm tra phép biến đổi trước khi warp
        if (!isTransformValid(cameras[i].R)) {
            stitching_log("Invalid transformation for image %d. Skipping...\n", i);
            continue; // Bỏ qua ảnh hiện tại nếu phép biến đổi không hợp lệ
        }

        // -> Tính toán ma trận H sau khi chuyển đổi K
        Mat H = K * cameras[i].R;
        H.convertTo(H, CV_32F);

        if (!isTransformValid(H)) {
            stitching_log("Invalid homography matrix for image %d. Skipping...\n", i);
            continue;
        }

        // Sử dụng adjustedRoi nếu cần thiết. Trong ví dụ này, chúng ta sử dụng toàn bộ ảnh.
        try {
            corners[i] = warper->warp(resized_images[i](adjustedRoi), K, H, INTER_LINEAR, BORDER_REFLECT,
                                      images_warped[i]);
        } catch (const cv::Exception &e) {
            stitching_log("OpenCV Exception (warp): %s\n", e.what());
//            images.erase(images.begin() + i);
            stitching_log("Error warping image %d. Skipping...\n", i);
            continue;
        }

        sizes[i] = images_warped[i].size();

        stitching_log("Image warped size: width=%d, height=%d\n", sizes[i].width,
                      sizes[i].height); // In ra kích thước ảnh warped

        if (sizes[i].width == 0 || sizes[i].height == 0) {
            stitching_log("Error: Warped image size is zero. Skipping...\n");
            // Xử lý lỗi tương tự như bước 2
        }

        masks_warped[i].create(sizes[i], CV_8U);
        masks_warped[i].setTo(Scalar::all(255));
    }

    // Thay vì:
// Ptr<ExposureCompensator> compensator = ExposureCompensator::createDefault(ExposureCompensator::GAIN_BLOCKS);
// Sử dụng:
    Ptr <ExposureCompensator> compensator = makePtr<NoExposureCompensator>();

    // Prepare the images and masks for exposure compensation
    stitching_log("Preparing images for exposure compensation...\n");

    vector <UMat> images_for_compensation(num_images);
    vector <UMat> masks_for_compensation(num_images);
    for (int i = 0; i < num_images; ++i) {
        images_warped[i].convertTo(images_for_compensation[i],
                                   CV_16S); // Convert images to 16-bit signed for compensation
        masks_warped[i].copyTo(masks_for_compensation[i]);
    }

    // Feed the images and masks to the compensator
    compensator->feed(corners, images_for_compensation, masks_for_compensation);


    // Apply exposure compensation
    stitching_log("Applying exposure compensation...\n");

    for (int i = 0; i < num_images; ++i) {
        compensator->apply(i, corners[i], images_warped[i], masks_warped[i]);
    }

    // Find seams
    stitching_log("Finding seams...\n");
    Ptr <SeamFinder> seam_finder;
    if (seam_find_type == "no")
        seam_finder = makePtr<NoSeamFinder>();
    else if (seam_find_type == "voronoi")
        seam_finder = makePtr<VoronoiSeamFinder>();
    else if (seam_find_type == "gc_color")
        seam_finder = makePtr<GraphCutSeamFinder>(GraphCutSeamFinderBase::COST_COLOR);
    else if (seam_find_type == "gc_colorgrad")
        seam_finder = makePtr<GraphCutSeamFinder>(GraphCutSeamFinderBase::COST_COLOR_GRAD);
    else if (seam_find_type == "dp_color")
        seam_finder = makePtr<DpSeamFinder>(DpSeamFinder::COLOR);
    else if (seam_find_type == "dp_colorgrad")
        seam_finder = makePtr<DpSeamFinder>(DpSeamFinder::COLOR_GRAD);
    else {
        stitching_log("Unknown seam finder type: '%s'\n", seam_find_type.c_str());
        return Mat();
    }


    vector<UMat> resized_images_warped;
    if (seam_megapix > 0) {
        double seam_scale = min(1.0, sqrt(seam_megapix * 1e6 / images_warped[0].total()));
        for (auto & img : images_warped) {
            UMat resized;
            if (seam_scale < 1.0) {
                resize(img, resized, Size(), seam_scale, seam_scale);
            } else {
                resized = img.clone();
            }
            resized_images_warped.push_back(resized);
        }
        seam_finder->find(resized_images_warped, corners, masks_warped);
        stitching_log("Seams found\n");
    } else {
        seam_finder->find(images_warped, corners, masks_warped);
        stitching_log("Seams found\n");
    }

    // Blend images
    stitching_log("Blending images...\n");
    Ptr <Blender> blender;
    if (blend_type == "no")
        blender = Blender::createDefault(Blender::NO);
    else if (blend_type == "feather")
        blender = Blender::createDefault(Blender::FEATHER);
    else if (blend_type == "multiband")
        blender = Blender::createDefault(Blender::MULTI_BAND);
    else {
        stitching_log("Unknown blender type: '%s'\n", blend_type.c_str());
        return Mat();
    }

    blender->prepare(corners, sizes);
    stitching_log("Blender prepared\n");

    for (int i = 0; i < num_images; ++i) {
        blender->feed(images_warped[i], masks_warped[i], corners[i]);
    }

    Mat result, result_mask;
    blender->blend(result, result_mask);
    stitching_log("Blending done\n");

    if (compose_megapix > 0) {
        double compose_scale = min(1.0, sqrt(compose_megapix * 1e6 / result.total()));
        if (compose_scale < 1.0) {
            resize(result, result, Size(), compose_scale, compose_scale);
        }
    }

    // === 4. Cắt 4 góc của bill ===
    // Tìm contour của bill
    stitching_log("Finding bill contour...\n");
    Mat grayResult;
    cvtColor(result, grayResult, COLOR_BGR2GRAY);
    threshold(grayResult, grayResult, 1, 255, THRESH_BINARY);
    vector<vector<Point>> contours;
    findContours(grayResult, contours, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);

    // Chọn contour lớn nhất (giả sử bill là đối tượng lớn nhất)
    int largestContourIndex = 0;
    double largestContourArea = 0;
    for (int i = 0; i < contours.size(); i++) {
        double area = contourArea(contours[i]);
        if (area > largestContourArea) {
            largestContourArea = area;
            largestContourIndex = i;
        }
    }

    stitching_log("Largest contour found\n");

    // Tìm bounding rect của contour lớn nhất
    Rect billRect = boundingRect(contours[largestContourIndex]);

    stitching_log("Bounding rect found\n");

    // Cắt ảnh theo bounding rect
    result = result(billRect);

    // === 5. Làm phẳng bill (sử dụng perspective transform) ===
    stitching_log("Flattening bill...\n");
    // Tìm 4 góc của bill
    stitching_log("Bill rect: x=%d, y=%d, width=%d, height=%d\n", billRect.x, billRect.y, billRect.width, billRect.height);
    vector<Point2f> billCorners(4);
    billCorners[0] = Point2f(billRect.x, billRect.y);                   // Góc trên bên trái
    billCorners[1] = Point2f(billRect.x + billRect.width, billRect.y);          // Góc trên bên phải
    billCorners[2] = Point2f(billRect.x + billRect.width, billRect.y + billRect.height); // Góc dưới bên phải
    billCorners[3] = Point2f(billRect.x, billRect.y + billRect.height);         // Góc dưới bên trái

    // Xác định kích thước ảnh đầu ra sau khi làm phẳng
    float maxWidth = max(norm(billCorners[0] - billCorners[1]), norm(billCorners[2] - billCorners[3]));
    float maxHeight = max(norm(billCorners[1] - billCorners[2]), norm(billCorners[3] - billCorners[0]));
    Size outputSize(maxWidth, maxHeight);

    stitching_log("Output size: width=%d, height=%d\n", outputSize.width, outputSize.height);

    // Tạo ma trận đích cho perspective transform
    vector<Point2f> outputCorners(4);
    outputCorners[0] = Point2f(0, 0);
    outputCorners[1] = Point2f(outputSize.width - 1, 0);
    outputCorners[2] = Point2f(outputSize.width - 1, outputSize.height - 1);
    outputCorners[3] = Point2f(0, outputSize.height - 1);

    // Tính toán ma trận perspective transform
    Mat perspectiveTransform = getPerspectiveTransform(billCorners, outputCorners);

    stitching_log("Perspective transform computed\n");

    // Áp dụng perspective transform để làm phẳng bill
    warpPerspective(result, result, perspectiveTransform, outputSize);

    stitching_log("Bill flattened\n");

    stitching_log("Stitching completed\n");

    return result;
}