import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:long_shot_app/native/native_main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';

class DisplayImage extends StatefulWidget {
  final String imagePath;

  const DisplayImage({super.key, required this.imagePath});

  @override
  State<DisplayImage> createState() => _DisplayImageState();
}

class _DisplayImageState extends State<DisplayImage> {
  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PhotoView(
            key: _imageKey,
            imageProvider: Image.file(File(widget.imagePath)).image,
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
                        builder: (context) => const NativeMain()));
              },
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
