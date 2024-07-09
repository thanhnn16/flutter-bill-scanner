import 'package:flutter/material.dart';
import 'package:long_shot_app/long_shot.dart';
import 'package:photo_view/photo_view.dart';

class DisplayImage extends StatelessWidget {
  const DisplayImage({super.key, this.stitchedBytes});

  final dynamic stitchedBytes;

  @override
  Widget build(BuildContext context) {
    // return stitchedBytes == null
    //     ? const Center(child: Text('No image to display'))
    //     : Image.memory(stitchedBytes, );
    return Stack(children: [
      PhotoView(imageProvider: MemoryImage(stitchedBytes)),
      Positioned(
          top: 32,
          right: 32,
          child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (context) => const LongShotApp())
                );
              },
            color: Colors.white,
          ),
      )
    ]);
  }
}
