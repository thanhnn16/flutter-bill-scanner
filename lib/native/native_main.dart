import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:long_shot_app/native/scan_bill.dart';
import 'package:path_provider/path_provider.dart';

import '../display_image.dart';
import '../permission.dart';
import 'native_opencv.dart';

const title = 'Native OpenCV Example';

late Directory tempDir;

String get tempPath => '${tempDir.path}/temp.jpg';

class NativeMain extends StatefulWidget {
  const NativeMain({super.key});

  @override
  NativeMainState createState() => NativeMainState();
}

class NativeMainState extends State<NativeMain> {
  final _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeTempDir();
    _initializePerm();
  }

  Future<void> _initializeTempDir() async {
    tempDir = await getTemporaryDirectory();
  }

  Future<void> _initializePerm() async {
    await requestCameraPermission();
    await requestGalleryPermission();
    await requestStoragePermission();
  }

  void showVersion() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final snackbar = SnackBar(
      content: Text('OpenCV version: ${opencvVersion()}'),
    );

    scaffoldMessenger
      ..removeCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
      ..showSnackBar(snackbar);
  }

  Future<String?> pickAnImage() async {
    if (Platform.isIOS || Platform.isAndroid) {
      return _picker
          .pickImage(
            source: ImageSource.gallery,
            imageQuality: 100,
          )
          .then((v) => v?.path);
    } else {
      return FilePicker.platform
          .pickFiles(
            dialogTitle: 'Pick an image',
            type: FileType.image,
            allowMultiple: false,
          )
          .then((v) => v?.files.first.path);
    }
  }

  Future<List<String?>> pickImages() async {
    if (Platform.isIOS || Platform.isAndroid) {
      return _picker
          .pickMultiImage(
            imageQuality: 100,
          )
          .then((value) => value.map((e) => e.path).toList());
    } else {
      return FilePicker.platform
          .pickFiles(
            dialogTitle: 'Pick images',
            type: FileType.image,
            allowMultiple: true,
          )
          .then((value) => value?.files.map((e) => e.path).toList() ?? []);
    }
  }

  Future<void> _processInIsolate(
      List<String?> imagePaths, String outputPath) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(
      _isolateEntry,
      [receivePort.sendPort, imagePaths, outputPath],
    );

    final result = await receivePort.first;
    if (result is Exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${result.toString()}'),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stitching complete'),
          ),
        );
      }
    }
  }

  static void _isolateEntry(List<dynamic> args) {
    final sendPort = args[0] as SendPort;
    final imagePaths = args[1] as List<String?>;
    final outputPath = args[2] as String;

    try {
      stitchImages(StitchImagesArguments(imagePaths, outputPath));
      sendPort.send('Success');
    } catch (e) {
      sendPort.send(e);
    }
  }

  void _processImage() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    final imagePaths = await pickImages();

    if (imagePaths.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final directory = await getDownloadsDirectory();
    final outputPath = '${directory!.path}/20.4.jpg';

    await _processInIsolate(imagePaths, outputPath);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DisplayImage(imagePath: outputPath),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _processImage,
                child: const Text('Pick Images and Stitch'),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: showVersion,
              child: const Text('Show OpenCV Version'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ScanBillScreen(),
                  ),
                );
              },
              child: const Text('Scan Bill'),
            ),
          ],
        ),
      ),
    );
  }
}
