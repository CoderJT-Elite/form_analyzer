import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: PoseDetectionScreen(),
    );
  }
}

class PoseDetectionScreen extends StatefulWidget {
  const PoseDetectionScreen({super.key});

  @override
  State<PoseDetectionScreen> createState() => _PoseDetectionScreenState();
}

class _PoseDetectionScreenState extends State<PoseDetectionScreen> {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  late CameraDescription _camera;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Initialize the pose detector
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );

    // Get available cameras
    final cameras = await availableCameras();
    _camera = cameras.first;

    // Initialize the camera controller
    _cameraController = CameraController(
      _camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (!mounted) {
      return;
    }

    // Start streaming images from the camera
    _cameraController!.startImageStream((CameraImage image) {
      // Add a simple 'isProcessing' lock to prevent overloading the AI
      if (_isProcessing) return;
      _isProcessing = true;

      try {
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        final imageRotation = InputImageRotationValue.fromRawValue(
          _camera.sensorOrientation,
        ) ?? InputImageRotation.rotation0deg;

        final imageFormat = InputImageFormatValue.fromRawValue(image.format.raw)
          ?? InputImageFormat.nv21; // Default to nv21 if unknown

        final inputImageMetadata = InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: imageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        );

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: inputImageMetadata,
        );

        _processImage(inputImage);
      } catch (e) {
        print("AI Processing Error: $e");
      } finally {
        _isProcessing = false;
      }
    });

    setState(() {
      _isCameraInitialized = true;
    });
  }

  Future<void> _processImage(InputImage inputImage) async {
    try {
      final poses = await _poseDetector?.processImage(inputImage);
      if (poses != null) {
        _analyzeExercise(poses);
      }
    } catch (e) {
      print("Pose detection error: $e");
    }
  }

  void _analyzeExercise(List<Pose> poses) {
    // TODO: Add your math for bicep curls and squats here.
    // You can access the landmarks of each pose, for example:
    // for (final pose in poses) {
    //   final landmark = pose.landmarks[PoseLandmarkType.leftShoulder];
    //   if (landmark != null) {
    //     print('Left shoulder position: (${landmark.x}, ${landmark.y})');
    //   }
    // }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _poseDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pose Detection')),
      body: CameraPreview(_cameraController!),
    );
  }
}
