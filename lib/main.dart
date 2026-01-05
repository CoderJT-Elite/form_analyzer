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
    final firstCamera = cameras.first;

    // Initialize the camera controller
    _cameraController = CameraController(
      firstCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (!mounted) {
      return;
    }

    // Start streaming images from the camera
    _cameraController!.startImageStream((CameraImage image) {
      // This is where the image frames from the camera are sent to the AI engine.
      // We convert the CameraImage to an InputImage, which the ML Kit library understands.

      // 1. Combine all image planes into a single byte array
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      // Calculate rotation based on the camera sensor orientation
      // (ensure 'firstCamera' from the enclosing scope is used)
      final int rotationDegrees = firstCamera.sensorOrientation;
      final InputImageRotation rotation;
      switch (rotationDegrees) {
        case 0:
          rotation = InputImageRotation.rotation0deg;
          break;
        case 90:
          rotation = InputImageRotation.rotation90deg;
          break;
        case 180:
          rotation = InputImageRotation.rotation180deg;
          break;
        case 270:
          rotation = InputImageRotation.rotation270deg;
          break;
        default:
          rotation = InputImageRotation.rotation0deg;
      }

      // 2. Build the metadata (This replaces the old 'PlaneMetadata' and 'planes' errors)
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // Use the rotation computed above
        format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
        bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : 0,
      );

      // 3. Create the final image for the AI to process
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: metadata,
      );

      // Process the image for poses
      _poseDetector?.processImage(inputImage).then((poses) {
        // This is the placeholder function for your exercise analysis.
        // The 'poses' variable contains the detected poses.
        _analyzeExercise(poses);
      }).catchError((e) {
        // Handle any errors
      });
    });

    setState(() {
      _isCameraInitialized = true;
    });
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
