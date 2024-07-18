import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:long_shot_app/native/scan_bill.dart';
import 'package:long_shot_app/permission.dart';
import 'package:path_provider/path_provider.dart';

import '../display_image.dart';
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
  final bool _isProcessed = false;
  final bool _isWorking = false;

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

  Future<List<String?>?> pickImages() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final List<XFile> images =
          await _picker.pickMultiImage(imageQuality: 100);
      return images.map((image) => image.path).toList();
    } else {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pick images',
        type: FileType.image,
        allowMultiple: true,
      );
      return result?.files.map((file) => file.path).toList();
    }
  }

  Future<void> stitchImagesAndShow(List<String?> imagePaths) async {
    setState(() {
      _isLoading = true;
    });
    final outputPath = '${tempDir.path}/stitched_image.jpg';

    // Creating a port for communication with isolate and arguments for entry point
    final port = ReceivePort();
    final args = StitchImagesArguments(imagePaths, outputPath);

    // Spawning an isolate
    Isolate.spawn<StitchImagesArguments>(
      stitchImagesInBackground,
      args,
      onError: port.sendPort,
      onExit: port.sendPort,
    );

    // Making a variable to store a subscription in
    late StreamSubscription sub;

    // Listening for messages on port
    sub = port.listen((_) async {
      // Cancel a subscription after message received called
      await sub.cancel();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DisplayImage(imagePath: outputPath),
          ),
        );
      }
    });
  }

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

  // Static function for the isolate
  static void stitchImagesInBackground(StitchImagesArguments args) {
    // Call the native stitching function
    stitchImages(StitchImagesArguments(args.imagePaths, args.outputPath));
    // Normally, you would use platform channels to communicate back to Flutter UI
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: Stack(
        children: <Widget>[
          Center(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                if (_isProcessed && !_isWorking)
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 3000, maxHeight: 300),
                    child: Image.file(
                      File(tempPath),
                      alignment: Alignment.center,
                    ),
                  ),
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: showVersion,
                      child: const Text('Show version'),
                    ),
                    ElevatedButton(
                      child: const Text('Stitch images'),
                      onPressed: () async {
                        final imagePaths = await pickImages();
                        if (imagePaths!.isNotEmpty) {
                          stitchImagesAndShow(imagePaths);
                        }
                      },
                    ),
                    ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const ScanBillScreen()));
                        },
                        child: const Text('Scan bill')),
                  ],
                )
              ],
            ),
          ),
          if (_isWorking)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(.7),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(.7),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
