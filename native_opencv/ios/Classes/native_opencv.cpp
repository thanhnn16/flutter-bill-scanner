#include "opencv2/opencv.hpp"
#include "chrono"
#include "vector"
#include "bill_stitching.hpp"
#include <algorithm>
#include <ctime>

#ifdef __ANDROID__
#include <android/log.h>
#endif

using namespace cv;
using namespace cv::detail;
using namespace std;

long long int get_now() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()
    ).count();
}

void platform_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
#ifdef __ANDROID__
    __android_log_vprint(ANDROID_LOG_VERBOSE, "ndk", fmt, args);
#else
    vprintf(fmt, args);
#endif
    va_end(args);
}

// Hàm so sánh để sắp xếp tên file theo thứ tự số tự nhiên
bool compareNatural(const std::string &a, const std::string &b) {
    // Tìm vị trí của dấu '/' cuối cùng trong đường dẫn
    size_t aSlashPos = a.find_last_of('/');
    size_t bSlashPos = b.find_last_of('/');

    // Lấy tên file từ đường dẫn
    std::string aFileName = a.substr(aSlashPos + 1);
    std::string bFileName = b.substr(bSlashPos + 1);

    std::string aNumber, bNumber;
    size_t aPos = 0, bPos = 0;

    while (aPos < aFileName.size() || bPos < bFileName.size()) {
        // Lấy phần số từ vị trí hiện tại đến khi gặp ký tự không phải số
        while (aPos < aFileName.size() && std::isdigit(aFileName[aPos])) {
            aNumber += aFileName[aPos++];
        }
        while (bPos < bFileName.size() && std::isdigit(bFileName[bPos])) {
            bNumber += bFileName[bPos++];
        }

        // So sánh phần số
        if (!aNumber.empty() && !bNumber.empty()) {
            if (std::stoi(aNumber) != std::stoi(bNumber)) {
                return std::stoi(aNumber) < std::stoi(bNumber);
            }
        } else if (!aNumber.empty()) { // a có số, b không có số
            return true;
        } else if (!bNumber.empty()) { // b có số, a không có số
            return false;
        }

        // Reset phần số
        aNumber.clear();
        bNumber.clear();

        // Chỉ tăng aPos hoặc bPos nếu chưa đến cuối chuỗi
        if (aPos < aFileName.size()) {
            aPos++;
        }
        if (bPos < bFileName.size()) {
            bPos++;
        }
    }

    // Nếu tất cả các phần số đều bằng nhau, so sánh độ dài chuỗi
    return aFileName.size() < bFileName.size();
}


