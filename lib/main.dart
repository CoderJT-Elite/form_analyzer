import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum RepPhase { down, up }

const double kCurlTopThreshold = 45;
const double kCurlBottomThreshold = 150;
const double kCurlMidThreshold = 100;
const double kMinMagnitude = 1e-6;

/// Calculates the angle (in degrees) at the middle point [b] formed by the
/// three offsets [a]-[b]-[c]. The result is clamped to avoid division by zero.
double calculateJointAngle(Offset a, Offset b, Offset c) {
  final ba = Offset(a.dx - b.dx, a.dy - b.dy);
  final bc = Offset(c.dx - b.dx, c.dy - b.dy);
  final dotProduct = (ba.dx * bc.dx) + (ba.dy * bc.dy);
  final baDistanceSquared = (ba.dx * ba.dx) + (ba.dy * ba.dy);
  final bcDistanceSquared = (bc.dx * bc.dx) + (bc.dy * bc.dy);
  final magnitude = math.max(math.sqrt(baDistanceSquared * bcDistanceSquared), kMinMagnitude);
  final cosine = (dotProduct / magnitude).clamp(-1.0, 1.0);
  final angle = math.acos(cosine) * 180 / math.pi;
  return angle;
}

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

/// Manages camera streaming, pose detection, rep counting, and overlay UI.
class _PoseDetectionScreenState extends State<PoseDetectionScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final PoseDetector _poseDetector;
  bool _isCameraInitialized = false;
<<<<<<< HEAD
  bool _isProcessing = false;
  late CameraDescription _camera;
=======
  bool _isProcessingFrame = false;
  List<Pose> _poses = <Pose>[];
  Size? _imageSize;
  int _repCount = 0;
  String _statusMessage = 'Align yourself in the frame';
  RepPhase _repPhase = RepPhase.down;
  String? _errorMessage;
  InputImageRotation _imageRotation = InputImageRotation.rotation0deg;
  CameraDescription? _cameraDescription;
  Future<void>? _initializeFuture;
>>>>>>> faf37e6969aabc91c6ff2ddd3b116e6393d0807b

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    _initialize();
  }

<<<<<<< HEAD
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
=======
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
>>>>>>> faf37e6969aabc91c6ff2ddd3b116e6393d0807b
      return;
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopImageStream();
      controller.dispose();
      _cameraController = null;
      setState(() {
        _isCameraInitialized = false;
      });
    } else if (state == AppLifecycleState.resumed) {
      _initialize();
    }
  }

