import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../services/pose_detector_service.dart';
import '../../services/tts_service.dart';
import '../widgets/control_icon.dart';
import '../widgets/glass_container.dart';
import '../widgets/pose_painter.dart';

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
  InputImageRotation _imageRotation = InputImageRotation.rotation0deg;
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  String? _errorMessage;

  // New Workout State
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
    _calibrationCountdown = 3;
    _isCalibrated = false;
    _calibrationTimer?.cancel();
    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_calibrationCountdown > 1) {
            _calibrationCountdown--;
          } else {
            _isCalibrated = true;
            _calibrationTimer?.cancel();
            _tts.speak("Start ${widget.exercise.name} now!");
          }
        });
      }
    });
  }

  void _finishSet() {
    if (_currentRepCount == 0 && widget.exercise.type != ExerciseType.plank) {
      return;
    }

    final set = ExerciseSet(
      reps: widget.exercise.type == ExerciseType.plank ? 0 : _currentRepCount,
      duration: widget.exercise.type == ExerciseType.plank
          ? Duration(seconds: widget.exercise.analyzer.repCount)
          : null,
      timestamp: DateTime.now(),
    );

    setState(() {
      _completedSets.add(set);
      _currentRepCount = 0;
      widget.exercise.analyzer.reset();
      _startRestTimer();
    });

    _tts.speak("Set complete. Resting for 30 seconds.");
  }

  void _startRestTimer() {
    setState(() {
      _isResting = true;
      _restTimeRemaining = 30;
    });

    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_restTimeRemaining > 1) {
            _restTimeRemaining--;
          } else {
            _isResting = false;
            _restTimer?.cancel();
            _tts.speak("Rest over. Get ready for the next set.");
          }
        });
      }
    });
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessingFrame || !mounted || !_isCalibrated || _isResting) return;
    _isProcessingFrame = true;

    try {
      final rotation = _getImageRotation();
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final poses = await _poseDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _poses = poses;
          _imageRotation = rotation;
        });

        if (poses.isNotEmpty) {
          final oldMsg = widget.exercise.analyzer.statusMessage;
          widget.exercise.analyzer.processPose(poses.first);
          if (widget.exercise.analyzer.statusMessage != oldMsg) {
            _tts.speak(widget.exercise.analyzer.statusMessage);
          }
        }
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImageRotation _getImageRotation() {
    return InputImageRotation
        .rotation90deg; // Simplified for now, can add back dynamic sensors
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _poseDetector.dispose();
    _calibrationTimer?.cancel();
    _restTimer?.cancel();

    // The workout saving/returning logic is now handled by _finishWorkout
    // which is called when the user explicitly stops the workout or when the screen is popped.
    // No need to call _finishWorkout here as dispose might be called for other reasons
    // (e.g., screen rotation) before the workout is truly finished by user action.

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!),
          if (_poses.isNotEmpty && _imageSize != null)
            CustomPaint(
              painter: PosePainter(
                poses: _poses,
                imageSize: _imageSize!,
                rotation: _imageRotation,
                lensDirection: _lensDirection,
                lastAngle: widget.exercise.analyzer.lastProcessedAngle,
              ),
            ),
          _buildUI(),
          if (_isResting) _buildRestOverlay(),
          if (_errorMessage != null) _buildError(),
        ],
      ),
    );
  }

  Widget _buildUI() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
                _GlassContainer(
<<<<<<< Updated upstream
                   padding: const EdgeInsets.all(4),
                   child: Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       Hero(
                         tag: 'exercise_${widget.exercise.type.name}',
                         child: Icon(widget.exercise.icon, color: AppColors.accentCyan, size: 24),
                       ),
                       const SizedBox(width: 8),
                       ControlIcon(
                         icon: _tts.isEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                         onTap: () => setState(() => _tts.toggle()),
                       ),
                       ControlIcon(
                         icon: Icons.flip_camera_ios_rounded,
                         onTap: () {
                           _lensDirection = _lensDirection == CameraLensDirection.back 
                               ? CameraLensDirection.front 
                               : CameraLensDirection.back;
                           _initialize();
                         },
                       ),
                     ],
                   ),
=======
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'exercise_${widget.exercise.type.name}',
                        child: Icon(
                          widget.exercise.icon,
                          color: AppColors.accentCyan,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ControlIcon(
                        icon: _tts.isEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        onTap: () => setState(() => _tts.toggle()),
                      ),
                      ControlIcon(
                        icon: Icons.flip_camera_ios_rounded,
                        onTap: () {
                          _lensDirection =
                              _lensDirection == CameraLensDirection.back
                              ? CameraLensDirection.front
                              : CameraLensDirection.back;
                          _initialize();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatBadge(label: 'SET', value: '${_completedSets.length + 1}'),
                const SizedBox(width: 12),
                _StatBadge(
                  label: widget.exercise.type == ExerciseType.plank
                      ? 'TIME'
                      : 'REPS',
                  value: widget.exercise.type == ExerciseType.plank
                      ? '${widget.exercise.analyzer.repCount}s'
                      : '$_currentRepCount',
                  isMain: true,
>>>>>>> Stashed changes
                ),
              ],
            ),
            const Spacer(),
            if (!_isCalibrated)
              Center(
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 30,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GET READY',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _calibrationCountdown.toString(),
                        style: GoogleFonts.outfit(
                          color: AppColors.accentCyan,
                          fontSize: 80,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_isCalibrated) const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _buildStatusFeedback()),
                  const SizedBox(width: 8),
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
                        onPressed: () => Navigator.pop(context),
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
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.fitness_center_rounded, color: AppColors.accentCyan),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
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
    return GlassContainer(
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
