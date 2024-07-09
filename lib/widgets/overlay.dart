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

  // Sử dụng giá trị trung bình động để làm mượt dữ liệu cảm biến
  final int _averageCount = 10; // Số lượng giá trị để tính trung bình
  final List<double> _accelerationXHistory =
  List.filled(10, 0.0); // Lưu trữ lịch sử gia tốc X
  int _historyIndex = 0; // Chỉ số của giá trị lịch sử hiện tại

  @override
  void initState() {
    super.initState();
    accelerometerEventStream().listen((AccelerometerEvent event) {
      _updateAlignment(event);
    });
  }

  void _updateAlignment(AccelerometerEvent event) {
    // Cập nhật lịch sử gia tốc X
    _accelerationXHistory[_historyIndex] = event.x;
    _historyIndex = (_historyIndex + 1) % _averageCount;

    // Tính toán giá trị trung bình của gia tốc X
    double averageX =
        _accelerationXHistory.reduce((a, b) => a + b) / _averageCount;

    // Tính toán vị trí mũi tên dựa trên gia tốc trung bình
    double newX = _arrowPosition + averageX * 0.005;
    newX = newX.clamp(0.0, 1.0);

    // Kiểm tra căn chỉnh dựa trên ngưỡng
    bool misaligned = (newX - 0.5).abs() >= 0.03;

    // Tính góc nghiêng từ gia tốc
    // double tiltAngle = math.atan2(
    //     event.y, math.sqrt(event.x * event.x + event.z * event.z)) *
    //     180 /
    //     math.pi;

    if (mounted) {
      setState(() {
        _arrowPosition = newX;
        _isMisaligned = misaligned;
        // _tiltAngle = tiltAngle; // Cập nhật góc nghiêng (không cần thiết)
      });
      widget.onAlignmentChange(!_isMisaligned);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          child: Divider(
              height: MediaQuery.of(context).size.height,
              color: Colors.white,
              thickness: 2,
              indent: MediaQuery.of(context).size.width * 0.5,
              endIndent: MediaQuery.of(context).size.width * 0.5),
        ),
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
              child: const Text(
                'Vui lòng căn chỉnh camera',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}