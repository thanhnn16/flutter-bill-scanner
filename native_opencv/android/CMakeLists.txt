cmake_minimum_required(VERSION 3.19)
project(NativeOpenCV)

set(OpenCV_DIR ../.././../OpenCV-android-sdk/sdk/native/jni)

# Tìm kiếm thư viện OpenCV với các modules cần thiết:
find_package(OpenCV REQUIRED COMPONENTS core imgcodecs imgproc stitching)
find_library(log-lib log)

message("Building for Android ABI: ${ANDROID_ABI}")
message("OpenCV library path: ${OpenCV_LIBS}")
message("OpenCV include directories: ${OpenCV_INCLUDE_DIRS}")

# Thêm thư viện native:
add_library(native_opencv SHARED ../ios/Classes/native_opencv.cpp ../ios/Classes/bill_stitching.cpp)

# Liên kết thư viện native với OpenCV:
target_link_libraries(native_opencv ${OpenCV_LIBS} ${log-lib})

# Thêm đường dẫn đến thư mục include của OpenCV:
target_include_directories(native_opencv PRIVATE ${OpenCV_INCLUDE_DIRS})