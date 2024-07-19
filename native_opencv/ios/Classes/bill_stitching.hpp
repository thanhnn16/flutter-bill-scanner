#ifndef BILL_STITCHING_HPP
#define BILL_STITCHING_HPP

#include "opencv2/core/core.hpp"
#include "opencv2/imgproc/imgproc.hpp"

namespace cv {
    namespace bill_stitching {
        cv::Mat stitchBills(const std::vector<cv::Mat>& images);
    }
}

#endif //BILL_STITCHING_HPP