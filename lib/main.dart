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
const double kInsufficientDepthAngle = 100; // Knee angle above which depth is considered insufficient
const double kMinMagnitude = 1e-6;

// Angle label padding in the canvas overlay
const double _kAngleLabelPadding = 6.0;

// Rep counter animation scale (elastic pop when count increments)
const double _kRepCounterScaleBegin = 1.4;
const double _kRepCounterScaleEnd   = 1.0;

// UI colour palette  (k-prefix follows Flutter framework convention)
const Color kAccentCyan    = Color(0xFF00E5FF);
const Color kGoodGreen     = Color(0xFF00E676);
const Color kBadRed        = Color(0xFFFF1744);
const Color kWarnOrange    = Color(0xFFFFAB40);
const Color kSurface       = Color(0xFF0D1117);

/// Returns a [_StatusStyle] (colour + icon) that matches the current status message.
_StatusStyle _styleForMessage(String message) {
  if (message.contains('Great squat') || message.contains('Good depth')) {
    return _StatusStyle(kGoodGreen, Icons.check_circle_rounded);
  } else if (message.contains('lower') || message.contains('Stand up')) {
    return _StatusStyle(kWarnOrange, Icons.swap_vert_rounded);
  } else if (message.contains('Too deep')) {
    return _StatusStyle(kBadRed, Icons.warning_rounded);
  } else if (message.contains('frame') || message.contains('visible')) {
    return _StatusStyle(kWarnOrange, Icons.person_search_rounded);
  }
  return _StatusStyle(kAccentCyan, Icons.fitness_center_rounded);
}

class _StatusStyle {
  const _StatusStyle(this.color, this.icon);
  final Color color;
  final IconData icon;
}

/// Calculates the angle (in degrees) at the middle point [b] formed by the
/// three offsets [a]-[b]-[c]. The result is clamped to avoid division by zero.
double calculateJointAngleFromOffsets(Offset a, Offset b, Offset c) {
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

/// Calculates the interior angle in degrees at joint [b] formed by the
/// three PoseLandmarks [a]-[b]-[c] using the Law of Cosines (dot-product form).
/// Returns 0.0 safely when any landmark is null or when points are coincident.
double calculateJointAngle(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
  if (a == null || b == null || c == null) return 0.0;

  // Vectors from the joint b to each neighbouring landmark
  final dx1 = a.x - b.x;
  final dy1 = a.y - b.y;
  final dz1 = a.z - b.z;

  final dx2 = c.x - b.x;
  final dy2 = c.y - b.y;
  final dz2 = c.z - b.z;

  final mag1 = math.sqrt(dx1 * dx1 + dy1 * dy1 + dz1 * dz1);
  final mag2 = math.sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2);

  if (mag1 < kMinMagnitude || mag2 < kMinMagnitude) return 0.0;

  final dotProduct = dx1 * dx2 + dy1 * dy2 + dz1 * dz2;
  final cosine = (dotProduct / (mag1 * mag2)).clamp(-1.0, 1.0);
  return math.acos(cosine) * 180 / math.pi;
}

/// Monitors the Hip–Knee–Ankle triad and counts squat repetitions.
///
/// A rep is triggered when the knee angle first crosses below [kSquatDepthMax]
/// (90°) and then returns above [kSquatStandingAngle] (160°).
class SquatHeuristic {
  int repCount = 0;
  // Start in RepPhase.up (standing): the user must squat down before a rep
  // can be counted, preventing a phantom count on the first frame.
  RepPhase _phase = RepPhase.up;
  String statusMessage = 'Align yourself in the frame';

  /// Call once per frame with the current [kneeAngle] in degrees.
  void update(double kneeAngle) {
    if (kneeAngle >= kSquatStandingAngle && _phase == RepPhase.down) {
      repCount++;
      statusMessage = 'Great squat!';
      _phase = RepPhase.up;
    } else if (kneeAngle < kSquatDepthMax && _phase == RepPhase.up) {
      statusMessage = 'Good depth! Now stand up';
      _phase = RepPhase.down;
    } else if (kneeAngle > kSquatDepthMax && kneeAngle < kSquatStandingAngle) {
      statusMessage = _phase == RepPhase.up ? 'Go lower' : 'Stand up';
    } else if (kneeAngle < kSquatDepthMin) {
      statusMessage = 'Too deep - maintain control';
    } else {
      statusMessage = 'Ready to squat';
    }
  }

