#include <opencv2/opencv.hpp>
#include <chrono>
#include <vector>
#include "bill_stitching.h"

#ifdef __ANDROID__
#include <android/log.h>
#endif
using namespace cv;
using namespace cv::detail;

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


// Avoiding name mangling
extern "C" {
const char *version() {
    return CV_VERSION;
}

void stitch_images(const char **imagePaths, int numImages, char *outputImagePath) {
    std::vector <cv::Mat> images;
    for (int i = 0; i < numImages; ++i) {
        images.push_back(cv::imread(imagePaths[i]));
        platform_log("Loaded image at path: %s\n", imagePaths[i]);
        if (images.back().empty()) {
            platform_log("Failed to load image at path: %s\n", imagePaths[i]);
            return;
        }
    }
    for (int i = 0; i < numImages; ++i) {
        images.push_back(cv::imread(imagePaths[i]));
    }

    try {
        long long int start = get_now();

        Mat pano = stitchBills(images);

        imwrite(outputImagePath, pano);
        long long int end = get_now();

        platform_log("Stitching took %lld ms\n", end - start);
        platform_log("Stitched image saved at path: %s\n", outputImagePath);

    } catch (const Exception &e) {
        platform_log("OpenCV exception: %s\n", e.what());
    } catch (const std::exception &e) {
        platform_log("Exception: %s\n", e.what());
    } catch (...) {
        platform_log("Unknown exception occurred.\n");
    }
}
}
