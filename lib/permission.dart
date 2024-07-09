import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestCameraPermission() async {
  final status = await Permission.camera.request();
  if (status.isGranted) {
    if (kDebugMode) {
      print('Permission granted');
    }
    return true;
  } else if (status.isDenied) {
    if (kDebugMode) {
      print('Permission denied');
    }
    return false;
  } else if (status.isPermanentlyDenied) {
    if (kDebugMode) {
      print('Permission permanently denied');
    }
    return false;
  }
  return false;
}
