#include "opencv2/opencv.hpp"
#include "chrono"
#include "vector"
#include "bill_stitching.hpp"
#include <algorithm>
#include <ctime>
#include <string>

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

Mat preprocess(Mat img) {
    platform_log("Bắt đầu tiền xử lý ảnh...\n");
    // 1. Cân bằng sáng (CLAHE)
    cvtColor(img, img, COLOR_BGR2Lab);
    vector<Mat> channels;

    platform_log("Cân bằng sáng ảnh...\n");
    split(img, channels);
    Ptr<CLAHE> clahe = createCLAHE(2.0, Size(8, 8));
    clahe->apply(channels[0], channels[0]);

    platform_log("Merge ảnh...\n");
    merge(channels, img);
    cvtColor(img, img, COLOR_Lab2BGR);

    platform_log("Kết thúc tiền xử lý ảnh.\n");

    platform_log("Loại bỏ nhiễu ảnh...\n");
    // 2. Loại bỏ nhiễu (Gaussian Blur)
    GaussianBlur(img, img, Size(3, 3), 0);
    platform_log("Kết thúc loại bỏ nhiễu ảnh.\n");

    return img;
}

extern "C" {
const char *version() {
    return CV_VERSION;
}

void stitch_images(const char **imagePaths, int numImages, char *outputImagePath) {

    std::vector<std::string> imagePathsVector(imagePaths, imagePaths + numImages);

    // Sắp xếp tên ảnh theo thứ tự tăng dần
    platform_log("Đang sắp xếp tên ảnh theo thứ tự tăng dần...\n");
    std::sort(imagePathsVector.begin(), imagePathsVector.end(), compareNatural);
    platform_log("Sắp xếp tên ảnh xong.\n");
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
        Mat resized;
        platform_log("Kích thước ảnh gốc: %dx%d\n", img.cols, img.rows);
        resize(img, resized, Size(), 0.5, 0.5); // Giảm kích thước xuống 50%
        platform_log("Kích thước ảnh sau khi giảm: %dx%d\n", resized.cols, resized.rows);
        // Tiền xử lý ảnh
        resized = preprocess(resized);
//        img = preprocess(img);
        images.push_back(resized);
    }

    try {
        long long int start = get_now();

        // 1. Khởi tạo Stitcher
        Ptr<Stitcher> stitcher = Stitcher::create(Stitcher::SCANS);
        // 2. Tùy chỉnh các tham số
//        stitcher->setRegistrationResol(0.75);    // Giảm nhẹ để tăng tốc độ, có thể thử nghiệm từ 0.6 - 0.8
//        stitcher->setSeamEstimationResol(0.75); // Giống RegistrationResol
        stitcher->setCompositingResol(1);      // Giữ nguyên để đảm bảo độ phân giải ảnh kết quả
        stitcher->setPanoConfidenceThresh(0.94);  // Tăng lên để loại bỏ ghép nối sai, giá trị thử nghiệm từ 0.7 - 0.9
//        stitcher->setFeaturesFinder(SIFT::create());
        stitcher->setFeaturesFinder(ORB::create(7600)); // Giảm số lượng features để tăng tốc độ, thử nghiệm từ 3000 - 8000
        // Ngoài ra, có thể thử nghiệm với các features khác như SIFT, BRISK, AKAZE
//        stitcher->setWaveCorrection(false);     // Tắt, không cần thiết cho scan bill
        // Bỏ qua ExposureCompensator vì ánh sáng khi scan thường đồng đều
        // stitcher->setExposureCompensator(ExposureCompensator::createDefault(ExposureCompensator::GAIN_BLOCKS));
        stitcher->setBlender(Blender::createDefault(Blender::MULTI_BAND,
                                                    false)); // Giữ nguyên, vẫn cần blender cho kết quả tốt nhất

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
                    errorMessage = "Không đủ ảnh để ghép.";
                    break;
                case Stitcher::ERR_HOMOGRAPHY_EST_FAIL:
                    errorMessage = "Ước lượng đồng nhất không thành công.";
                    break;
                case Stitcher::ERR_CAMERA_PARAMS_ADJUST_FAIL:
                    errorMessage = "Điều chỉnh tham số camera không thành công.";
                    break;
                default:
                    errorMessage = "Lỗi không xác định.";
                    break;
            }
            platform_log("Không thể ghép ảnh: %s\n", errorMessage.c_str());
            return;
        }


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
