import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'frame/frame_overlay.dart';

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

  // Sử dụng StreamSubscription để có thể hủy lắng nghe khi không cần thiết
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  final _averageCount = 4; // Tăng số lượng mẫu trung bình
  final List<double> _accelerationXHistory = List.filled(4, 0.0);
  int _historyIndex = 0;

  final double _movementThreshold = 0.02;
  final double _deadZone = 0.015; // Giảm deadZone để tăng độ nhạy

  // Biến lưu giá trị sai lệch của gia tốc kế theo trục X
  double _accelerationXBias = 0.0;

  @override
  void initState() {
    super.initState();
    _calibrateAccelerometer();
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel(); // Hủy lắng nghe khi widget bị hủy
    super.dispose();
  }

  // Hàm hiệu chỉnh gia tốc kế
  void _calibrateAccelerometer() async {
    final accelerometerEvents = await accelerometerEventStream().take(20).toList();
    double sumX = 0.0;
    for (var event in accelerometerEvents) {
      sumX += event.x;
    }
    _accelerationXBias = sumX / accelerometerEvents.length;

    // Bắt đầu lắng nghe sau khi hiệu chỉnh
    _startListening();
  }

  // Hàm bắt đầu lắng nghe sự kiện từ cảm biến
  void _startListening() {
    _accelerometerSubscription =
        accelerometerEventStream().listen((event) {
          _updateAlignment(event);
        });
  }

  void _updateAlignment(AccelerometerEvent event) {
    // Trừ giá trị sai lệch đã tính được
    double calibratedX = event.x - _accelerationXBias;

    // Sử dụng low-pass filter để lọc nhiễu
    calibratedX = _applyLowPassFilter(calibratedX, _accelerationXHistory[_historyIndex]);

    _accelerationXHistory[_historyIndex] = calibratedX;
    _historyIndex = (_historyIndex + 1) % _averageCount;

    double sumX = 0.0;
    for (int i = 0; i < _averageCount; i++) {
      sumX += _accelerationXHistory[i];
    }
    double averageX = sumX / _averageCount;

    // Áp dụng dead zone
    averageX = (averageX.abs() < _deadZone) ? 0 : averageX;

    // Giảm tốc độ di chuyển của mũi tên
    double newX = (_arrowPosition + averageX * 0.02).clamp(0.0, 1.0);

    bool newMisalignment = (newX - 0.5).abs() >= _movementThreshold;

    String newAlignmentMessage = newMisalignment
        ? "Vui lòng nghiêng camera sang ${averageX > 0 ? "trái" : "phải"}"
        : "Camera đã căn chỉnh đúng";

    // Chỉ setState khi có thay đổi
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

  // Áp dụng low-pass filter
  double _applyLowPassFilter(double currentValue, double previousValue, {double alpha = 0.2}) {
    return alpha * currentValue + (1 - alpha) * previousValue;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FrameOverlay(
          frameLeft: 0,
          frameTop: 0,
          frameWidth: MediaQuery.of(context).size.width,
          frameHeight: MediaQuery.of(context).size.height,
        ),
        Positioned(
          left: MediaQuery.of(context).size.width * _arrowPosition - 25,
          top: MediaQuery.of(context).size.height * 0.5 - 25,
          child: Icon(
            Icons.arrow_downward,
            size: 64,
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
          left: MediaQuery.of(context).size.width / 2 - 4,
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
