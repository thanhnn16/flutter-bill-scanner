import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class FramePainter extends CustomPainter {
  final double strokeWidth;
  final Color color;

  FramePainter({
    this.strokeWidth = 5.0,
    this.color = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Draw the rectangle frame
    final rect = Rect.fromLTWH(64, 150, size.width - 128, size.height - 300);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class FrameOverlay extends StatelessWidget {
  final double frameLeft;
  final double frameTop;
  final double frameWidth;
  final double frameHeight;

  const FrameOverlay({
    super.key,
    required this.frameLeft,
    required this.frameTop,
    required this.frameWidth,
    required this.frameHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipPath(
            clipper: FrameClipper(
              frameLeft: frameLeft,
              frameTop: frameTop,
              frameWidth: frameWidth,
              frameHeight: frameHeight,
            ),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Container(
                color: Colors.black.withOpacity(0),
              ),
            ),
          ),
        ),
        Positioned(
          left: frameLeft,
          top: frameTop,
          width: frameWidth,
          height: frameHeight,
          child: CustomPaint(
            painter: FramePainter(),
          ),
        ),
      ],
    );
  }
}

class FrameClipper extends CustomClipper<Path> {
  final double frameLeft;
  final double frameTop;
  final double frameWidth;
  final double frameHeight;

  FrameClipper({
    required this.frameLeft,
    required this.frameTop,
    required this.frameWidth,
    required this.frameHeight,
  });

  @override
  Path getClip(Size size) {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(frameLeft, frameTop, frameWidth, frameHeight))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}