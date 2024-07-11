import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;

class AlignmentOverlay extends StatefulWidget {
  final Function(bool) onAlignmentChange;

  const AlignmentOverlay({super.key, required this.onAlignmentChange});

  @override
  AlignmentOverlayState createState() => AlignmentOverlayState();
}

class AlignmentOverlayState extends State<AlignmentOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _arrowAnimation;

  final double _arrowWidth = 50.0;
  bool _isMisaligned = false;
  String _alignmentMessage = 'Giữ điện thoại thẳng đứng';
  final double _tiltThreshold = 15.0;
  StreamSubscription<dynamic>? _sensorSubscription;

  double _tiltAngle = 0.0;

  final KalmanFilter _kalmanFilter = KalmanFilter();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _arrowAnimation = Tween<double>(begin: -1.0, end: 1.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));

    _startListening();
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startListening() {
    final accelerometerStream = accelerometerEventStream();

    _sensorSubscription = accelerometerStream
        .sampleTime(const Duration(milliseconds: 50))
        .listen((accelEvent) {
      _updateAlignment(accelEvent);
    });
  }

void _updateAlignment(AccelerometerEvent accelEvent) {
  double tiltAngle = _calculateTiltAngle(accelEvent.x, accelEvent.y, accelEvent.z);
  _tiltAngle = _kalmanFilter.filter(tiltAngle);

  bool isAligned = (_tiltAngle.abs() <= _tiltThreshold);
  if (mounted) {
    double normalizedTilt = (_tiltAngle / _tiltThreshold).clamp(-1.0, 1.0);
    double arrowPosition = (normalizedTilt + 1) / 2;
    bool isWithinMiddleQuarter = arrowPosition >= 0.4 && arrowPosition <= 0.6;

    if (_isMisaligned != !isAligned || !isWithinMiddleQuarter) {
      setState(() {
        _isMisaligned = !isAligned || !isWithinMiddleQuarter;
        _alignmentMessage = _isMisaligned ? "Giữ điện thoại thẳng đứng" : "Di chuyển camera chậm để quét";
      });
      widget.onAlignmentChange(!_isMisaligned);
    }

    _animationController.animateTo(arrowPosition, curve: Curves.easeInOut);
  }
}

  double _calculateTiltAngle(double x, double y, double z) {
    return math.atan2(x, math.sqrt(y * y + z * z)) * (180 / math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double dividerWidth = screenSize.width / 4;
    return Stack(
      children: [
        Positioned(
          left: screenSize.width / 2 - dividerWidth / 2,
          top: 0,
          bottom: 0,
          child: Container(
            width: dividerWidth,
            color: Colors.grey.withOpacity(0.5),
          ),
        ),
        AnimatedBuilder(
          animation: _arrowAnimation,
          builder: (context, child) {
            return Positioned(
              left: (_arrowAnimation.value *
                      (screenSize.width - _arrowWidth) /
                      2) +
                  screenSize.width / 2 -
                  _arrowWidth / 2,
              top: screenSize.height * 0.5 - _arrowWidth / 2,
              child: Icon(
                _isMisaligned
                    ? Icons.warning_amber_rounded
                    : Icons.arrow_downward_rounded,
                size: _arrowWidth,
                color: _isMisaligned ? Colors.red : Colors.green,
              ),
            );
          },
        ),
        if (_alignmentMessage.isNotEmpty)
          Positioned(
            top: screenSize.height * 0.5 + _arrowWidth,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: _isMisaligned ? Colors.red : Colors.green,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  _alignmentMessage,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class KalmanFilter {
  double q = 0.0001; // Quá trình biến đổi (process variance)
  double r = 0.1; // Đo lường biến đổi (measurement variance)
  double p = 1.0; // Sai số ước lượng (estimation error)
  double x = 0.0; // Giá trị ước lượng ban đầu (initial value)

  double filter(double measurement) {
    p = p + q;
    double k = p / (p + r);
    x = x + k * (measurement - x);
    p = (1 - k) * p;
    return x;
  }
}
