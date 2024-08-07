import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:long_shot_app/widgets/frame/frame_overlay.dart';
import 'package:long_shot_app/widgets/overlay.dart';
import 'package:path_provider/path_provider.dart';

import '../display_image.dart';
import 'native_main.dart';
import 'native_opencv.dart';

class ScanBillScreen extends StatefulWidget {
  const ScanBillScreen({super.key});

  @override
  ScanBillScreenState createState() => ScanBillScreenState();
}

class ScanBillScreenState extends State<ScanBillScreen> {
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
  int _imageCounter = 1; // Start with 1 for the first image filename
  bool _isLoading = false;
  bool _isProcessing = false;

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
      fps: 30,
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

  // // Triggers image stitching in a separate isolate
  // Future<void> _stitchImagesForPreview() async {
  //
  // }

  Future<void> _captureImage() async {
    if (!_isCapturingPicture && _isAligned) {
      setState(() {
        _isCapturingPicture = true;
      });

      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();

      final String fileName = '$_imageCounter.jpg';
      final File file =
          File('${(await getTemporaryDirectory()).path}/$fileName');
      await file.writeAsBytes(bytes);

      _images.add(XFile(file.path, name: fileName));
      _imageCounter++;

      // if (_images.length >= 2) {
      //   _stitchImagesForPreview();
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
        Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      await _captureImage();
    });
  }

  void _stopRecording() async {
    _captureTimer?.cancel();
    _captureTimer = null;

    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
    setState(() {
      _isRecording = false;
      _isCapturingPicture = false;
    });

    if (_images.isEmpty) return;

    await _controller?.pausePreview();

    _processImage();
    // _stitchImagesForPreview();
  }

  // Reset function
  void _reset() {
    _images = [];
    // _stitchedImage = Uint8List(0);
    if (_controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _controller!.resumePreview();
    setState(() {});
  }

  Future<void> _processInIsolate(
      List<String?> imagePaths, String outputPath) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(
      _isolateEntry,
      [receivePort.sendPort, imagePaths, outputPath],
    );

    final result = await receivePort.first;
    if (result is Exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${result.toString()}'),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stitching complete'),
          ),
        );
      }
    }
  }

  static void _isolateEntry(List<dynamic> args) {
    final sendPort = args[0] as SendPort;
    final imagePaths = args[1] as List<String?>;
    final outputPath = args[2] as String;

    try {
      stitchImages(StitchImagesArguments(imagePaths, outputPath));
      sendPort.send('Success');
    } catch (e) {
      sendPort.send(e);
    }
  }

  void _processImage() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _isProcessing = true;
    });

    _images.sort((a, b) => a.name.compareTo(b.name));

    final imagePaths = _images.map((e) => e.path).toList();

    if (imagePaths.isEmpty) {
      setState(() {
        _isLoading = true;
        _isProcessing = true;
      });
      return;
    }

    final outputPath = '${tempDir.path}/stitched_image.jpg';

    await _processInIsolate(imagePaths, outputPath);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DisplayImage(imagePath: outputPath),
        ),
      );
    }

    setState(() {
      _isLoading = true;
      _isProcessing = true;
    });
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
                            // CameraPreview(_controller!),
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
          //           fit: BoxFit.contain,
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
          Positioned(
            bottom: 32,
            right: 32,
            child: IconButton(
              icon: const Icon(Icons.restart_alt_sharp),
              onPressed: _reset,
              color: Colors.white,
            ),
          ),
          if (_isProcessing)
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
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