  /// Resets the rep counter and phase back to initial state.
  void reset() {
    repCount = 0;
    _phase = RepPhase.up;
    statusMessage = 'Align yourself in the frame';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: kAccentCyan,
          secondary: kGoodGreen,
          surface: kSurface,
          onSurface: Colors.white,
          error: kBadRed,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const PoseDetectionScreen(),
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
  final SquatHeuristic _squat = SquatHeuristic();
  double? _kneeAngle;
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
        _squat.statusMessage = 'Move fully into the frame';
        _kneeAngle = null;
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
        _squat.statusMessage = 'Keep your full body visible';
        _kneeAngle = null;
      });
      return;
    }

    // calculateJointAngle handles null landmarks safely
    final angle = calculateJointAngle(hip, knee, ankle);
    _squat.update(angle);

    setState(() {
      _kneeAngle = angle;
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kSurface, Colors.black],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kBadRed.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: kBadRed.withOpacity(0.4), width: 2),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: kBadRed, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                _errorMessage ?? 'An unexpected error occurred',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kAccentCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _initialize,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kSurface, Colors.black],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: kAccentCyan, strokeWidth: 3),
            SizedBox(height: 20),
            Text(
              'Starting camera...',
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  void _resetCount() {
    setState(() {
      _squat.reset();
    });
  }

  Widget _buildTopOverlay() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            // App title badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kAccentCyan.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fitness_center_rounded, color: kAccentCyan, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Squat Analyzer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Rep counter
            _RepCounter(count: _squat.repCount),
            const SizedBox(width: 10),
            // Reset button
            GestureDetector(
              onTap: _resetCount,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatus() {
    final style = _styleForMessage(_squat.statusMessage);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: style.color.withOpacity(0.55), width: 1.5),
          ),
          child: Row(
            children: [
              Icon(style.icon, color: style.color, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _squat.statusMessage,
                  style: TextStyle(
                    color: style.color,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_kneeAngle != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: style.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_kneeAngle!.toStringAsFixed(0)}°',
                    style: TextStyle(
                      color: style.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: _errorMessage != null
          ? _buildError()
          : !_isCameraInitialized
              ? _buildLoading()
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
                          kneeAngle: _kneeAngle,
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopOverlay(),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildBottomStatus(),
                    ),
                  ],
                ),
    );
  }
}

/// Custom painter that maps pose landmarks to the preview canvas and renders a
/// skeletal overlay.
///
/// Lines are drawn **green** when form is correct and **red** when the knee
/// angle exceeds 100° while the subject is squatting (insufficient depth).
class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    this.kneeAngle,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  /// The current Hip–Knee–Ankle angle in degrees, or null when unavailable.
  final double? kneeAngle;

  /// Returns true when the skeleton should be drawn in green (good form).
  ///
  /// Lines turn red only while the subject is actively squatting
  /// (kneeAngle < [kSquatStandingAngle]) and the depth is insufficient
  /// (kneeAngle > [kInsufficientDepthAngle]).
  bool get _isFormGood {
    final a = kneeAngle;
    if (a == null || a >= kSquatStandingAngle) return true;
    return a <= kInsufficientDepthAngle;
  }

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
    final lineColor = _isFormGood ? kGoodGreen : kBadRed;

    final landmarkPaint = Paint()
      ..color = kAccentCyan
      ..strokeWidth = 4
      ..style = PaintingStyle.fill;

    final landmarkOuterPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final linePaint = Paint()
      ..color = lineColor.withOpacity(0.9)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
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
        canvas.drawCircle(point, 7, landmarkPaint);
        canvas.drawCircle(point, 7, landmarkOuterPaint);
      }

      // Annotate the knee angle near the knee landmark
      if (kneeAngle != null) {
        final kneeLm = pose.landmarks[PoseLandmarkType.leftKnee] ??
            pose.landmarks[PoseLandmarkType.rightKnee];
        if (kneeLm != null) {
          final kneePoint = _transform(kneeLm, size);
          _drawAngleLabel(canvas, kneePoint, '${kneeAngle!.toStringAsFixed(0)}°', lineColor);
        }
      }
    }
  }

  void _drawAngleLabel(Canvas canvas, Offset position, String label, Color color) {
    const padding = _kAngleLabelPadding;
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.bold,
    );
    final textSpan = TextSpan(text: label, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        position.dx + 10,
        position.dy - textPainter.height / 2 - padding,
        textPainter.width + padding * 2,
        textPainter.height + padding * 2,
      ),
      const Radius.circular(6),
    );

    canvas.drawRRect(
      bgRect,
      Paint()..color = color.withOpacity(0.75),
    );

    textPainter.paint(
      canvas,
      Offset(position.dx + 10 + padding, position.dy - textPainter.height / 2),
    );
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
        oldDelegate.lensDirection != lensDirection ||
        oldDelegate.kneeAngle != kneeAngle;
  }
}

/// Animated rep counter badge shown in the top overlay.
class _RepCounter extends StatelessWidget {
  const _RepCounter({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween<double>(begin: _kRepCounterScaleBegin, end: _kRepCounterScaleEnd).animate(
          CurvedAnimation(parent: animation, curve: Curves.elasticOut),
        ),
        child: child,
      ),
      child: Container(
        key: ValueKey<int>(count),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAccentCyan.withOpacity(0.6), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: const TextStyle(
                color: kAccentCyan,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'reps',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
