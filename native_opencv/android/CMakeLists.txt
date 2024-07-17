cmake_minimum_required(VERSION 3.19)
project(NativeOpenCV)

# Include the OpenCV headers
include_directories(../include)

# Import the OpenCV library
add_library(lib_opencv SHARED IMPORTED)
set_target_properties(lib_opencv PROPERTIES IMPORTED_LOCATION
        ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libopencv_java4.so)

# Ensure the OpenCV library was found
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libopencv_java4.so)
    message(FATAL_ERROR "OpenCV library not found at ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libopencv_java4.so")
endif()

# Find the log library
find_library(log-lib log)

# Add your native library
add_library(native_opencv SHARED ../ios/Classes/native_opencv.cpp)

# Link your native library with OpenCV and log library
target_link_libraries(native_opencv lib_opencv ${log-lib})
