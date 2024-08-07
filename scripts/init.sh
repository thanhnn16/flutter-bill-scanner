mkdir -p download
cd download || exit

wget -O opencv-4.10.0-android-sdk.zip https://sourceforge.net/projects/opencvlibrary/files/4.10.0/opencv-4.10.0-android-sdk.zip/download
wget -O opencv-4.10.0-ios-framework.zip https://sourceforge.net/projects/opencvlibrary/files/4.10.0/opencv-4.10.0-ios-framework.zip/download

unzip opencv-4.10.0-android-sdk.zip
unzip opencv-4.10.0-ios-framework.zip

cp -r opencv2.framework ../../native_opencv/ios
cp -r OpenCV-android-sdk/sdk/native/jni/include ../../native_opencv
mkdir -p ../../native_opencv/android/src/main/jniLibs/
cp -r OpenCV-android-sdk/sdk/native/libs/* ../../native_opencv/android/src/main/jniLibs/

echo "Done"