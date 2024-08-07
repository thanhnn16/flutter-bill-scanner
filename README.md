
# Flutter Native OpenCV
[Nguồn tham khảo](https://github.com/westracer/flutter_native_opencv)

Read the full articles:
- Mobile platorms: https://medium.com/flutter-community/integrating-c-library-in-a-flutter-app-using-dart-ffi-38a15e16bc14

# How to build & run (OpenCV version: `4.10.0`)
## Android and iOS

Run `init.sh` script from a `scripts` folder or do the following steps manually:

1. Download OpenCV for Android and iOS: https://opencv.org/releases/
2. Copy or create symlinks:
    - `opencv2.framework` to `native_opencv/ios`
    - `OpenCV-android-sdk/sdk/native/jni/include` to `native_opencv`
    - Contents of `OpenCV-android-sdk/sdk/native/libs/**` to `native_opencv/android/src/main/jniLibs/**`

## Windows

Run `init_windows.ps1` PowerShell script from a `scripts` folder or do the following steps manually:

1. Download OpenCV for Windows: https://opencv.org/releases/
2. Unpack it. Set env. variable `OpenCV_DIR` to unpacked `...\opencv\build` folder
3. Create a hard link from `native_opencv\ios\Classes\native_opencv.cpp` to `native_opencv_windows\windows\native_opencv.cpp`
4. Make sure `native_opencv_windows\windows\CMakeLists.txt` contains correct .dll names (OpenCV_DEBUG_DLL_NAME,OpenCV_RELEASE_DLL_NAME)

## macOS

Before doing anything else, you need to download OpenCV source code and
build a framework by running `opencv/platforms/apple/build_xcframework.py` script.

Run `init_macos.sh` script from a `scripts` folder or do the following steps manually:

1. Create a hard link from `native_opencv/ios/Classes/native_opencv.cpp` to `native_opencv_macos/macos/Classes/native_opencv.cpp`
2. Copy `opencv2.xcframework` to `native_opencv/macos`

# Sửa logic xử lý ảnh
- Sửa logic xử lý ảnh trong file `native_opencv/ios/Classes/native_opencv.cpp` (hiện đang sử dụng logic trong file `native_opencv.cpp`) hoặc `native_opencv/ios/Classes/bill_stitching.cpp`
- [OpenCV 4.10.0 Documentation](https://docs.opencv.org/4.10.0/)
- [Stitching Documentation](https://docs.opencv.org/4.10.0/d1/d46/group__stitching.html)
- 