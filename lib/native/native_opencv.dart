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

  // Allocate memory for an array of pointers to char*
  final ffi.Pointer<ffi.Pointer<Utf8>> pathsPtr =
  malloc.allocate<ffi.Pointer<Utf8>>(ffi.sizeOf<ffi.Pointer<Utf8>>() * numImages);

  // Convert Dart strings to UTF-8 encoded byte arrays and assign to the array
  for (int i = 0; i < numImages; i++) {
    final ffi.Pointer<Utf8>? charPtr = imagePaths[i]?.toNativeUtf8();
    pathsPtr[i] = charPtr!;
  }

  // Call the C++ function
  _stitchImages(pathsPtr, numImages, args.outputPath.toNativeUtf8());

  // Free allocated memory (important to avoid memory leaks!)
  for (int i = 0; i < numImages; i++) {
    malloc.free(pathsPtr[i]);
  }
  malloc.free(pathsPtr);
}

class StitchImagesArguments {
  final List<String?> imagePaths;
  final String outputPath;

  StitchImagesArguments(this.imagePaths, this.outputPath);
}
