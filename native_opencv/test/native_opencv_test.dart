import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_opencv/native_opencv.dart';

void main() {
  const MethodChannel channel = MethodChannel('native_opencv');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await NativeOpencv.platformVersion, '42');
  });
}
