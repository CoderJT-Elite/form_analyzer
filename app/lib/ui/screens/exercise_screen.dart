import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
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
  final StorageService _storage = StorageService();

  bool _isCameraInitialized = false;
  Future<void>? _cameraInitializationFuture;
  bool _isProcessingFrame = false;
  int _calibrationCountdown = 3;
  bool _isCalibrated = false;
  static const int _frameSkipInterval = 2;
  int _frameCounter = 0;
  Timer? _calibrationTimer;

  // Per-frame state lives in notifiers rather than in setState. Calling
  // setState here would rebuild the whole Stack — camera preview, badges and
  // status panel — on every analysed frame. These let each piece repaint on
  // its own.
  final ValueNotifier<List<Pose>> _poses = ValueNotifier<List<Pose>>(const []);
  final ValueNotifier<String> _statusMessage = ValueNotifier<String>('');
  final ValueNotifier<int> _repCount = ValueNotifier<int>(0);
  final ValueNotifier<int> _setCount = ValueNotifier<int>(0);

  Size? _imageSize;
  late InputImageRotation _imageRotation;
  late InputImageFormat _inputImageFormat;
  CameraLensDirection _lensDirection = CameraLensDirection.front;
  String? _errorMessage;

  // Workout State
  final List<ExerciseSet> _completedSets = [];
  bool _isResting = false;
  int _restTimeRemaining = 30;
  Timer? _restTimer;
  bool _hapticsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusMessage.value = widget.exercise.analyzer.statusMessage;
    _initialize();
    _loadFeedbackPreferences();
    widget.exercise.analyzer.onRep = (count) {
      if (mounted) {
        if (count > _repCount.value) {
          _triggerHaptic(HapticFeedback.mediumImpact);
        }
        _repCount.value = count;
      }
    };
    // Cue delivery is already rate-limited, prioritised and varied by the
    // analyzer's CueEngine, so these just hand the text straight to speech.
    widget.exercise.analyzer.onFeedback = _tts.speak;
    widget.exercise.analyzer.onCorrection = _tts.speak;
    widget.exercise.analyzer.onSafetyAlert = (message) {
      _triggerHaptic(HapticFeedback.heavyImpact);
      _tts.speak(message);
    };
  }

  Future<void> _loadFeedbackPreferences() async {
    await _tts.init();
    final voiceEnabled = await _storage.isVoiceCoachingEnabled();
    final hapticsEnabled = await _storage.isHapticFeedbackEnabled();
    _tts.setEnabled(voiceEnabled);
    if (mounted) {
      setState(() => _hapticsEnabled = hapticsEnabled);
    }
  }

  Future<void> _initialize() async {
    final inFlightInit = _cameraInitializationFuture;
    if (inFlightInit != null) return inFlightInit;

    final completer = Completer<void>();
    _cameraInitializationFuture = completer.future;
    _isCameraInitialized = false;
    _errorMessage = null;
    if (mounted) setState(() {});
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _errorMessage = 'No cameras available on this device.');
        }
      } else {
        _calibrationTimer?.cancel();
        await _disposeCameraController();

        final description = cameras.firstWhere(
          (cam) => cam.lensDirection == _lensDirection,
          orElse: () => cameras.first,
        );

        _lensDirection = description.lensDirection;
        final mappedRotation = InputImageRotationValue.fromRawValue(
          description.sensorOrientation,
        );
        if (mappedRotation == null) {
          debugPrint(
            'Unknown sensor orientation ${description.sensorOrientation}; using rotation0deg fallback.',
          );
        }
        _imageRotation = mappedRotation ?? InputImageRotation.rotation0deg;
        _inputImageFormat = Platform.isIOS
            ? InputImageFormat.bgra8888
            : InputImageFormat.nv21;

        final controller = CameraController(
          description,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: Platform.isIOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.nv21,
        );

        _cameraController = controller;
        await controller.initialize();

        _imageSize = Size(
          controller.value.previewSize!.width,
          controller.value.previewSize!.height,
        );

        await controller.startImageStream(_processImage);

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _isCalibrated = false;
            _calibrationCountdown = 3;
            _errorMessage = null;
          });
          _startCalibration();
        }
      }
    } on CameraException catch (e) {
      final message = switch (e.code) {
        'CameraAccessDenied' => 'Camera access was denied. Please enable camera permission and try again.',
        'CameraAccessRestricted' => 'Camera access is restricted on this device.',
        'AudioAccessDenied' => 'Microphone/camera permission denied.',
        _ => 'Could not start the camera (${e.code}). Please try again.',
      };
      if (mounted) {
        setState(() => _errorMessage = message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Something went wrong while starting the camera. Please retry.';
        });
      }
    } finally {
      completer.complete();
      _cameraInitializationFuture = null;
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
    // Count every delivered frame before any early return, so the skip
    // interval stays a fixed 1-in-N. Incrementing after the busy check made
    // the effective sample rate drift with detection latency.
    _frameCounter++;
    if (_frameCounter % _frameSkipInterval != 0) return;
    if (_isProcessingFrame || !_isCameraInitialized) return;
    _isProcessingFrame = true;

    try {
      if (image.planes.isEmpty) {
        debugPrint(
          'Skipping frame: no image planes available (camera may still be initializing).',
        );
        return;
      }
      final inputImage = _poseDetector.buildInputImage(
        image: image,
        rotation: _imageRotation,
        format: _inputImageFormat,
      );

      final poses = await _poseDetector.processImage(inputImage);

      if (!mounted) return;

      if (_isCalibrated && !_isResting) {
        for (final pose in poses) {
          widget.exercise.analyzer.processPose(pose);
        }
        _statusMessage.value = widget.exercise.analyzer.statusMessage;
      }

      // Notifier assignment instead of setState: only the skeleton overlay
      // repaints, leaving CameraPreview and the surrounding chrome alone.
      _poses.value = poses;
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _onFinishWorkout() async {
    final sets = List<ExerciseSet>.from(_completedSets);
    if (_repCount.value > 0) {
      final setPerformance = widget.exercise.analyzer.getPerformanceMetrics();
      sets.add(
        ExerciseSet(
          reps: _repCount.value,
          timestamp: DateTime.now(),
          rating: setPerformance.averageFormScore,
          feedback: setPerformance.commonIssues,
          repRecords: List.of(widget.exercise.analyzer.repRecords),
        ),
      );
    }
    if (sets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complete at least one rep before finishing.'),
          ),
        );
      }
      return;
    }

    final performance = widget.exercise.analyzer.getPerformanceMetrics();

    final session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      exerciseType: widget.exercise.type,
      sets: sets,
      overallRating: performance.averageFormScore,
      overallFeedback: performance.commonIssues,
    );

    // Read the previous rating for this exercise before saving, so the
    // comparison is against the last session rather than this one.
    final previousRating = await _previousRatingForExercise();

    // Save standalone session if not in routine mode
    if (!widget.isRoutineMode) {
      await _storage.saveSession(session);
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WorkoutSummaryDialog(
          session: session,
          previousRating: previousRating,
          onConfirm: () {
            Navigator.pop(context); // Close dialog
            Navigator.pop(context, session); // Return to dashboard/routine
          },
        ),
      );
    }
  }

  /// Overall rating of the most recent stored session for this exercise, or
  /// null if this is the first one.
  Future<double?> _previousRatingForExercise() async {
    try {
      final sessions = await _storage.loadSessions();
      final sameExercise = sessions
          .where((s) => s.exerciseType == widget.exercise.type)
          .where((s) => s.overallRating != null)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      return sameExercise.isEmpty ? null : sameExercise.first.overallRating;
    } catch (e) {
      debugPrint('Could not load previous rating: $e');
      return null;
    }
  }

  void _finishSet() {
    if (_repCount.value == 0) return;

    final performance = widget.exercise.analyzer.getPerformanceMetrics();
    _completedSets.add(
      ExerciseSet(
        reps: _repCount.value,
        timestamp: DateTime.now(),
        rating: performance.averageFormScore,
        feedback: performance.commonIssues,
        repRecords: List.of(widget.exercise.analyzer.repRecords),
      ),
    );
    _repCount.value = 0;
    _setCount.value = _completedSets.length;
    widget.exercise.analyzer.reset();
    _statusMessage.value = widget.exercise.analyzer.statusMessage;
    _startRest();
  }

  void _startRest() {
    _restTimer?.cancel();
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
    unawaited(_disposeCameraController());
    _poseDetector.dispose();
    _calibrationTimer?.cancel();
    _restTimer?.cancel();
    widget.exercise.analyzer.reset();
    widget.exercise.analyzer.onRep = null;
    widget.exercise.analyzer.onFeedback = null;
    widget.exercise.analyzer.onCorrection = null;
    widget.exercise.analyzer.onSafetyAlert = null;
    _poses.dispose();
    _statusMessage.dispose();
    _repCount.dispose();
    _setCount.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (mounted) {
        setState(() => _isCameraInitialized = false);
      }
      unawaited(_disposeCameraController());
    } else if (state == AppLifecycleState.resumed &&
        _cameraController == null &&
        mounted) {
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

          // Pose Landmarks Overlay. RepaintBoundary keeps the per-frame
          // skeleton repaint from dirtying the camera preview behind it.
          if (_imageSize != null)
            RepaintBoundary(
              child: ValueListenableBuilder<List<Pose>>(
                valueListenable: _poses,
                builder: (context, poses, _) {
                  if (poses.isEmpty) return const SizedBox.shrink();
                  return CustomPaint(
                    painter: PosePainter(
                      poses: poses,
                      imageSize: _imageSize!,
                      rotation: _imageRotation,
                      lensDirection: _lensDirection,
                      squatState: widget.exercise.analyzer is SquatAnalyzer
                          ? (widget.exercise.analyzer as SquatAnalyzer)
                              .squatState
                          : null,
                      activeLandmarkTypes:
                          widget.exercise.analyzer.activeLandmarkTypes,
                    ),
                  );
                },
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
                      ValueListenableBuilder<int>(
                        valueListenable: _repCount,
                        builder: (context, reps, _) => _StatBadge(
                          label: 'REPS',
                          value: '$reps',
                          isMain: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: _setCount,
                        builder: (context, sets, _) => _StatBadge(
                          label: 'SETS',
                          value: '$sets',
                        ),
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
                  style: AppTextStyles.calibrationCountdown,
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
                    onPressed: () async {
                      setState(() {
                        _lensDirection =
                            _lensDirection == CameraLensDirection.back
                            ? CameraLensDirection.front
                            : CameraLensDirection.back;
                      });
                      await _initialize();
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
              onPressed: () {
                _restTimer?.cancel();
                setState(() => _isResting = false);
              },
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
                child: ValueListenableBuilder<String>(
                  valueListenable: _statusMessage,
                  builder: (context, message, _) => Text(
                    message,
                    style: AppTextStyles.statusMessage,
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 56),
              const SizedBox(height: 20),
              Text(
                'CAMERA UNAVAILABLE',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _initialize,
                  child: const Text('RETRY CAMERA'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('GO BACK'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerHaptic(Future<void> Function() callback) {
    if (!_hapticsEnabled) return;
    callback();
  }

  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller == null) return;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping image stream: $e');
    }

    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('Error disposing camera controller: $e');
    }
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
          Text(label, style: AppTextStyles.statBadgeLabel),
          Text(
            value,
            style: isMain
                ? AppTextStyles.statBadgeValueMain
                : AppTextStyles.statBadgeValue,
          ),
        ],
      ),
    );
  }
}

/// Glass panel tuned for sitting on top of the live camera preview.
///
/// The backdrop blur is switched off here: three blurred panels over a moving
/// video feed cost a full-screen GPU pass each, every frame. A darker fill
/// keeps the text just as legible for a fraction of the cost.
class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassContainer({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: padding,
      blur: 0,
      backgroundColor: AppColors.glassOverCamera,
      child: child,
    );
  }
}
