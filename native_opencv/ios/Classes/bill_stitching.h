#ifndef BILL_STITCHING_H
#define BILL_STITCHING_H
#include <opencv2/opencv.hpp>
#include <vector>

cv::Mat stitchBills(const std::vector <cv::Mat> &images); // khai báo hàm

#endif
