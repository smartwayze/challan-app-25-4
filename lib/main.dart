import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(CarDetectionApp());
}

class CarDetectionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: CarDetectionScreen(),
    );
  }
}

class CarDetectionScreen extends StatefulWidget {
  @override
  _CarDetectionScreenState createState() => _CarDetectionScreenState();
}

class _CarDetectionScreenState extends State<CarDetectionScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;
  String _prediction = '';
  Interpreter? _interpreter;
  int _countdown = 0;
  bool _showTimer = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _initializeCamera();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model/yolov8n_full_integer_quant.tflite');
      print("Model loaded");
    } catch (e) {
      print("Failed to load model: $e");
    }
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    setState(() => _isCameraReady = true);
    _showCameraDialog();
  }

  void _showCameraDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("permission"),
        content: Text("Do you allow this app to take acceess?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("No")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startCountdownAndCapture();
            },
            child: Text("Yes"),
          ),
        ],
      ),
    );
  }

  void _startCountdownAndCapture() {
    setState(() {
      _countdown = 10;
      _showTimer = true;
    });

    Timer.periodic(Duration(seconds: 1), (timer) async {
      if (_countdown == 1) {
        timer.cancel();
        setState(() => _showTimer = false);
        await _captureImageAndPredict();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _captureImageAndPredict() async {
    try {
      final path = (await getTemporaryDirectory()).path + "/capture.jpg";
      XFile file = await _controller!.takePicture();
      File imageFile = File(file.path);
      await _predict(imageFile);
    } catch (e) {
      print("Capture error: $e");
    }
  }

  Future<void> _predict(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    img.Image? oriImage = img.decodeImage(bytes);

    if (_interpreter == null || oriImage == null) {
      setState(() => _prediction = 'Model/Image error');
      return;
    }

    int inputSize = _interpreter!.getInputTensor(0).shape[1];
    img.Image resized = img.copyResize(oriImage, width: inputSize, height: inputSize);

    List<List<List<List<int>>>> input = List.generate(
      1,
          (_) => List.generate(inputSize, (y) => List.generate(inputSize, (x) {
        final pixel = resized.getPixel(x, y);
        return [
          (pixel >> 16 & 0xFF) - 128,
          (pixel >> 8 & 0xFF) - 128,
          (pixel & 0xFF) - 128
        ].map((v) => v.clamp(-128, 127)).toList();
      })),
    );

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    var output = List.generate(
      outputShape[0],
          (_) => List.generate(outputShape[1], (_) => List.filled(outputShape[2], 0)),
    );

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      setState(() => _prediction = 'Inference failed');
      return;
    }

    String predictionText = "No Detection";
    for (var i = 0; i < outputShape[2]; i++) {
      int rawConfidence = output[0][0][i];
      int classId = output[0][1][i];

      double confidence = (rawConfidence + 128) / 255.0;

      if (confidence > 0.5) {
        if (classId == 1) {
          predictionText = "Wrongly Parked";
          break;
        } else if (classId == 0) {
          predictionText = "Correctly Parked";
          break;
        }
      }
    }


    setState(() {
      _prediction = predictionText;

    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Car Parking Detection')),
      body: Stack(
        children: [
          _isCameraReady
              ? CameraPreview(_controller!)
              : Center(child: CircularProgressIndicator()),

          // Countdown Overlay
          if (_showTimer)
            Center(
              child: Container(

                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: EdgeInsets.all(40),
                child: Text(
                  '$_countdown',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // Prediction Text
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _prediction,
                style: TextStyle(
                  color: Colors.white,
                  backgroundColor: Colors.black54,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
