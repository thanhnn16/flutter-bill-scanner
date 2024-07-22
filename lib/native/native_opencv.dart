// native_opencv.dart
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// C function signatures
typedef _CVersionFunc = ffi.Pointer<Utf8> Function();
typedef _CStitchImagesFunc = ffi.Void Function(
    ffi.Pointer<ffi.Pointer<Utf8>>,
    ffi.Int32,
    ffi.Pointer<Utf8>,
    );

// Dart function signatures
typedef _VersionFunc = ffi.Pointer<Utf8> Function();
typedef _StitchImagesFunc = void Function(
    ffi.Pointer<ffi.Pointer<Utf8>>,
    int,
    ffi.Pointer<Utf8>,
    );

// Getting a library that holds needed symbols
ffi.DynamicLibrary _openDynamicLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libnative_opencv.so');
  }
  return ffi.DynamicLibrary.process();
}

ffi.DynamicLibrary _lib = _openDynamicLibrary();

// Looking for the functions
final _VersionFunc _version =
_lib.lookup<ffi.NativeFunction<_CVersionFunc>>('version').asFunction();

final _StitchImagesFunc _stitchImages = _lib
    .lookup<ffi.NativeFunction<_CStitchImagesFunc>>('stitch_images')
    .asFunction();

String opencvVersion() {
  return _version().toDartString();
}

void stitchImages(StitchImagesArguments args) {
  final imagePaths = args.imagePaths;
  final int numImages = imagePaths.length;

  // Get timestamps of images
  final List<int> timestamps = imagePaths.map((imagePath) {
    return File(imagePath!).lastModifiedSync().millisecondsSinceEpoch;
  }).toList();

  // Allocate memory for timestamps
  final ffi.Pointer<ffi.Int64> timestampsPtr =
  malloc.allocate<ffi.Int64>(ffi.sizeOf<ffi.Int64>() * numImages);

  // Copy timestamps to native memory
  for (int i = 0; i < numImages; i++) {
    timestampsPtr[i] = timestamps[i];
  }

  // Allocate memory for image paths
  final ffi.Pointer<ffi.Pointer<Utf8>> pathsPtr =
  malloc.allocate<ffi.Pointer<Utf8>>(
      ffi.sizeOf<ffi.Pointer<Utf8>>() * numImages);

  for (int i = 0; i < numImages; i++) {
    final ffi.Pointer<Utf8> charPtr = imagePaths[i]!.toNativeUtf8();
    pathsPtr[i] = charPtr;
  }

  // Call the C++ function
  _stitchImages(pathsPtr, numImages, args.outputPath.toNativeUtf8());

  // Free allocated memory
  for (int i = 0; i < numImages; i++) {
    malloc.free(pathsPtr[i]);
  }
  malloc.free(pathsPtr);
  malloc.free(timestampsPtr);
}

class StitchImagesArguments {
  final List<String?> imagePaths;
  final String outputPath;

  StitchImagesArguments(this.imagePaths, this.outputPath);
}
