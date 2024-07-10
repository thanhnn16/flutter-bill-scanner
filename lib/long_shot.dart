import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:long_shot_app/widgets/overlay.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'display_image.dart';

class LongShotApp extends StatefulWidget {
  const LongShotApp({super.key});

  @override
  LongShotAppState createState() => LongShotAppState();
}

Future<Uint8List> _stitchImagesIsolate(List<Uint8List> imageDataList) async {
  List<cv.Mat> matImages = [];
  for (var imageData in imageDataList) {
    final image = await cv.imdecodeAsync(imageData, cv.COLOR_YUV2BGR_NV21);
    var resizedImage =
        await cv.resizeAsync(image, (200, 320), interpolation: cv.INTER_AREA);
    matImages.add(resizedImage);
  }

  final stitcher = cv.Stitcher.create(mode: cv.StitcherMode.SCANS);
  final vecMat = cv.VecMat.fromList(matImages);
  final stitchResult = stitcher.stitch(vecMat);

  final stitchedBytes = await cv.imencodeAsync('.jpg', stitchResult.$2);

  // Clean up OpenCV Mats
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
  var _stitchedImage = Uint8List(0);
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
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
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
  Future<void> _stitchImagesForPreview() async {
    List<Uint8List> imageDataList = [];
    for (var xFile in _images) {
      imageDataList.add(await xFile.readAsBytes());
    }
    final stitchedImage = await compute(_stitchImagesIsolate, imageDataList);

    if (mounted) {
      setState(() {
        _stitchedImage = stitchedImage;
      });
    }
  }

  Future<void> _captureImage() async {
    if (!_isCapturingPicture && _isAligned) {
      setState(() {
        _isCapturingPicture = true;
      });

      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final decodedImage = await cv.imdecodeAsync(bytes, cv.IMREAD_COLOR);

      // Define the frame dimensions
      // const frameLeft = 0;
      // const frameTop = 0;
      // final frameWidth = (_controller!.value.previewSize!.width).toInt();
      // final frameHeight =
      //     (_controller!.value.previewSize!.height).toInt();
      //
      // // Crop the image to the frame dimensions
      // final croppedImage = await cv.getRectSubPixAsync(
      //   decodedImage,
      //   (frameWidth, frameHeight),
      //   cv.Point2f((frameLeft + frameWidth / 2).toDouble(),
      //       (frameTop + frameHeight / 2).toDouble()),
      // );

      final croppedBytes = await cv.imencodeAsync('.jpg', decodedImage);

      _images.add(XFile.fromData(croppedBytes.$2, name: image.name));
      if (_images.length >= 2) {
        await _stitchImagesForPreview();
      }

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
        Timer.periodic(const Duration(milliseconds: 300), (timer) async {
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
    if (kDebugMode) {
      print('Stop recording');
    }
    _stitchImagesForPreview();
    await _controller?.pausePreview();
    _stitchImages(navigateAfterStitching: true);
  }

  // Stitches images in the background using compute
  Future<void> _stitchImages({required bool navigateAfterStitching}) async {
    List<cv.Mat> matImages = [];

    List<XFile> imagesCopy = List<XFile>.from(_images);
    for (var xFile in imagesCopy) {
      final bytes = await xFile.readAsBytes();
      final image = await cv.imdecodeAsync(bytes, cv.IMREAD_COLOR);
      matImages.add(image);
    }

    final stitcher = cv.Stitcher.create(mode: cv.StitcherMode.SCANS);
    final vecMat = cv.VecMat.fromList(matImages);
    final stitchResult = stitcher.stitch(vecMat);

    // Convert to grayscale
    final grayImage =
        await cv.cvtColorAsync(stitchResult.$2, cv.COLOR_BGR2GRAY);

    // Apply adaptive thresholding
    final thresholdImage = await cv.adaptiveThresholdAsync(
        grayImage, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, 11, 2);

    // Apply contrast enhancement
    final contrastEnhancedImage =
        await cv.convertScaleAbsAsync(thresholdImage, alpha: 3, beta: 0);

    // Apply histogram equalization
    final equalizedImage = await cv.equalizeHistAsync(contrastEnhancedImage);

    // Apply Gaussian blur to reduce noise
    final blurredImage = await cv.gaussianBlurAsync(equalizedImage, (4, 4), 0);

    // Use Morphological Operations to enhance text
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (1, 1));
    final dilatedImage = await cv.dilateAsync(equalizedImage, kernel);

    // Encode the processed image to bytes
    final processedBytes = await cv.imencodeAsync('.png', dilatedImage);

    if (navigateAfterStitching && mounted) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  DisplayImage(stitchedBytes: processedBytes.$2)));
    } else if (mounted) {
      setState(() {
        _stitchedImage = processedBytes.$2;
      });
    }

    // Clean up OpenCV Mats
    for (var matImage in matImages) {
      matImage.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _controller != null && _controller!.value.isInitialized
                ? GestureDetector(
                    onTapUp: (details) {
                      final screenSize = MediaQuery.of(context).size;
                      final x = details.localPosition.dx / screenSize.width;
                      final y = details.localPosition.dy / screenSize.height;
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
                    child: CameraPreview(_controller!))
                : const Center(child: CircularProgressIndicator()),
          ),
          AlignmentOverlay(
            onAlignmentChange: (aligned) {
              setState(() {
                _isAligned = aligned;
              });
            },
          ),
          OverlayPreview(
            child: _stitchedImage.isNotEmpty
                ? Image.memory(_stitchedImage,
                    fit: BoxFit.cover,
                    width: 150,
                    height: MediaQuery.of(context).size.height / 2 -
                        10) // Adjust the size of the preview
                : Container(
                    color: Colors.black,
                    width: 150, // Adjust the size of the preview
                    height: MediaQuery.of(context).size.height / 2 -
                        10, // Adjust the size of the preview
                  ),
          ),
          // Positioned(
          //   bottom: 10,
          //   left: 10,
          //   child: IconButton(
          //     icon: const Icon(Icons.flash_on),
          //     onPressed: () async {
          //       await _controller?.setFlashMode(
          //           _controller!.value.flashMode == FlashMode.off
          //               ? FlashMode.torch
          //               : FlashMode.off);
          //     },
          //   ),
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
    return Positioned(
      left: 10,
      top: MediaQuery.of(context).size.height / 2 - 150,
      child: Container(
        width: MediaQuery.of(context).size.width / 6,
        height: MediaQuery.of(context).size.height / 3,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );
  }
}
