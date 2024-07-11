import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:long_shot_app/long_shot.dart';
import 'package:photo_view/photo_view.dart';

class DisplayImage extends StatefulWidget {
  final Uint8List stitchedBytes;

  const DisplayImage({super.key, required this.stitchedBytes});

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
                  imageProvider: MemoryImage(widget.stitchedBytes),
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