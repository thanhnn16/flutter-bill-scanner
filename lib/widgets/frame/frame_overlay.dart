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
        // Sử dụng ClipPath để tạo vùng trong khung được hiển thị rõ ràng
        ClipPath(
          clipper: _FrameClipper(
            left: frameLeft,
            top: frameTop,
            width: frameWidth,
            height: frameHeight,
          ),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),
        ),
        // Frame overlay on top
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
class _FrameClipper extends CustomClipper<Path> {
  final double left;
  final double top;
  final double width;
  final double height;

  _FrameClipper({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  Path getClip(Size size) {
    final path = Path();

    // Create the outer rectangle (full screen) as a clockwise path
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Create the inner rectangle (clear frame) as a counter-clockwise hole
    path.addRect(Rect.fromLTWH(left, top, width, height));
    path.fillType = PathFillType.evenOdd;

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}