<<<<<<< HEAD
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
=======
  Future<void> _initialize() async {
    _initializeFuture ??= _initializeCamera();
    final pending = _initializeFuture!;
    try {
      await pending;
    } finally {
      if (identical(_initializeFuture, pending)) {
        _initializeFuture = null;
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available on this device.';
          _isCameraInitialized = false;
        });
        return;
      }
      final description = cameras.first;
      _cameraDescription = description;
      await _stopImageStream();
      await _cameraController?.dispose();
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _cameraController = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _imageRotation = _getImageRotation();
      // previewSize reports landscape values; swap to match portrait canvas.
      _imageSize = controller.value.previewSize == null
          ? null
          : Size(
              controller.value.previewSize!.height,
              controller.value.previewSize!.width,
            );
      await controller.startImageStream(_processCameraImage);
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      setState(() {
        _errorMessage = e.code == 'CameraAccessDenied'
            ? 'Camera permission denied. Please enable it in settings.'
            : 'Camera error: ${e.description ?? e.code}';
        _isCameraInitialized = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
        _isCameraInitialized = false;
      });
    }
  }

  Future<void> _stopImageStream() async {
    try {
      if (_cameraController?.value.isStreamingImages ?? false) {
        await _cameraController?.stopImageStream();
      }
    } catch (e) {
      debugPrint('Failed to stop image stream: $e');
    }
  }

  InputImageRotation _getImageRotation() {
    return InputImageRotationValue.fromRawValue(_cameraDescription?.sensorOrientation ?? 0) ??
        InputImageRotation.rotation0deg;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Frames arrive serially from the camera stream; this flag prevents
    // overlapping work when processing falls behind.
    if (_isProcessingFrame || _cameraDescription == null) return;
    _isProcessingFrame = true;
    try {
      final planes = image.planes;
      if (planes.isEmpty) {
        debugPrint('CameraImage contained no planes; skipping frame.');
        return;
      }
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      final rotation = _getImageRotation();
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
        bytesPerRow: planes.first.bytesPerRow,
      );
      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final poses = await _poseDetector.processImage(inputImage);
      final adjustedSize = (rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg)
          ? Size(metadata.size.height, metadata.size.width)
          : metadata.size;
      if (!mounted) return;
      setState(() {
        _poses = poses;
        _imageSize = adjustedSize;
        _imageRotation = rotation;
      });
      _evaluateExercise(poses);
    } catch (e, stack) {
      debugPrint('Pose processing error: $e\n$stack');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Pose _selectPrimaryPose(List<Pose> poses) {
    if (poses.length == 1) return poses.first;
    Pose? bestPose;
    double bestScore = -1;
    for (final pose in poses) {
      final score = _poseLikelihood(pose);
      if (score > bestScore) {
        bestScore = score;
        bestPose = pose;
        if (score >= 0.9) break;
      }
    }
    return bestPose ?? poses.first;
  }

  double _poseLikelihood(Pose pose) {
    if (pose.landmarks.isEmpty) return 0;
    final total = pose.landmarks.values.fold<double>(0, (sum, lm) => sum + lm.likelihood);
    return total / pose.landmarks.length;
  }

  void _evaluateExercise(List<Pose> poses) {
    if (!mounted) return;
    if (poses.isEmpty) {
      setState(() {
        _statusMessage = 'Move fully into the frame';
      });
      return;
    }
    // Focus on the pose with highest confidence to keep rep counting fast for a single-user flow.
    final Pose pose = _selectPrimaryPose(poses);
    var shoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    var elbow = pose.landmarks[PoseLandmarkType.leftElbow];
    var wrist = pose.landmarks[PoseLandmarkType.leftWrist];
    if (shoulder == null || elbow == null || wrist == null) {
      shoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
      elbow = pose.landmarks[PoseLandmarkType.rightElbow];
      wrist = pose.landmarks[PoseLandmarkType.rightWrist];
    }
    if (shoulder == null || elbow == null || wrist == null) {
      setState(() {
        _statusMessage = 'Keep at least one arm visible';
      });
      return;
    }
    final angle = _calculateAngle(shoulder, elbow, wrist);
    int reps = _repCount;
    RepPhase phase = _repPhase;
    String status = _statusMessage;

    if (angle <= kCurlTopThreshold && phase == RepPhase.down) {
      status = 'Squeeze at the top';
      phase = RepPhase.up;
    } else if (angle >= kCurlBottomThreshold && phase == RepPhase.up) {
      reps += 1;
      status = 'Great form!';
      phase = RepPhase.down;
    } else if (angle > kCurlMidThreshold) {
      status = 'Curl up';
    } else {
      status = 'Control the descent';
    }
>>>>>>> faf37e6969aabc91c6ff2ddd3b116e6393d0807b

    setState(() {
      _repCount = reps;
      _statusMessage = status;
      _repPhase = phase;
    });
  }

<<<<<<< HEAD
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
=======
  double _calculateAngle(
    PoseLandmark a,
    PoseLandmark b,
    PoseLandmark c,
  ) {
    return calculateJointAngle(
      Offset(a.x, a.y),
      Offset(b.x, b.y),
      Offset(c.x, c.y),
    );
>>>>>>> faf37e6969aabc91c6ff2ddd3b116e6393d0807b
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopImageStream();
    _cameraController?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An unexpected error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initialize,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBar() {
    return Row(
      children: [
        _InfoChip(
          title: 'Reps',
          value: '$_repCount',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoChip(
            title: 'Status',
            value: _statusMessage,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pose Detection')),
      backgroundColor: Colors.black,
      body: _errorMessage != null
          ? _buildError()
          : !_isCameraInitialized
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cameraController != null) CameraPreview(_cameraController!),
                    if (_imageSize != null)
                      CustomPaint(
                        painter: PosePainter(
                          poses: _poses,
                          imageSize: _imageSize!,
                          rotation: _imageRotation,
                          lensDirection: _cameraDescription?.lensDirection ?? CameraLensDirection.back,
                        ),
                      ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _buildInfoBar(),
                    ),
                    Positioned(
                      bottom: 24,
                      left: 16,
                      right: 16,
                      child: _InfoChip(title: 'Tip', value: _statusMessage),
                    ),
                  ],
                ),
    );
  }
}

/// Custom painter that maps pose landmarks to the preview canvas and renders a
/// skeletal overlay.
class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  /// Landmark pairs that define the skeletal connections to render.
  static const List<List<PoseLandmarkType>> _connections = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final landmarkPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final pose in poses) {
      for (final connection in _connections) {
        final first = pose.landmarks[connection[0]];
        final second = pose.landmarks[connection[1]];
        if (first == null || second == null) continue;
        final p1 = _transform(first, size);
        final p2 = _transform(second, size);
        canvas.drawLine(p1, p2, linePaint);
      }
      for (final landmark in pose.landmarks.values) {
        final point = _transform(landmark, size);
        canvas.drawCircle(point, 5, landmarkPaint);
      }
    }
  }

  Offset _transform(PoseLandmark landmark, Size canvasSize) {
    double x = landmark.x;
    double y = landmark.y;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        final temp = x;
        x = y;
        y = imageSize.width - temp;
        break;
      case InputImageRotation.rotation270deg:
        final temp = x;
        x = imageSize.height - y;
        y = temp;
        break;
      case InputImageRotation.rotation180deg:
        x = imageSize.width - x;
        y = imageSize.height - y;
        break;
      case InputImageRotation.rotation0deg:
        break;
    }
    final scaleX = canvasSize.width / imageSize.width;
    final scaleY = canvasSize.height / imageSize.height;
    var transformed = Offset(x * scaleX, y * scaleY);
    if (lensDirection == CameraLensDirection.front) {
      transformed = Offset(canvasSize.width - transformed.dx, transformed.dy);
    }
    return transformed;
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.lensDirection != lensDirection;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
