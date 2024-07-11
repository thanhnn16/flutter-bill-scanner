import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:long_shot_app/widgets/frame/frame_overlay.dart';
import 'package:long_shot_app/widgets/overlay.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'display_image.dart';

class LongShotApp extends StatefulWidget {
  const LongShotApp({super.key});

  @override
  LongShotAppState createState() => LongShotAppState();
}

// Future<Uint8List> _stitchImagesPreviewIsolate(
//     List<Uint8List> imageDataList) async {
//   List<cv.Mat> matImages = [];
//   for (var imageData in imageDataList) {
//     final image = await cv.imdecodeAsync(imageData, cv.COLOR_YUV2BGR_NV21);
//     var resizedImage =
//         await cv.resizeAsync(image, (200, 320), interpolation: cv.INTER_AREA);
//     matImages.add(resizedImage);
//   }
//
//   final stitcher = cv.Stitcher.create(mode: cv.StitcherMode.SCANS);
//   final vecMat = cv.VecMat.fromList(matImages);
//   final stitchResult = stitcher.stitch(vecMat);
//
//   final stitchedBytes = await cv.imencodeAsync('.jpg', stitchResult.$2);
//
//   // Clean up OpenCV Mats
//   for (var matImage in matImages) {
//     matImage.dispose();
//   }
//
//   return stitchedBytes.$2;
// }

Future<Uint8List> _stitchImagesIsolate(List<Uint8List> imageDataList) async {
  List<cv.Mat> matImages = [];
  for (var imageData in imageDataList) {
    final image = await cv.imdecodeAsync(imageData, cv.COLOR_YUV2BGR_NV21);
    matImages.add(image);
  }

  final stitcher = cv.Stitcher.create(mode: cv.StitcherMode.SCANS);
  final vecMat = cv.VecMat.fromList(matImages);
  final stitchResult = stitcher.stitch(vecMat);

  final stitchedBytes = await cv.imencodeAsync('.png', stitchResult.$2);

  for (var matImage in matImages) {
    matImage.dispose();
  }
  return stitchedBytes.$2;
}

class LongShotAppState extends State<LongShotApp> {
  CameraController? _controller;
  List<XFile> _images = [];
  bool _isRecording = false;
  bool _isCapturingPicture = false;
  Timer? _captureTimer;
  bool _isAligned = false;
  // var _stitchedImage = Uint8List(0);
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  late double maxAllowedZoomLevel;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;
    _controller = CameraController(
      firstCamera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();

    await _controller!.setFocusMode(FocusMode.auto);

    await _controller!.setFlashMode(FlashMode.off);

    maxAllowedZoomLevel = await _controller!.getMaxZoomLevel();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Triggers image stitching in a separate isolate
  // Future<void> _stitchImagesForPreview() async {
  //   List<Uint8List> imageDataList = [];
  //   for (var xFile in _images) {
  //     imageDataList.add(await xFile.readAsBytes());
  //   }
  //   final stitchedImage =
  //       await compute(_stitchImagesPreviewIsolate, imageDataList);
  //
  //   if (mounted) {
  //     setState(() {
  //       _stitchedImage = stitchedImage;
  //     });
  //   }
  // }

  Future<void> _captureImage() async {
    if (!_isCapturingPicture && _isAligned) {
      setState(() {
        _isCapturingPicture = true;
      });

      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final decodedImage = await cv.imdecodeAsync(bytes, cv.IMREAD_COLOR);

      final croppedBytes = await cv.imencodeAsync('.jpg', decodedImage);

      _images.add(XFile.fromData(croppedBytes.$2, name: image.name));
      // if (_images.length >= 2) {
      //   await _stitchImagesForPreview();
      // }

      if (mounted) {
        setState(() {
          _isCapturingPicture = false;
        });
      }
    }
  }

  void _startRecording() async {
    setState(() {
      _isRecording = true;
    });
    _images = [];
    await _captureImage();
    _captureTimer =
        Timer.periodic(const Duration(milliseconds: 350), (timer) async {
      await _captureImage();
    });
  }

  void _stopRecording() async {
    await _captureImage();
    _captureTimer?.cancel();
    _captureTimer = null;

    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
    setState(() {
      _isRecording = false;
      _isCapturingPicture = false;
    });

    // _stitchImagesForPreview();
    await _controller?.pausePreview();
    _stitchImages(navigateAfterStitching: true);
  }

  // Stitches images in the background using compute
  Future<void> _stitchImages({required bool navigateAfterStitching}) async {
    if (_images.length < 2) {
      return;
    }
    if (navigateAfterStitching) {
      showDialog(
        context: context,
        builder: (context) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );
    }
    List<Uint8List> imageDataList = [];
    for (var xFile in _images) {
      imageDataList.add(await xFile.readAsBytes());
    }
    final stitchedImage = await compute(_stitchImagesIsolate, imageDataList);

    if (navigateAfterStitching && mounted) {
      Navigator.pop(context);
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => DisplayImage(
                    stitchedBytes: stitchedImage,
                  )));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AspectRatio(
              aspectRatio:
                  _controller != null && _controller!.value.isInitialized
                      ? _controller!.value.aspectRatio
                      : 1.0,
              child: _controller != null && _controller!.value.isInitialized
                  ? CameraPreview(
                      _controller!,
                      child: GestureDetector(
                        onTapUp: (details) {
                          final screenSize = MediaQuery.of(context).size;
                          final x = details.localPosition.dx / screenSize.width;
                          final y =
                              details.localPosition.dy / screenSize.height;
                          final focusPoint = Offset(x, y);
                          _controller!.setFocusPoint(focusPoint);
                        },
                        onScaleStart: (_) {
                          _baseZoomLevel = _currentZoomLevel;
                        },
                        onScaleUpdate: (details) async {
                          _currentZoomLevel = (_baseZoomLevel * details.scale)
                              .clamp(1.0, maxAllowedZoomLevel);
                          await _controller!.setZoomLevel(_currentZoomLevel);
                        },
                        child: Stack(
                          children: [
                            FrameOverlay(
                              frameLeft: 0,
                              frameTop: 0,
                              frameWidth: MediaQuery.of(context).size.width,
                              frameHeight: MediaQuery.of(context).size.height,
                            ),
                            AlignmentOverlay(
                              onAlignmentChange: (aligned) {
                                setState(() {
                                  _isAligned = aligned;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
          // OverlayPreview(
          //   child: _stitchedImage.isNotEmpty
          //       ? Image.memory(_stitchedImage,
          //           fit: BoxFit.cover,
          //           width: MediaQuery.of(context).size.width / 4,
          //           height: MediaQuery.of(context).size.height / 4)
          //       : Container(
          //           color: Colors.white,
          //           width: MediaQuery.of(context).size.width /
          //               4, // Adjust the size of the preview
          //           height: MediaQuery.of(context).size.height /
          //               4, // Adjust the size of the preview
          //         ),
          // ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isRecording ? _stopRecording : _startRecording,
        label: Text(_isRecording ? 'Stop' : 'Start'),
        icon: Icon(_isRecording ? Icons.stop : Icons.camera),
      ),
    );
  }
}

class OverlayPreview extends StatelessWidget {
  final Widget child;

  const OverlayPreview({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Positioned(
      left: screenSize.width / 2 - (screenSize.width / 4) / 2,
      top: 0,
      child: child,
    );
  }
}
