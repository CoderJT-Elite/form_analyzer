import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';
import '../../core/app_constants.dart';
import '../../logic/exercise_analyzer.dart';
import '../../models/exercise_model.dart';
import '../../services/pose_detector_service.dart';
import '../../services/tts_service.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';
import '../widgets/pose_painter.dart';
import '../widgets/workout_summary_dialog.dart';

class ExerciseScreen extends StatefulWidget {
  final Exercise exercise;
  final bool isRoutineMode;

  const ExerciseScreen({
    super.key,
    required this.exercise,
    this.isRoutineMode = false,
  });

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  final PoseDetectorService _poseDetector = PoseDetectorService();
  final TTSService _tts = TTSService();

  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  int _calibrationCountdown = 3;
  bool _isCalibrated = false;
  Timer? _calibrationTimer;
  List<Pose> _poses = [];
  Size? _imageSize;
  final InputImageRotation _imageRotation = InputImageRotation.rotation90deg;
  CameraLensDirection _lensDirection = CameraLensDirection.front;
  String? _errorMessage;

  // Workout State
  final List<ExerciseSet> _completedSets = [];
  int _currentRepCount = 0;
  bool _isResting = false;
  int _restTimeRemaining = 30;
  Timer? _restTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _tts.init();
    widget.exercise.analyzer.onRep = (count) {
      if (mounted) {
        setState(() => _currentRepCount = count);
        _tts.speak("$count");
      }
    };
    // Task 3: Wire TTS feedback for coaching cues (e.g. "Go deeper next time.").
    widget.exercise.analyzer.onFeedback = (message) {
      _tts.speakFeedback(message);
    };
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      final description = cameras.firstWhere(
        (cam) => cam.lensDirection == _lensDirection,
        orElse: () => cameras.first,
      );

      _lensDirection = description.lensDirection;

      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      _cameraController = controller;
      await controller.initialize();

      _imageSize = Size(
        controller.value.previewSize!.width,
        controller.value.previewSize!.height,
      );

      await controller.startImageStream(_processImage);

      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _startCalibration();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  void _startCalibration() {
    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_calibrationCountdown > 0) {
            _calibrationCountdown--;
            _tts.speak("$_calibrationCountdown");
          } else {
            _isCalibrated = true;
            _calibrationTimer?.cancel();
            _tts.speak("Go!");
          }
        });
      }
    });
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessingFrame || !_isCameraInitialized) return;
    _isProcessingFrame = true;

    try {
      final inputImage = InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _imageRotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final poses = await _poseDetector.processImage(inputImage);

      if (mounted && _isCalibrated && !_isResting) {
        for (final pose in poses) {
          widget.exercise.analyzer.processPose(pose);
        }
      }

      if (mounted) {
        setState(() {
          _poses = poses;
        });
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _onFinishWorkout() async {
    // Collect all sets into a session
    final performance = widget.exercise.analyzer.getPerformanceMetrics();

    final session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      exerciseType: widget.exercise.type,
      sets: _completedSets,
      overallRating: performance.averageFormScore,
      overallFeedback: performance.commonIssues,
    );

    // Save standalone session if not in routine mode
    if (!widget.isRoutineMode) {
      await StorageService().saveSession(session);
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WorkoutSummaryDialog(
          session: session,
          onConfirm: () {
            Navigator.pop(context); // Close dialog
            Navigator.pop(context, session); // Return to dashboard/routine
          },
        ),
      );
    }
  }

  void _finishSet() {
    if (_currentRepCount > 0) {
      final performance = widget.exercise.analyzer.getPerformanceMetrics();
      setState(() {
        _completedSets.add(
          ExerciseSet(
            reps: _currentRepCount,
            timestamp: DateTime.now(),
            rating: performance.averageFormScore,
            feedback: performance.commonIssues,
          ),
        );
        _currentRepCount = 0;
        widget.exercise.analyzer.reset();
        _startRest();
      });
    }
  }

  void _startRest() {
    setState(() {
      _isResting = true;
      _restTimeRemaining = 30;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_restTimeRemaining > 0) {
            _restTimeRemaining--;
          } else {
            _isResting = false;
            _restTimer?.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _poseDetector.dispose();
    _calibrationTimer?.cancel();
    _restTimer?.cancel();
    widget.exercise.analyzer.reset();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _buildError();
    }
    if (!_isCameraInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          CameraPreview(_cameraController!),

          // Pose Landmarks Overlay
          if (_poses.isNotEmpty && _imageSize != null)
            CustomPaint(
              painter: PosePainter(
                poses: _poses,
                imageSize: _imageSize!,
                rotation: _imageRotation,
                lensDirection: _lensDirection,
                squatState: widget.exercise.analyzer is SquatAnalyzer
                    ? (widget.exercise.analyzer as SquatAnalyzer).squatState
                    : null,
                isBusy: _isProcessingFrame,
              ),
            ),

          // Header Stats
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatBadge(
                        label: 'REPS',
                        value: '$_currentRepCount',
                        isMain: true,
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        label: 'SETS',
                        value: '${_completedSets.length}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStatusFeedback(),
                ],
              ),
            ),
          ),

          // Calibration Overlay
          if (!_isCalibrated)
            Container(
              color: Colors.black54,
              child: Center(
                child: Text(
                  '$_calibrationCountdown',
                  style: GoogleFonts.outfit(
                    color: AppColors.accentCyan,
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),

          // Rest Overlay
          if (_isResting) _buildRestOverlay(),

          // Footer Controls
          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: Row(
              children: [
                _GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    onPressed: () {
                      setState(() {
                        _lensDirection =
                            _lensDirection == CameraLensDirection.back
                            ? CameraLensDirection.front
                            : CameraLensDirection.back;
                        _initialize();
                      });
                    },
                    icon: const Icon(
                      Icons.flip_camera_ios_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                const Spacer(),
                if (_isCalibrated && !_isResting)
                  _GlassContainer(
                    padding: const EdgeInsets.all(12),
                    child: IconButton(
                      onPressed: _finishSet,
                      icon: const Icon(
                        Icons.add_task_rounded,
                        color: AppColors.accentCyan,
                        size: 26,
                      ),
                    ),
                  ),
                if (_isCalibrated) ...[
                  const SizedBox(width: 8),
                  _GlassContainer(
                    padding: const EdgeInsets.all(12),
                    child: IconButton(
                      onPressed: _onFinishWorkout,
                      icon: const Icon(
                        Icons.stop_rounded,
                        color: Colors.redAccent,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RESTING',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: _restTimeRemaining / 30,
                    strokeWidth: 8,
                    color: AppColors.accentCyan,
                    backgroundColor: Colors.white10,
                  ),
                ),
                Text(
                  '$_restTimeRemaining',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => setState(() => _isResting = false),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'SKIP REST',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFeedback() {
    final msg = widget.exercise.analyzer.statusMessage;
    return _GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.accentCyan),
          const SizedBox(width: 14),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 100),
              child: SingleChildScrollView(
                child: Text(
                  msg,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final bool isMain;

  const _StatBadge({
    required this.label,
    required this.value,
    this.isMain = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      padding: EdgeInsets.symmetric(horizontal: isMain ? 24 : 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: isMain ? AppColors.accentCyan : Colors.white,
              fontSize: isMain ? 32 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassContainer({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(padding: padding, child: child);
  }
}
