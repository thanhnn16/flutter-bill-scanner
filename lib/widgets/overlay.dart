import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class AlignmentOverlay extends StatefulWidget {
  final Function(bool) onAlignmentChange;

  const AlignmentOverlay({super.key, required this.onAlignmentChange});

  @override
  AlignmentOverlayState createState() => AlignmentOverlayState();
}

class AlignmentOverlayState extends State<AlignmentOverlay> {
  double _arrowPosition = 0.5;
  bool _isMisaligned = false;
  String _alignmentMessage = 'Camera đã căn chỉnh đúng';

  final _averageCount = 5;
  final List<double> _accelerationXHistory = List.filled(5, 0.0);
  int _historyIndex = 0;

  final double _movementThreshold = 0.02;
  final double _deadZone = 0.02;

  // Biến lưu giá trị sai lệch của gia tốc kế theo trục X
  double _accelerationXBias = 0.0;

  @override
  void initState() {
    super.initState();
    _calibrateAccelerometer(); // Hiệu chỉnh gia tốc kế khi khởi tạo
    accelerometerEventStream().listen((event) {
      _updateAlignment(event);
    });
  }

  // Hàm hiệu chỉnh gia tốc kế
  void _calibrateAccelerometer() async {
    final accelerometerEvents = await accelerometerEventStream().take(10).toList();
    double sumX = 0.0;
    for (var event in accelerometerEvents) {
      sumX += event.x;
    }
    _accelerationXBias = sumX / accelerometerEvents.length;
  }

  void _updateAlignment(AccelerometerEvent event) {
    // Trừ giá trị sai lệch đã tính được
    double calibratedX = event.x - _accelerationXBias;

    _accelerationXHistory[_historyIndex] = calibratedX;
    _historyIndex = (_historyIndex + 1) % _averageCount;

    double sumX = 0.0;
    for (int i = 0; i < _averageCount; i++) {
      sumX += _accelerationXHistory[i];
    }
    double averageX = sumX / _averageCount;

    // Áp dụng dead zone
    averageX = (averageX.abs() < _deadZone) ? 0 : averageX;

    double newX = (_arrowPosition + averageX * 0.05).clamp(0.0, 1.0);

    bool newMisalignment = (newX - 0.5).abs() >= _movementThreshold;

    String newAlignmentMessage = newMisalignment
        ? "Vui lòng nghiêng camera sang ${averageX > 0 ? "trái" : "phải"}"
        : "Camera đã căn chỉnh đúng";

    if (_isMisaligned != newMisalignment ||
        _alignmentMessage != newAlignmentMessage ||
        _arrowPosition != newX) {
      setState(() {
        _arrowPosition = newX;
        _isMisaligned = newMisalignment;
        _alignmentMessage = newAlignmentMessage;
      });
      widget.onAlignmentChange(!_isMisaligned);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: MediaQuery.of(context).size.width * _arrowPosition - 25,
          top: MediaQuery.of(context).size.height * 0.5 - 25,
          child: Icon(
            Icons.arrow_downward,
            size: 50,
            color: _isMisaligned ? Colors.red : Colors.green,
          ),
        ),
        if (_isMisaligned)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.5 - 60,
            left: MediaQuery.of(context).size.width * 0.5 - 100,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red,
              child: Text(
                _alignmentMessage,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        Positioned(
          left: MediaQuery.of(context).size.width / 2 - 4, // Center the line
          top: 0,
          bottom: 0,
          child: const VerticalDivider(
            color: Colors.grey,
            thickness: 4,
          ),
        ),
      ],
    );
  }
}
