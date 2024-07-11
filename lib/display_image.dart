import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:long_shot_app/long_shot.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:photo_view/photo_view.dart';

class DisplayImage extends StatefulWidget {
  final cv.Mat stitchedMat; // Use cv.Mat instead of Uint8List

  const DisplayImage({super.key, required this.stitchedMat});

  @override
  State<DisplayImage> createState() => _DisplayImageState();
}

class _DisplayImageState extends State<DisplayImage> {
  cv.Mat? processedImage; // Store the processed image
  final GlobalKey _imageKey = GlobalKey();
  bool _isLoading = false; // Add isLoading state

  @override
  void initState() {
    super.initState();
    _processImage(); // Process image after build
  }

  @override
  void dispose() {
    processedImage?.dispose();
    super.dispose();
  }

  Future<void> _processImage() async {
    setState(() {
      _isLoading = true;
    });

    // Simulate getting crop parameters - you'll replace this with actual logic
    // final cropParameters = await _getCropParameters(widget.stitchedMat);
    // processedImage = await _cropAndEnhance(widget.stitchedMat, cropParameters);

    // final grayImage =
    //     await cv.cvtColorAsync(widget.stitchedMat, cv.COLOR_BGR2GRAY);
    //
    // final thresholdImage =
    //     await cv.thresholdAsync(grayImage, 200, 255, cv.THRESH_BINARY);
    //
    // final enhancedImage = await cv.equalizeHistAsync(thresholdImage.$2);

    processedImage = widget.stitchedMat;

    setState(() {
      _isLoading = false;
    });
  }

  Future<Uint8List?> _encodeImage() async {
    if (processedImage != null) {
      final encoded = await cv.imencodeAsync('.png', processedImage!);
      return Uint8List.fromList(encoded.$2);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            FutureBuilder<Uint8List?>(
              future: _encodeImage(), // Gọi hàm async
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData &&
                    snapshot.data != null) {
                  return PhotoView(
                    key: _imageKey,
                    imageProvider: MemoryImage(snapshot.data!),
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          Positioned(
            top: 32,
            right: 32,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LongShotApp()));
              },
              color: Colors.white,
            ),
          )
        ],
      ),
    );
  }
}
