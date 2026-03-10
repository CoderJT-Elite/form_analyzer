import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../services/pose_detector_service.dart';
import '../../services/storage_service.dart';
import '../../services/tts_service.dart';
import '../widgets/control_icon.dart';
import '../widgets/glass_container.dart';
import '../widgets/pose_painter.dart';
import '../widgets/rep_badge.dart';

class ExerciseScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseScreen({super.key, required this.exercise});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final PoseDetectorService _poseDetector = PoseDetectorService();
  final TTSService _tts = TTSService();
  final StorageService _storage = StorageService();

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _tts.init();
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
      // Unlock orientation to support 180-degree flips
      
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

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessingFrame || !mounted || !_isCalibrated) return;
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
    return InputImageRotation.rotation90deg; // Simplified for now, can add back dynamic sensors
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _poseDetector.dispose();
    _storage.saveWorkout(widget.exercise.analyzer.repCount, widget.exercise.name);
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
                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                ),
                _GlassContainer(
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
                ),
              ],
            ),
            const SizedBox(height: 20),
            RepBadge(count: widget.exercise.analyzer.repCount),
            const Spacer(),
            if (!_isCalibrated)
              Center(
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
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
            _buildStatusFeedback(),
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

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassContainer({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: padding,
      child: child,
    );
  }
}
