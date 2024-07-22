#include "opencv2/opencv.hpp"
#include "opencv2/opencv_modules.hpp"
#include "opencv2/core/utility.hpp"
#include "opencv2/stitching/detail/autocalib.hpp"
#include "opencv2/stitching/detail/blenders.hpp"
#include "opencv2/stitching/detail/camera.hpp"
#include "opencv2/stitching/detail/exposure_compensate.hpp"
#include "opencv2/stitching/detail/matchers.hpp"
#include "opencv2/stitching/detail/motion_estimators.hpp"
#include "opencv2/stitching/detail/seam_finders.hpp"
#include "opencv2/stitching/detail/warpers.hpp"
#include "opencv2/stitching/warpers.hpp"
#include "bill_stitching.hpp"

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

// Hàm kiểm tra xem phép biến đổi có hợp lệ không
bool isTransformValid(const Mat &H) {
    double det = determinant(H);
    if (det < 1e-6) {
        stitching_log("Transformation matrix is degenerate (det = %f)\n", det);
        return false;
    }
    return true;
}

Mat cv::bill_stitching::stitchBills(const std::vector<cv::Mat> &images) {
    double work_megapix = 0.5;   // Giảm xuống để tăng tốc độ
    double seam_megapix = 0.5;
    double compose_megapix = -1;
//    string features_type = "orb"; // Sử dụng ORB cho tốc độ
    string features_type = "sift";
    string matcher_type = "affine";
    string estimator_type = "affine";
    string ba_cost_func = "affine";
//    bool do_wave_correct = true;
    string warp_type = "affine";  // Sử dụng affine warping cho bill hơi cong
    float match_conf = 0.6;      // Tăng lên để lọc kết quả khớp tốt hơn
    bool try_cuda = true;
    double warped_image_scale = 1.0;
    double seam_work_aspect = 1.0;
    std::string seam_find_type = "dp_color";
    std::string blend_type = "no";

    int num_images = static_cast<int>(images.size());
    if (num_images < 2) {
        stitching_log("Need more images\n");
        return Mat();
    }

    //=== Tiền xử lý ===
    vector<Mat> preprocessed_images;
    for (const auto &img: images) {
        Mat preprocessed = img.clone();

        //=== Cân bằng trắng ===
        // Chuyển đổi sang ảnh xám
        Mat gray;
        cvtColor(preprocessed, gray, COLOR_BGR2GRAY);

        // Tính toán histogram
        Mat hist;
        int histSize = 256;
        float range[] = {0, 256};
        const float *histRange = {range};
        calcHist(&gray, 1, 0, Mat(), hist, 1, &histSize, &histRange, true, false);

        // Tìm ngưỡng để phân đoạn nền và đối tượng
        int totalPixels = gray.rows * gray.cols;
        float sum = 0;
        int thresholdValue = 0;
        for (int i = 0; i < histSize; ++i) {
            sum += hist.at<float>(i);
            if (sum > 0.1 * totalPixels) {
                thresholdValue = i;
                break;
            }
        }

        // Tạo mặt nạ cho nền và đối tượng
        Mat mask;
        threshold(gray, mask, thresholdValue, 255, THRESH_BINARY);

        // Tính toán giá trị trung bình cho nền và đối tượng
        Scalar meanForeground, meanBackground;
        meanStdDev(preprocessed, meanForeground, noArray(), mask);
        meanStdDev(preprocessed, meanBackground, noArray(), ~mask);

        // Cân bằng trắng bằng cách scale giá trị trung bình của đối tượng về giá trị trung bình của nền
        Scalar scaleFactor = meanBackground / meanForeground;
        preprocessed.convertTo(preprocessed, CV_32FC3);
        multiply(preprocessed, scaleFactor, preprocessed);
        preprocessed.convertTo(preprocessed, CV_8UC3);

        //=== Giảm nhiễu ===
        GaussianBlur(preprocessed, preprocessed, Size(5, 5), 0);

        //=== Tăng cường độ tương phản ===
        Ptr<CLAHE> clahe = createCLAHE();

        clahe->setClipLimit(4.0);
        Mat lab;
        cvtColor(preprocessed, lab, COLOR_BGR2Lab);
        vector<Mat> lab_planes(3);
        split(lab, lab_planes);
        clahe->apply(lab_planes[0], lab_planes[0]);
        merge(lab_planes, lab);
        cvtColor(lab, preprocessed, COLOR_Lab2BGR);

        preprocessed_images.push_back(preprocessed);
    }

    vector<Mat> resized_images;
    double scale = 1.0;
    if (work_megapix > 0) {
        scale = min(1.0, sqrt(work_megapix * 1e6 / preprocessed_images[0].total()));
    }
    for (const auto &img: preprocessed_images) {
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
    Ptr<Feature2D> finder;
    if (features_type == "orb") {
        finder = ORB::create(7000); // Giảm số lượng features tối đa
    } else if (features_type == "akaze") {
        finder = AKAZE::create();
    } else if (features_type == "sift") {
        finder = SIFT::create();
    } else if (features_type == "brisk") {
        finder = BRISK::create();
    } else {
        stitching_log("Unknown 2D features type: '%s'\n", features_type.c_str());
        return Mat();
    }

    vector<ImageFeatures> features(num_images);
    for (int i = 0; i < num_images; ++i) {
        vector<KeyPoint> keypoints;
        Mat descriptors;
        // Detect keypoints and compute descriptors for the current image
        finder->detectAndCompute(resized_images[i], noArray(), keypoints, descriptors);

        // Loại bỏ điểm đặc trưng trùng lặp (radius match)
        float radius = 10.0f; // Adjust this value as needed
        vector<KeyPoint> filteredKeypoints;
        for (size_t j = 0; j < keypoints.size(); ++j) {
            bool keep = true;
            for (size_t k = 0; k < filteredKeypoints.size(); ++k) {
                if (norm(keypoints[j].pt - filteredKeypoints[k].pt) < radius) {
                    keep = false;
                    break;
                }
            }
            if (keep) {
                filteredKeypoints.push_back(keypoints[j]);
            }
        }
        keypoints = filteredKeypoints;
        features[i].img_idx = i;
        features[i].keypoints = keypoints;
        descriptors.clone().copyTo(features[i].descriptors);
    }
    stitching_log("Features found\n");

    //=== 2. Ghép nối từng cặp ảnh theo thứ tự đầu vào ===
    stitching_log("Matching features...\n");

    Mat result = resized_images[0].clone(); // Ảnh đầu tiên là ảnh khởi tạo
    for (int i = 1; i < num_images; ++i) {
        stitching_log("Stitching image %d to the panorama...\n", i);

        // Tìm feature matching giữa ảnh hiện tại và kết quả ghép nối tạm thời
        vector<MatchesInfo> pairwise_matches;
        Ptr<FeaturesMatcher> matcher;
        if (matcher_type == "affine")
            matcher = makePtr<AffineBestOf2NearestMatcher>(false, try_cuda, match_conf);
        else if (matcher_type == "homography")
            matcher = makePtr<BestOf2NearestMatcher>(false, match_conf, try_cuda);
        else {
            stitching_log("Unknown matcher type: '%s'\n", matcher_type.c_str());
            return Mat();
        }
        vector<ImageFeatures> twoFeatures;
        twoFeatures.push_back(features[i - 1]); // Ảnh trước đó (đã được ghép nối)
        twoFeatures.push_back(features[i]);     // Ảnh hiện tại
        (*matcher)(twoFeatures, pairwise_matches);
        matcher->collectGarbage();

        // Estimate camera parameters
        vector<CameraParams> cameras;
        Ptr<Estimator> estimator;
        if (estimator_type == "homography") {
            estimator = makePtr<HomographyBasedEstimator>();
        } else if (estimator_type == "affine") {
            estimator = makePtr<AffineBasedEstimator>();
        } else {
            stitching_log("Unknown estimator type: '%s'\n", estimator_type.c_str());
            return Mat();
        }

        if (!(*estimator)(twoFeatures, pairwise_matches, cameras)) {
            stitching_log("Camera parameters estimation failed.\n");
            return Mat();
        }
        for (size_t j = 0; j < cameras.size(); ++j) {
            Mat R = cameras[j].R;

            // Kiểm tra xem có phép biến đổi lật ảnh không
            if (R.at<double>(0, 0) * R.at<double>(1, 1) -
                R.at<double>(0, 1) * R.at<double>(1, 0) < 0) {
                // Nếu có, đảo ngược dấu của cột thứ hai
                R.at<double>(0, 1) *= -1;
                R.at<double>(1, 1) *= -1;
                R.at<double>(2, 1) *= -1;

                // Cập nhật lại ma trận R trong cameras
                cameras[j].R = R;
            }
        }

        //=== 3. Warp ảnh hiện tại và ghép nối vào result ===
// Chuyển đổi ma trận H từ 2x3 thành 3x3
        Mat H = cameras[1].R;
        H.convertTo(H, CV_32F); // Chuyển đổi kiểu dữ liệu của H sang float
        H = Mat::eye(3, 3, CV_32F) * H;
        H.at<float>(2, 2) = 1.0f;

// Tính toán kích thước ảnh result sau khi warp
        stitching_log("Calculating output image size...\n");
        vector<Point2f> corners(4);
        corners[0] = Point2f(0, 0);
        corners[1] = Point2f(result.cols, 0);
        corners[2] = Point2f(result.cols, result.rows);
        corners[3] = Point2f(0, result.rows);
        Mat cornersMat = Mat(corners).reshape(1).t();
        cornersMat.convertTo(cornersMat, CV_32FC2);

// Thực hiện perspectiveTransform
        perspectiveTransform(cornersMat, cornersMat, H);
        cornersMat = cornersMat.reshape(2, cornersMat.cols).t();
        corners = vector<Point2f>(cornersMat.ptr<Point2f>(0),
                                  cornersMat.ptr<Point2f>(0) + cornersMat.cols);

        int minX = min(0, min(cvRound(corners[0].x), cvRound(corners[3].x)));
        int minY = min(0, min(cvRound(corners[0].y), cvRound(corners[1].y)));
        int maxX = max(cvRound(corners[1].x), max(cvRound(corners[2].x), result.cols));
        int maxY = max(cvRound(corners[2].y), max(cvRound(corners[3].y), result.rows));
        Size outputSize(maxX - minX, maxY - minY);
        stitching_log("Output image size: width=%d, height=%d\n", outputSize.width,
                      outputSize.height);

        // Tạo ma trận dịch chuyển để đưa ảnh về đúng vị trí
        Mat translation = Mat::eye(3, 3, CV_32F);
        translation.at<float>(0, 2) = -minX;
        translation.at<float>(1, 2) = -minY;

        // Cập nhật ma trận homography
        H = translation * H;

        // Warp ảnh hiện tại
        Mat warpedImage;
        warpPerspective(resized_images[i], warpedImage, H, outputSize, INTER_LINEAR,
                        BORDER_CONSTANT);

        // Ghép nối ảnh đã warp vào result
        stitching_log("Blending images...\n");
        Mat finalImage(outputSize, CV_8UC3);
        for (int y = 0; y < outputSize.height; y++) {
            for (int x = 0; x < outputSize.width; x++) {
                // Kiểm tra xem điểm ảnh có nằm trong vùng chồng lấp không
                if (x - minX >= 0 && x - minX < result.cols && y - minY >= 0 &&
                    y - minY < result.rows &&
                    warpedImage.at<Vec3b>(y, x) != Vec3b(0, 0, 0)) {
                    // Điểm ảnh nằm trong vùng chồng lấp, thực hiện blending
                    finalImage.at<Vec3b>(y, x) =
                            0.5 * result.at<Vec3b>(y - minY, x - minX) +
                            0.5 * warpedImage.at<Vec3b>(y, x);
                } else if (warpedImage.at<Vec3b>(y, x) != Vec3b(0, 0, 0)) {
                    // Điểm ảnh chỉ nằm trong ảnh warped
                    finalImage.at<Vec3b>(y, x) = warpedImage.at<Vec3b>(y, x);
                } else if (x - minX >= 0 && x - minX < result.cols && y - minY >= 0 &&
                           y - minY < result.rows) {
                    // Điểm ảnh chỉ nằm trong ảnh result
                    finalImage.at<Vec3b>(y, x) = result.at<Vec3b>(y - minY, x - minX);
                } else {
                    // Điểm ảnh không thuộc vùng nào, đặt là màu đen
                    finalImage.at<Vec3b>(y, x) = Vec3b(0, 0, 0);
                }
            }
        }
        stitching_log("Blending done\n");

        // Cập nhật result
        result = finalImage.clone();
    }


    stitching_log("Features matched\n");



    //=== 5. Cắt ảnh theo bill ===
    stitching_log("Finding bill contour...\n");
    Mat grayResult;
    cvtColor(result, grayResult, COLOR_BGR2GRAY);
    threshold(grayResult, grayResult, 1, 255, THRESH_BINARY);
    vector<vector<Point>> contours;
    findContours(grayResult, contours, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);

    if (contours.empty()) {
        stitching_log("No contours found. Skipping bill cropping.\n");
        return result;
    }

    // Chọn contour lớn nhất (giả sử bill là đối tượng lớn nhất)
    stitching_log("Finding largest contour...\n");
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

    // === 6. Làm phẳng bill (sử dụng perspective transform) ===
    stitching_log("Flattening bill...\n");
    // Tìm 4 góc của bill
    stitching_log("Bill rect: x=%d, y=%d, width=%d, height=%d\n", billRect.x, billRect.y,
                  billRect.width, billRect.height);
    vector<Point2f> billCorners(4);
    billCorners[0] = Point2f(billRect.x, billRect.y);                   // Góc trên bên trái
    billCorners[1] = Point2f(billRect.x + billRect.width, billRect.y);          // Góc trên bên phải
    billCorners[2] = Point2f(billRect.x + billRect.width,
                             billRect.y + billRect.height); // Góc dưới bên phải
    billCorners[3] = Point2f(billRect.x, billRect.y + billRect.height);         // Góc dưới bên trái

    // Xác định kích thước ảnh đầu ra sau khi làm phẳng
    float maxWidth = max(norm(billCorners[0] - billCorners[1]),
                         norm(billCorners[2] - billCorners[3]));
    float maxHeight = max(norm(billCorners[1] - billCorners[2]),
                          norm(billCorners[3] - billCorners[0]));
    Size outputSize1(maxWidth, maxHeight);

    stitching_log("Output size: width=%d, height=%d\n", outputSize1.width, outputSize1.height);

    // Tạo ma trận đích cho perspective transform
    vector<Point2f> outputCorners(4);
    outputCorners[0] = Point2f(0, 0);
    outputCorners[1] = Point2f(outputSize1.width - 1, 0);
    outputCorners[2] = Point2f(outputSize1.width - 1, outputSize1.height - 1);
    outputCorners[3] = Point2f(0, outputSize1.height - 1);

    // Tính toán ma trận perspective transform
    Mat perspectiveTransform1 = getPerspectiveTransform(billCorners, outputCorners);

    stitching_log("Perspective transform computed\n");

    // Áp dụng perspective transform để làm phẳng bill
    warpPerspective(result, result, perspectiveTransform1, outputSize1);

    stitching_log("Bill flattened\n");

    stitching_log("Stitching completed\n");

    return result;
}