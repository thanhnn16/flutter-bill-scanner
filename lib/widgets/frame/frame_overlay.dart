import 'package:flutter/material.dart';

class FramePainter extends CustomPainter {
  final double cornerLength;
  final double strokeWidth;
  final Color color;

  FramePainter({
    this.cornerLength = 20.0,
    this.strokeWidth = 5.0,
    this.color = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Top left corner
    canvas.drawLine(Offset(0, cornerLength), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(cornerLength, 0), paint);

    // Top right corner
    canvas.drawLine(Offset(size.width - cornerLength, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);

    // Bottom left corner
    canvas.drawLine(Offset(0, size.height - cornerLength), Offset(0, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);

    // Bottom right corner
    canvas.drawLine(Offset(size.width - cornerLength, size.height), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class FrameOverlay extends StatelessWidget {
  const FrameOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 64, // Adjust based on desired frame size and position
      right: 64,
      top: 150,
      bottom: 150,
      child: CustomPaint(
        painter: FramePainter(),
      ),
    );
  }
}