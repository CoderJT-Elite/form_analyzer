import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum RepPhase { down, up }

// Squat depth thresholds
const double kSquatDepthMin = 70;  // Minimum angle for valid squat depth
const double kSquatDepthMax = 90;  // Maximum angle for valid squat depth
const double kSquatStandingAngle = 160;  // Standing position threshold
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

/// Calculates the interior angle (in degrees) at the joint [second] formed by 
/// three PoseLandmarks using the dot product formula.
/// Returns the angle between the vectors [first]-[second] and [second]-[third].
/// Formula: cos(θ) = (a·b) / (|a||b|), where a and b are vectors from the joint.
double calculateAngle(PoseLandmark first, PoseLandmark second, PoseLandmark third) {
  // Calculate vector from second to first
  final dx1 = first.x - second.x;
  final dy1 = first.y - second.y;
  final dz1 = first.z - second.z;
  
  // Calculate vector from second to third
  final dx2 = third.x - second.x;
  final dy2 = third.y - second.y;
  final dz2 = third.z - second.z;
  
  // Calculate magnitudes (distances)
  final mag1 = math.sqrt(dx1 * dx1 + dy1 * dy1 + dz1 * dz1);
  final mag2 = math.sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2);
  
  // Prevent division by zero
  if (mag1 < kMinMagnitude || mag2 < kMinMagnitude) {
    return 0.0;
  }
  
  // Calculate dot product
  final dotProduct = dx1 * dx2 + dy1 * dy2 + dz1 * dz2;
  
  // Apply dot product formula: cos(θ) = (a·b) / (|a||b|)
  final cosine = (dotProduct / (mag1 * mag2)).clamp(-1.0, 1.0);
  
  // Convert to degrees
  final angleRadians = math.acos(cosine);
  final angleDegrees = angleRadians * 180 / math.pi;
  
  return angleDegrees;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
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
    
    // Get Hip-Knee-Ankle landmarks for squat tracking
    var hip = pose.landmarks[PoseLandmarkType.leftHip];
    var knee = pose.landmarks[PoseLandmarkType.leftKnee];
    var ankle = pose.landmarks[PoseLandmarkType.leftAnkle];
    
    // Fallback to right side if left side not visible
    if (hip == null || knee == null || ankle == null) {
      hip = pose.landmarks[PoseLandmarkType.rightHip];
      knee = pose.landmarks[PoseLandmarkType.rightKnee];
      ankle = pose.landmarks[PoseLandmarkType.rightAnkle];
    }
    
    if (hip == null || knee == null || ankle == null) {
      setState(() {
        _statusMessage = 'Keep your full body visible';
      });
      return;
    }
    
    // Calculate the knee angle (Hip-Knee-Ankle)
    final angle = calculateAngle(hip, knee, ankle);
    
    int reps = _repCount;
    RepPhase phase = _repPhase;
    String status = _statusMessage;

    // Squat tracking logic
    if (angle >= kSquatStandingAngle && phase == RepPhase.down) {
      // Standing up from squat - rep completed
      reps += 1;
      status = 'Great squat!';
      phase = RepPhase.up;
    } else if (angle >= kSquatDepthMin && angle <= kSquatDepthMax && phase == RepPhase.up) {
      // Reached proper squat depth
      status = 'Good depth! Now stand up';
      phase = RepPhase.down;
    } else if (angle > kSquatDepthMax && angle < kSquatStandingAngle) {
      // In between standing and proper depth
      if (phase == RepPhase.up) {
        status = 'Go lower';
      } else {
        status = 'Stand up';
      }
    } else if (angle < kSquatDepthMin) {
      // Too deep
      status = 'Too deep - maintain control';
    } else {
      status = 'Ready to squat';
    }

    setState(() {
      _repCount = reps;
      _statusMessage = status;
      _repPhase = phase;
    });
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
      appBar: AppBar(title: const Text('Squat Form Analyzer')),
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
