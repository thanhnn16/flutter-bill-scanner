#include <opencv2/opencv.hpp>
#include <chrono>
#include <vector>
#include <opencv2/stitching.hpp>

#ifdef __ANDROID__
#include <android/log.h>
#endif

#if defined(__GNUC__)
// Attributes to prevent 'unused' function from being removed and to make it visible
#define FUNCTION_ATTRIBUTE __attribute__((visibility("default"))) __attribute__((used))
#elif defined(_MSC_VER)
// Marking a function for export
#define FUNCTION_ATTRIBUTE __declspec(dllexport)
#endif

using namespace cv;
using namespace std;

long long int get_now() {
    return chrono::duration_cast<std::chrono::milliseconds>(
            chrono::system_clock::now().time_since_epoch()
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

// Avoiding name mangling
extern "C" {
FUNCTION_ATTRIBUTE
const char *version() {
    return CV_VERSION;
}

FUNCTION_ATTRIBUTE
void stitch_images(const char **imagePaths, int numImages, char *outputImagePath) {
    std::vector <cv::Mat> images;
    for (int i = 0; i < numImages; ++i) {
        images.push_back(cv::imread(imagePaths[i]));
        // Make sure to check for successful image loading
        if (images.back().empty()) {
            platform_log("Failed to load image at path: %s\n", imagePaths[i]);
            // Handle error appropriately
        }
    }
    for (int i = 0; i < numImages; ++i) {
        images.push_back(cv::imread(imagePaths[i]));
    }

    try {
        cv::Mat pano;
        cv::Stitcher::Mode mode = cv::Stitcher::SCANS;
        cv::Ptr <cv::Stitcher> stitcher = cv::Stitcher::create(mode);
        cv::Stitcher::Status status = stitcher->stitch(images, pano);

        if (status != cv::Stitcher::OK) {
            platform_log("Stitching failed.\n");
            return;
        } else {
            cv::imwrite(outputImagePath, pano);
            platform_log("Stitching completed successfully.\n");
        }
    } catch (const cv::Exception &e) {
        platform_log("OpenCV exception: %s\n", e.what());
    } catch (const std::exception &e) {
        platform_log("Exception: %s\n", e.what());
    } catch (...) {
        platform_log("Unknown exception occurred.\n");
    }
}
}