extern "C" {
const char *version() {
    return CV_VERSION;
}

void stitch_images(const char **imagePaths, int numImages, char *outputImagePath) {

    std::vector<std::string> imagePathsVector(imagePaths, imagePaths + numImages);

    // Sắp xếp tên ảnh theo thứ tự tăng dần
    platform_log("Sắp xếp tên ảnh theo thứ tự tăng dần...\n");
    std::sort(imagePathsVector.begin(), imagePathsVector.end(), compareNatural);
    platform_log("Sắp xếp tên ảnh xong.\n");
    platform_log("Danh sách ảnh:\n");
    for (const auto &imagePath: imagePathsVector) {
        platform_log("%s\n", imagePath.c_str());
    }

    std::vector<cv::Mat> images;
    images.reserve(numImages); // Giữ chỗ trước cho images để tối ưu hiệu suất

    for (const auto &imagePath: imagePathsVector) {
        cv::Mat img = cv::imread(imagePath);
        platform_log("Đã tải hình ảnh tại đường dẫn: %s\n", imagePath.c_str());
        if (img.empty()) {
            platform_log("Không thể tải hình ảnh tại đường dẫn: %s\n", imagePath.c_str());
            // Xử lý lỗi khi không load được ảnh, ví dụ: bỏ qua ảnh lỗi và tiếp tục
            continue;
        }
        images.push_back(img);
    }

    try {
        long long int start = get_now();

        // 1. Khởi tạo Stitcher
        Ptr<Stitcher> stitcher = Stitcher::create(Stitcher::SCANS);

        // 2. Tùy chỉnh các tham số
        stitcher->setRegistrationResol(0.8);    // Giảm nhẹ để tăng tốc độ, có thể thử nghiệm từ 0.6 - 0.8
        stitcher->setSeamEstimationResol(0.8); // Giống RegistrationResol
        stitcher->setCompositingResol(1);      // Giữ nguyên để đảm bảo độ phân giải ảnh kết quả
        stitcher->setPanoConfidenceThresh(0.95);  // Tăng lên để loại bỏ ghép nối sai, giá trị thử nghiệm từ 0.7 - 0.9
        stitcher->setFeaturesFinder(SIFT::create());
//        stitcher->setFeaturesFinder(ORB::create(9000)); // Giảm số lượng features để tăng tốc độ, thử nghiệm từ 3000 - 8000
        // Ngoài ra, có thể thử nghiệm với các features khác như SIFT, BRISK, AKAZE
        stitcher->setWaveCorrection(false);     // Tắt, không cần thiết cho scan bill

        // Bỏ qua ExposureCompensator vì ánh sáng khi scan thường đồng đều
        // stitcher->setExposureCompensator(ExposureCompensator::createDefault(ExposureCompensator::GAIN_BLOCKS));
        stitcher->setBlender(Blender::createDefault(Blender::MULTI_BAND, true)); // Giữ nguyên, vẫn cần blender cho kết quả tốt nhất
        // Không cần setWarper vì không ghép panorama
        // stitcher->setWarper(Ptr<WarperCreator>(new cv::CylindricalWarper()));

        // 3. Thực hiện ghép nối tất cả ảnh cùng lúc
        cv::Mat result;
        platform_log("Đang ghép %lu ảnh...\n", images.size());
        Stitcher::Status status = stitcher->stitch(images, result);
        platform_log("Kết thúc ghép ảnh.\n");

        // 4. Kiểm tra kết quả
        if (status != Stitcher::OK) {
            std::string errorMessage;
            switch (status) {
                case Stitcher::ERR_NEED_MORE_IMGS:
                    errorMessage = "Not enough images to stitch.";
                    break;
                case Stitcher::ERR_HOMOGRAPHY_EST_FAIL:
                    errorMessage = "Homography estimation failed.";
                    break;
                case Stitcher::ERR_CAMERA_PARAMS_ADJUST_FAIL:
                    errorMessage = "Camera parameters adjustment failed.";
                    break;
                default:
                    errorMessage = "Unknown stitching error.";
                    break;
            }
            platform_log("Can't stitch images, error: %s\n", errorMessage.c_str());
            return;
        }

//
//// === 5. Cắt ảnh theo bill (sử dụng Canny edge detection) ===
//        platform_log("Cropping bill using Canny edge detection...\n");
//
//        Mat grayResult, edges;
//        cvtColor(result, grayResult, COLOR_BGR2GRAY);
//        GaussianBlur(grayResult, grayResult, Size(5, 5), 0); // Giảm nhiễu
//        Canny(grayResult, edges, 50, 150); // Áp dụng Canny edge detection
//
//        // Tìm contours từ edges
//        vector <vector<Point>> contours;
//        findContours(edges, contours, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);
//
//        if (contours.empty()) {
//            platform_log("No contours found. Skipping bill cropping.\n");
//        } else {
//            // Chọn contour lớn nhất
//            int largestContourIndex = 0;
//            double largestContourArea = 0;
//            for (int i = 0; i < contours.size(); i++) {
//                double area = contourArea(contours[i]);
//                if (area > largestContourArea) {
//                    largestContourArea = area;
//                    largestContourIndex = i;
//                }
//            }
//
//            // Tìm bounding rect của contour lớn nhất
//            Rect billRect = boundingRect(contours[largestContourIndex]);
//
//            // Cắt ảnh theo bounding rect
//            result = result(billRect);
//        }
//
//        // === 6. Làm phẳng bill (sử dụng perspective transform) ===
//        platform_log("Flattening bill...\n");
//        // Tìm 4 góc của bill
//        platform_log("Bill rect: x=%d, y=%d, width=%d, height=%d\n", billRect.x, billRect.y,
//                     billRect.width, billRect.height);
//        vector <Point2f> billCorners(4);
//        billCorners[0] = Point2f(billRect.x, billRect.y);                   // Góc trên bên trái
//        billCorners[1] = Point2f(billRect.x + billRect.width,
//                                 billRect.y);          // Góc trên bên phải
//        billCorners[2] = Point2f(billRect.x + billRect.width,
//                                 billRect.y + billRect.height); // Góc dưới bên phải
//        billCorners[3] = Point2f(billRect.x,
//                                 billRect.y + billRect.height);         // Góc dưới bên trái
//
//        // Xác định kích thước ảnh đầu ra sau khi làm phẳng
//        float maxWidth = max(norm(billCorners[0] - billCorners[1]),
//                             norm(billCorners[2] - billCorners[3]));
//        float maxHeight = max(norm(billCorners[1] - billCorners[2]),
//                              norm(billCorners[3] - billCorners[0]));
//        Size outputSize1(maxWidth, maxHeight);
//
//        platform_log("Output size: width=%d, height=%d\n", outputSize1.width, outputSize1.height);
//
//        // Tạo ma trận đích cho perspective transform
//        vector <Point2f> outputCorners(4);
//        outputCorners[0] = Point2f(0, 0);
//        outputCorners[1] = Point2f(outputSize1.width - 1, 0);
//        outputCorners[2] = Point2f(outputSize1.width - 1, outputSize1.height - 1);
//        outputCorners[3] = Point2f(0, outputSize1.height - 1);
//
//        // Tính toán ma trận perspective transform
//        Mat perspectiveTransform1 = getPerspectiveTransform(billCorners, outputCorners);
//
//        platform_log("Perspective transform computed\n");
//
//        // Áp dụng perspective transform để làm phẳng bill
//        warpPerspective(result, result, perspectiveTransform1, outputSize1);
//
//        platform_log("Bill flattened\n");
//
//        platform_log("Stitching completed\n");

        imwrite(outputImagePath, result);

        long long int end = get_now();
        platform_log("Ghép mất %lld ms\n", end - start);
        platform_log("Hình ảnh ghép được lưu tại: %s\n", outputImagePath);

    } catch (const cv::Exception &e) {
        platform_log("Lỗi OpenCV: %s\n", e.what());
    } catch (const std::exception &e) {
        platform_log("Lỗi: %s\n", e.what());
    } catch (...) {
        platform_log("Đã xảy ra lỗi không xác định.\n");
    }
}
}
