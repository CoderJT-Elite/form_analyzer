import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';
import '../../core/app_constants.dart';
import '../../core/build_info.dart';
import '../../core/app_theme.dart';
import '../../logic/cue_engine.dart';
import '../../logic/exercise_analyzer.dart';
import '../../logic/gravity_frame.dart';
import '../../logic/pose_framing.dart';
import '../../logic/presence_tracker.dart';
import '../../logic/pose_normalizer.dart';
import '../../logic/pose_orientation.dart';
import '../../logic/pose_validity.dart';
import '../../models/exercise_model.dart';
import '../../models/feedback_copy.dart';
import '../../services/device_gravity_service.dart';
import '../../services/pose_detector_service.dart';
import '../../services/session_recorder.dart';
import '../../services/tts_service.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';
import '../widgets/pose_painter.dart';
import '../widgets/workout_summary_dialog.dart';

/// What's blocking the pre-exercise setup screen from advancing, in the
/// priority order they're checked.
enum SetupIssue { notInFrame, wrongOrientation }

class ExerciseScreen extends StatefulWidget {
  final Exercise exercise;
  final bool isRoutineMode;
  final TTSService? tts;
  final bool skipCameraInitialization;
  final Duration minGuidanceDuration;
  final Duration maxGuidanceDuration;
  // Only meaningful alongside skipCameraInitialization: real camera init
  // always sets the frame size itself, so this exists purely so tests can
  // exercise PoseFraming's edge/distance logic without a real camera.
  final Size? imageSizeForTesting;

  /// Supplied by tests; in the app the recorder is created when recording is
  /// switched on in Profile.
  final SessionRecorder? recorder;

  const ExerciseScreen({
    super.key,
    required this.exercise,
    this.isRoutineMode = false,
    this.tts,
    this.skipCameraInitialization = false,
    this.minGuidanceDuration = const Duration(milliseconds: 1500),
    this.maxGuidanceDuration = const Duration(milliseconds: 4000),
    this.imageSizeForTesting,
    this.recorder,
  });

  @override
  State<ExerciseScreen> createState() => ExerciseScreenState();
}

class ExerciseScreenState extends State<ExerciseScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  final PoseDetectorService _poseDetector = PoseDetectorService();
  final DeviceGravityService _gravity = DeviceGravityService();
  final PoseValidator _validator = PoseValidator();
  final PresenceTracker _presence = PresenceTracker();
  late final TTSService _tts;

  /// Records the workout for diagnosis when the athlete has switched that on in
  /// Profile (off by default).
  SessionRecorder? _recorder;
  bool _recordingSaved = false;
  final StorageService _storage = StorageService();

  bool _isCameraInitialized = false;
  Future<void>? _cameraInitializationFuture;
  bool _isProcessingFrame = false;

  // Setup guidance & calibration state
  bool _isSetupGuiding = false;
  // Which problem (if any) is currently blocking setup, checked in priority
  // order (framing before orientation -- there's no point telling someone
  // to turn side-on if half of them isn't even in the shot yet). Null means
  // nothing is blocking and it's safe to advance to the countdown.
  SetupIssue? _setupIssue;
  DateTime? _setupStartTime;
  final OrientationTracker _setupOrientationTracker = OrientationTracker();
  Timer? _guidanceAdvanceTimer;
  Timer? _guidanceFallbackTimer;

  /// Watches for the end of a set once counting has begun.
  Timer? _setWatchTimer;
  bool _setOverHinted = false;

  /// The last time setup saw an athlete properly in frame. The fallback that
  /// starts the countdown anyway needs this to be recent: with nobody there,
  /// starting proves nothing (live test #3 counted down at an empty room).
  DateTime? _lastSetupInFrameAt;

  // Kept as the external name since that's what existing tests/UI code
  // already read; it now means "nothing blocking setup" rather than
  // literally "orientation only".
  bool get isOrientationConfirmed => _setupIssue == null;
  SetupIssue? get setupIssue => _setupIssue;
  bool get isSetupGuiding => _isSetupGuiding;
  bool get isCalibrated => _isCalibrated;
  int get calibrationCountdown => _calibrationCountdown;

  @visibleForTesting
  void handleTestPose(Pose pose) {
    if (_isSetupGuiding) {
      _onPoseDuringSetup(pose);
    }
    _poses.value = [pose];
  }

  int _calibrationCountdown = 3;
  bool _isCalibrated = false;
  Timer? _calibrationTimer;

  // Per-frame state lives in notifiers rather than in setState. Calling
  // setState here would rebuild the whole Stack — camera preview, badges and
  // status panel — on every analysed frame. These let each piece repaint on
  // its own.
  final ValueNotifier<List<Pose>> _poses = ValueNotifier<List<Pose>>(const []);
  final ValueNotifier<String> _statusMessage = ValueNotifier<String>('');
  final ValueNotifier<int> _repCount = ValueNotifier<int>(0);
  final ValueNotifier<int> _setCount = ValueNotifier<int>(0);

  /// What the pose detector should be told: the camera's sensor rotation,
  /// turned to match how the phone is actually lying (see [DeviceGravity]).
  InputImageRotation get _detectionRotation =>
      _gravity.estimate?.detectionRotation ?? _imageRotation;

  /// Gravity in the frame poses are reported in.
  GravityFrame get _gravityFrame => _gravity.estimate?.residual ?? GravityFrame.upright;

  Size? _imageSize;
  // Real camera init always overwrites this with the actual mapped
  // rotation; the default only matters when skipCameraInitialization skips
  // that step (tests), since the pose overlay's build() reads this
  // whenever _imageSize is set, independent of whether the camera pipeline
  // ever ran.
  //
  // This is the camera's own (sensor) rotation: how the preview is drawn, since
  // the UI is locked to portrait. Detection uses [_detectionRotation], which
  // also follows the phone's physical orientation.
  InputImageRotation _imageRotation = InputImageRotation.rotation0deg;

  /// The rotation the poses currently on screen were detected in.
  InputImageRotation _posesRotation = InputImageRotation.rotation0deg;
  late InputImageFormat _inputImageFormat;
  CameraLensDirection _lensDirection = CameraLensDirection.front;
  String? _errorMessage;

  // Zoom state (applies to both front and back cameras when supported).
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;
  double _zoomAtGestureStart = 1.0;

  Future<void> _setZoom(double value) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final clamped = value.clamp(_minZoom, _maxZoom).toDouble();
    if (mounted) setState(() => _zoom = clamped);
    try {
      await controller.setZoomLevel(clamped);
    } catch (e) {
      debugPrint('setZoomLevel failed: $e');
    }
  }

  // Raw-pointer pinch tracking: works on both cameras and doesn't compete
  // with the slider's own drag gesture.
  final Map<int, Offset> _pointers = {};
  double _pinchStartDistance = 0;

  double _pointerDistance() {
    final pts = _pointers.values.take(2).toList();
    return (pts[0] - pts[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStartDistance = _pointerDistance();
      _zoomAtGestureStart = _zoom;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _pinchStartDistance > 0) {
      _setZoom(_zoomAtGestureStart * _pointerDistance() / _pinchStartDistance);
    }
  }

  void _onPointerEnd(PointerEvent e) => _pointers.remove(e.pointer);

  // Workout State
  final List<ExerciseSet> _completedSets = [];
  bool _isResting = false;
  int _restTimeRemaining = 30;
  Timer? _restTimer;
  bool _hapticsEnabled = true;

  /// Whether the rep number is spoken after each counted rep (Profile).
  bool _speakCounts = true;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder;
    _tts = widget.tts ?? TTSService();
    WidgetsBinding.instance.addObserver(this);
    _statusMessage.value = widget.exercise.analyzer.displayMessage;
    if (widget.skipCameraInitialization) {
      _isCameraInitialized = true;
      _imageSize = widget.imageSizeForTesting;
      _startSetupGuidance();
    } else {
      _initialize();
    }
    _loadFeedbackPreferences();
    widget.exercise.analyzer.onRep = (count) {
      if (mounted) {
        final counted = count > _repCount.value;
        if (counted) {
          _triggerHaptic(HapticFeedback.mediumImpact);
          _announceCount(count);
        }
        _repCount.value = count;
        _recorder?.event('rep', {'count': count});
      }
    };
    // Cue delivery is already rate-limited, prioritised and varied by the
    // analyzer's CueEngine, so these just hand the text straight to speech.
    widget.exercise.analyzer.onFeedback = (message) {
      // While the count is being spoken, praise is kept for the streaks: "7. Nice
      // rep. 8. That one was clean." is chatter.
      if (_speakCounts &&
          !widget.exercise.analyzer.isTimedHold &&
          !_streakPhrases.contains(message)) {
        _recorder?.event('speech_skipped', {'text': message, 'why': 'counting aloud'});
        return;
      }
      _say(message, kind: 'praise');
    };
    widget.exercise.analyzer.onNoRep = (reason, spoken) {
      _triggerHaptic(HapticFeedback.heavyImpact);
      _recorder?.event('noRep', {'reason': reason, 'spoken': spoken != null});
      if (spoken != null) _say(spoken, kind: 'noRep');
    };
    widget.exercise.analyzer.onIgnored = (reason) => _recorder?.event('ignored', {'reason': reason});
    widget.exercise.analyzer.onCorrection = (message) => _say(message, kind: 'correction');
    widget.exercise.analyzer.onSafetyAlert = (message) {
      _triggerHaptic(HapticFeedback.heavyImpact);
      _say(message, kind: 'safety', priority: SpeechPriority.urgent);
    };
    _gravity.onQuadrantChanged = () {
      // Turning the phone re-frames every coordinate; that is not the athlete
      // teleporting.
      _validator.reset();
      final e = _gravity.estimate;
      if (e != null) {
        _recorder?.event('quadrant', {
          'turns': e.quarterTurns,
          'rotation': e.detectionRotation.rawValue,
        });
      }
    };
  }

  /// Speak [message], noting it for the recording. Everything the athlete hears
  /// goes through here, so the recording can show what was said and when.
  void _say(String message, {String kind = 'speech', SpeechPriority priority = SpeechPriority.normal}) {
    _recorder?.event('speech', {'text': message, 'kind': kind, 'urgent': priority == SpeechPriority.urgent});
    // The engine drops a phrase when something more important is being said (or
    // the voice is off). The recording used to claim everything was spoken.
    unawaited(_tts.speak(message, priority: priority).then((spoken) {
      if (!spoken) _recorder?.event('speech_dropped', {'text': message, 'kind': kind});
    }));
  }

  /// The streak compliments, the only praise spoken while counting aloud.
  static final Set<String> _streakPhrases = {
    for (final d in kDefaultCues)
      if (d.id == CueIds.streak) ...d.phrasings,
  };

  /// Say the rep number, quietly: any coaching cuts it off.
  void _announceCount(int count) {
    final analyzer = widget.exercise.analyzer;
    if (!_speakCounts) return;
    if (analyzer.isTimedHold) {
      // A hold is not counted second by second; mark the milestones.
      if (count > 0 && count % 15 == 0) {
        _say('$count seconds', kind: 'count', priority: SpeechPriority.low);
      }
      return;
    }
    _say('$count', kind: 'count', priority: SpeechPriority.low);
  }

  Future<void> _loadFeedbackPreferences() async {
    await _tts.init();
    final voiceEnabled = await _storage.isVoiceCoachingEnabled();
    final hapticsEnabled = await _storage.isHapticFeedbackEnabled();
    _speakCounts = await _storage.isRepCountSpeechEnabled();
    if (widget.recorder != null) {
      _recorder = widget.recorder;
    } else if (await _storage.isSessionRecordingEnabled()) {
      _recorder = SessionRecorder(exercise: widget.exercise.type.name);
    }
    _recorder?.event('start', {'analyzer': widget.exercise.analyzer.runtimeType.toString()});
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
        _posesRotation = _imageRotation;
        _gravity.start(
          frontCamera: description.lensDirection == CameraLensDirection.front,
          sensorOrientation: description.sensorOrientation,
        );
        _inputImageFormat = Platform.isIOS
            ? InputImageFormat.bgra8888
            : InputImageFormat.nv21;

        // A fixed 30 fps target keeps the sensor from stretching exposure in
        // indoor light, which is what blurs a fast arm into a smear. A device
        // that refuses it gets the plugin's default instead of no camera.
        CameraController build({int? fps}) => CameraController(
              description,
              ResolutionPreset.medium,
              enableAudio: false,
              fps: fps,
              imageFormatGroup: Platform.isIOS
                  ? ImageFormatGroup.bgra8888
                  : ImageFormatGroup.nv21,
            );

        var controller = build(fps: 30);
        _cameraController = controller;
        try {
          await controller.initialize();
        } on CameraException catch (e) {
          debugPrint('Camera refused a 30 fps target (${e.code}); using the default.');
          try {
            await controller.dispose();
          } catch (_) {}
          controller = build();
          _cameraController = controller;
          await controller.initialize();
        }

        try {
          _minZoom = await controller.getMinZoomLevel();
          _maxZoom = await controller.getMaxZoomLevel();
        } catch (_) {
          _minZoom = 1.0;
          _maxZoom = 1.0;
        }
        _zoom = _minZoom;

        _imageSize = Size(
          controller.value.previewSize!.width,
          controller.value.previewSize!.height,
        );

        await controller.startImageStream(_processImage);

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _errorMessage = null;
          });
          _startSetupGuidance();
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

  void _startSetupGuidance() {
    _calibrationTimer?.cancel();
    _guidanceAdvanceTimer?.cancel();
    _guidanceFallbackTimer?.cancel();

    // Best guess before any pose data has arrived: assume orientation is
    // the thing to fix. _onPoseDuringSetup corrects this immediately once a
    // real frame comes in, e.g. switching to "step back" if that's the
    // actual problem.
    const initialIssue = SetupIssue.wrongOrientation;

    if (mounted) {
      setState(() {
        _isCalibrated = false;
        _isSetupGuiding = true;
        _setupIssue = initialIssue;
        _setupStartTime = DateTime.now();
        _setupOrientationTracker.reset();
      });
    } else {
      _isCalibrated = false;
      _isSetupGuiding = true;
      _setupIssue = initialIssue;
      _setupStartTime = DateTime.now();
      _setupOrientationTracker.reset();
    }

    _setupSpokenAt.clear();
    _lastSetupInFrameAt = null;
    _presence.reset();
    _speakForIssue(initialIssue);

    _guidanceFallbackTimer = Timer(widget.maxGuidanceDuration, _fallbackStart);
  }

  /// After the guidance has run its course, start anyway even if the
  /// orientation is not quite right -- but only if an athlete really is in
  /// frame and the phone is still. Otherwise keep waiting: the countdown used to
  /// fire on a timer alone, at an empty room or a phone still being propped up
  /// (all 8 sets of live test #3), and analysis then ran on garbage.
  void _fallbackStart() {
    if (!mounted || !_isSetupGuiding) return;
    final seen = _lastSetupInFrameAt;
    final athleteThere =
        seen != null && DateTime.now().difference(seen) < const Duration(milliseconds: 1500);
    if (athleteThere && !_gravity.phoneIsMoving) {
      _startCountdown();
      return;
    }
    _guidanceFallbackTimer = Timer(const Duration(milliseconds: 500), _fallbackStart);
  }

  /// Start the countdown once the phone has stopped moving.
  void _advanceWhenReady() {
    if (!mounted || !_isSetupGuiding) return;
    if (_gravity.phoneIsMoving) {
      _guidanceAdvanceTimer?.cancel();
      _guidanceAdvanceTimer =
          Timer(const Duration(milliseconds: 400), _advanceWhenReady);
      return;
    }
    _startCountdown();
  }

  // The framing check can flip between "step back" and "turn side-on" every
  // few frames as the athlete settles, and each flip used to be spoken --
  // "turn side, step back, step back, turn side" (live test 2026-09-20). The
  // screen still updates instantly; only the voice holds each phrase back.
  static const Duration _setupSpeechGap = Duration(seconds: 6);
  final Map<SetupIssue, DateTime> _setupSpokenAt = {};

  void _speakForIssue(SetupIssue issue) {
    final last = _setupSpokenAt[issue];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _setupSpeechGap) return;
    _setupSpokenAt[issue] = now;
    switch (issue) {
      case SetupIssue.notInFrame:
        _say(CameraSetupCopy.notInFrameSpoken, kind: 'setup');
      case SetupIssue.wrongOrientation:
        _say(
          CameraSetupCopy.spokenFor(widget.exercise.analyzer.requiredOrientation),
          kind: 'setup',
        );
    }
  }

  void _onPoseDuringSetup(Pose pose, {InputImageRotation? poseRotation}) {
    if (!_isSetupGuiding) return;

    // Framing is checked first: turning side-on is meaningless advice if
    // half the athlete isn't even in the shot yet.
    final raw = _imageSize;
    final inFrame = PoseFraming.isInFrame(
      pose: pose,
      requiredLandmarks: widget.exercise.analyzer.activeLandmarkTypes,
      // Poses are in the detection frame, which is turned relative to the raw
      // image whenever the phone is on its side.
      imageSize: raw == null
          ? null
          : PoseCoordinates.frameSize(raw, poseRotation ?? _imageRotation),
    );

    if (inFrame) _lastSetupInFrameAt = DateTime.now();

    final observed = _setupOrientationTracker.update(pose);

    final newIssue = !inFrame
        ? SetupIssue.notInFrame
        : (widget.exercise.analyzer.acceptsOrientation(observed)
            ? null
            : SetupIssue.wrongOrientation);

    if (newIssue == _setupIssue) return;

    final wasConfirmed = _setupIssue == null;
    _setupIssue = newIssue;
    if (mounted) setState(() {});
    if (newIssue != null) _speakForIssue(newIssue);

    if (newIssue == null && !wasConfirmed) {
      final startTime = _setupStartTime;
      final elapsed = startTime == null
          ? Duration.zero
          : DateTime.now().difference(startTime);
      final remaining = widget.minGuidanceDuration - elapsed;

      if (remaining <= Duration.zero) {
        _advanceWhenReady();
      } else {
        _guidanceAdvanceTimer?.cancel();
        _guidanceAdvanceTimer = Timer(remaining, _advanceWhenReady);
      }
    } else {
      _guidanceAdvanceTimer?.cancel();
    }
  }

  void _startCountdown() {
    _guidanceAdvanceTimer?.cancel();
    _guidanceFallbackTimer?.cancel();
    _calibrationTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _isSetupGuiding = false;
      _calibrationCountdown = 3;
    });
    _recorder?.event('countdown');
    _say("3", kind: 'countdown', priority: SpeechPriority.urgent);

    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Counting down while the phone is still being propped up starts the set
      // on the wrong picture. Go back to guidance until it is still.
      if (_gravity.phoneIsMoving) {
        timer.cancel();
        _startSetupGuidance();
        return;
      }
      setState(() {
        if (_calibrationCountdown > 1) {
          _calibrationCountdown--;
          _say("$_calibrationCountdown", kind: 'countdown', priority: SpeechPriority.urgent);
        } else {
          _isCalibrated = true;
          _calibrationTimer?.cancel();
          _say("Go!", kind: 'countdown', priority: SpeechPriority.urgent);
          _recorder?.event('go');
          _startSetWatch();
        }
      });
    });
  }

  /// Once the set is under way, notice when it has ended: the athlete walks off
  /// (nobody in the shot) or picks the phone up to stop. Counting stops on its
  /// own in the second case; this tells the athlete the set can be saved.
  void _startSetWatch() {
    _setWatchTimer?.cancel();
    _setOverHinted = false;
    _presence.reset();
    _setWatchTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkSetOver());
  }

  void _checkSetOver() {
    if (!mounted || !_isCalibrated || _isResting) return;
    if (widget.exercise.analyzer.repCount == 0) return;
    final over = _presence.hasBeenAbsentFor(AppConstants.setOverAbsence) ||
        _gravity.phoneIsMoving;
    if (over && !_setOverHinted) {
      _setOverHinted = true;
      _statusMessage.value = 'Set done? Tap the check to save it.';
    } else if (!over && _setOverHinted) {
      _setOverHinted = false;
      _statusMessage.value = widget.exercise.analyzer.displayMessage;
    }
  }

  Future<void> _processImage(CameraImage image) async {
    // Every frame the detector can take is analysed: skipping every other one
    // halved the rate to 6-8 a frame (live test #5), at which fast arms blur and
    // a rep's bottom can fall between two frames. The busy flag below is the
    // throttle: frames that arrive while detection is running are dropped.
    if (_isProcessingFrame || !_isCameraInitialized) return;
    _isProcessingFrame = true;
    final detectStarted = DateTime.now();

    try {
      if (image.planes.isEmpty) {
        debugPrint(
          'Skipping frame: no image planes available (camera may still be initializing).',
        );
        return;
      }
      // Read once: the phone can be turned while this frame is in flight, and
      // the poses that come back belong to the rotation they were detected in.
      final detectionRotation = _detectionRotation;
      final gravity = _gravityFrame;
      final gravityKnown = _gravity.estimate != null;
      final inputImage = _poseDetector.buildInputImage(
        image: image,
        rotation: detectionRotation,
        format: _inputImageFormat,
      );

      final detected = await _poseDetector.processImage(inputImage);
      final detectMs = DateTime.now().difference(detectStarted).inMilliseconds;

      if (!mounted) return;

      // Drop "poses" that are not an athlete (a barbell plate, a blurred face
      // close-up while the phone is put down): they neither count nor draw.
      final raw = _imageSize;
      final poses = raw == null
          ? detected
          : detected
              .where((p) => _validator.accepts(p, PoseCoordinates.frameSize(raw, detectionRotation)))
              .toList();

      if (_isSetupGuiding && poses.isNotEmpty) {
        _onPoseDuringSetup(poses.first, poseRotation: detectionRotation);
      }

      if (_isCalibrated && !_isResting) {
        if (_pausedForPhoneMotion()) {
          // The phone is being carried: nothing it sees is the exercise.
        } else {
          widget.exercise.analyzer.gravityKnown = gravityKnown;
          for (final pose in poses) {
            // Analyzers are written for an upright phone; level the pose first.
            widget.exercise.analyzer.processPose(normalizePose(pose, gravity));
          }
          if (!_setOverHinted) {
            _statusMessage.value = widget.exercise.analyzer.displayMessage;
          }
        }
      }

      // Notifier assignment instead of setState: only the skeleton overlay
      // repaints, leaving CameraPreview and the surrounding chrome alone.
      _presence.frame(athleteVisible: poses.isNotEmpty);
      _recordFrame(detected, poses, detectionRotation, detectMs);
      _posesRotation = detectionRotation;
      _poses.value = poses;
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// The stage of the workout, for the recording.
  String get _stage => _isSetupGuiding
      ? 'setup'
      : (!_isCalibrated ? 'countdown' : (_isResting ? 'rest' : 'active'));

  void _recordFrame(
    List<Pose> detected,
    List<Pose> accepted,
    InputImageRotation rotation,
    int detectMs,
  ) {
    final recorder = _recorder;
    final raw = _imageSize;
    if (recorder == null || raw == null) return;
    final first = detected.isEmpty ? null : detected.first;
    recorder.frame(
      pose: first,
      accepted: first != null && accepted.contains(first),
      rotation: rotation,
      frameSize: PoseCoordinates.frameSize(raw, rotation),
      stage: _stage,
      gravity: _gravity.estimate,
      accel: _gravity.lastSample,
      phoneMoving: _gravity.phoneIsMoving,
      detectMs: detectMs,
    );
  }

  /// Write the recording, if there is one. Saved once per visit to the screen.
  Future<void> _saveRecording(Map<String, Object?> summary) async {
    final recorder = _recorder;
    if (recorder == null || _recordingSaved || recorder.isEmpty) return;
    _recordingSaved = true;
    try {
      await recorder.save(await RecordingStore.directory(), summary: summary);
    } catch (e) {
      debugPrint('Could not save the recording: $e');
    }
  }

  bool _wasPhoneMoving = false;

  /// True while the phone is being picked up or carried. On the moment it starts
  /// moving, take back reps counted just before -- that is the athlete walking
  /// up to the phone, and what the camera sees then is not the exercise.
  bool _pausedForPhoneMotion() {
    final moving = _gravity.phoneIsMoving;
    final analyzer = widget.exercise.analyzer;
    if (moving && !_wasPhoneMoving) {
      final since = (_gravity.phoneMovingSince ?? DateTime.now())
          .subtract(AppConstants.phoneMotionRetractWindow);
      analyzer.retractRepsSince(since);
      analyzer.interrupt();
      _repCount.value = analyzer.repCount;
      _statusMessage.value = 'Phone moved - paused';
      _recorder?.event('phone_moved', {'reps': analyzer.repCount});
    } else if (!moving && _wasPhoneMoving) {
      _statusMessage.value = analyzer.displayMessage;
      _recorder?.event('phone_still');
    }
    _wasPhoneMoving = moving;
    return moving;
  }

  void _onFinishWorkout() async {
    final analyzer = widget.exercise.analyzer;
    final sets = List<ExerciseSet>.from(_completedSets);
    double? rating;
    if (_repCount.value > 0) {
      final setPerformance = analyzer.getPerformanceMetrics();
      rating = setPerformance.averageFormScore;
      sets.add(
        ExerciseSet(
          reps: _repCount.value,
          timestamp: DateTime.now(),
          rating: setPerformance.averageFormScore,
          feedback: setPerformance.commonIssues,
          repRecords: List.of(analyzer.attemptRecords),
        ),
      );
    }
    // The coaching summary covers every set of the workout, not only the one
    // still in progress: finishing a set and then the workout used to leave the
    // report with no coach feedback at all.
    final feedback = PerformanceMetrics.fromRecords(
      sets.expand((set) => set.repRecords),
    ).commonIssues;
    if (sets.isEmpty) {
      // Nothing was counted. That is not the same as nothing happening: the
      // counter may have missed a whole set (it did, twice, on live test #3),
      // and throwing it away with a snackbar lost the athlete's work.
      final choice = await _askAboutEmptySet();
      if (!mounted || choice == null) return; // keep going
      if (choice == _EmptySetSheet.discard) {
        Navigator.pop(context);
        return;
      }
      sets.add(
        ExerciseSet(
          reps: choice,
          countedReps: 0,
          timestamp: DateTime.now(),
          rating: 0,
        ),
      );
      rating = null; // no counted reps, so no form score
    } else if (rating == null) {
      // Finished right after "finish set": the analyzer has been reset, so rate
      // the workout from the sets that were saved rather than from nothing.
      final rated = sets.where((s) => s.counted > 0).toList();
      rating = rated.isEmpty
          ? null
          : rated.fold<double>(0, (sum, s) => sum + s.rating) / rated.length;
    }

    final session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      exerciseType: widget.exercise.type,
      sets: sets,
      overallRating: rating,
      overallFeedback: feedback,
    );

    // Read the previous rating for this exercise before saving, so the
    // comparison is against the last session rather than this one.
    final previousRating = await _previousRatingForExercise();

    if (!mounted) return;
    // The session is saved when the athlete confirms, so a corrected rep count
    // is what is stored (the counter's own number is kept with it).
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WorkoutSummaryDialog(
        session: session,
        previousRating: previousRating,
        onConfirm: (finalSession) async {
          _recorder?.event('confirmed', {
            'counted': finalSession.countedTotal,
            'final': finalSession.totalReps,
          });
          unawaited(_saveRecording({
            'counted': finalSession.countedTotal,
            'final': finalSession.totalReps,
            'build': BuildInfo.label,
          }));
          // Save standalone session if not in routine mode
          if (!widget.isRoutineMode) {
            await _storage.saveSession(finalSession);
          }
          if (!context.mounted) return;
          Navigator.pop(context); // Close dialog
          Navigator.pop(context, finalSession); // Return to dashboard/routine
        },
      ),
    );
  }

  /// Ask what to do about a set in which nothing was counted. Returns the reps
  /// to save (at least 1), [_EmptySetSheet.discard], or null to keep going.
  Future<int?> _askAboutEmptySet() {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (context) => _EmptySetSheet(
        unit: widget.exercise.analyzer.isTimedHold ? 'seconds' : 'reps',
      ),
    );
  }

  /// Overall rating of the most recent stored session for this exercise, or
  /// null if this is the first one.
  Future<double?> _previousRatingForExercise() async {
    try {
      final sessions = await _storage.loadSessions();
      final sameExercise = sessions
          .where((s) => s.exerciseType == widget.exercise.type)
          .where((s) => s.overallRating != null)
          // Ratings from before no-reps existed were made by lenient rules and
          // are not comparable with today's.
          .where((s) => s.scoringVersion >= WorkoutSession.currentScoringVersion)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      return sameExercise.isEmpty ? null : sameExercise.first.overallRating;
    } catch (e) {
      debugPrint('Could not load previous rating: $e');
      return null;
    }
  }

  /// What the set that just ended looked like, shown on the rest screen.
  PerformanceMetrics? _lastSetSummary;

  void _finishSet() {
    if (_repCount.value == 0) return;

    final performance = widget.exercise.analyzer.getPerformanceMetrics();
    _completedSets.add(
      ExerciseSet(
        reps: _repCount.value,
        timestamp: DateTime.now(),
        rating: performance.averageFormScore,
        feedback: performance.commonIssues,
        repRecords: List.of(widget.exercise.analyzer.attemptRecords),
      ),
    );
    _lastSetSummary = performance;
    _recorder?.event('set_finished', {'reps': _repCount.value, 'sets': _completedSets.length});
    _repCount.value = 0;
    _setCount.value = _completedSets.length;
    _setOverHinted = false;
    _presence.reset();
    widget.exercise.analyzer.reset();
    _statusMessage.value = widget.exercise.analyzer.displayMessage;
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
    unawaited(_gravity.dispose());
    _guidanceAdvanceTimer?.cancel();
    _guidanceFallbackTimer?.cancel();
    _calibrationTimer?.cancel();
    _setWatchTimer?.cancel();
    _restTimer?.cancel();
    // Screens left without finishing (back button, app killed by the phone) are
    // still worth having a recording of.
    unawaited(_saveRecording({'left': 'without confirming', 'build': BuildInfo.label}));
    widget.exercise.analyzer.reset();
    widget.exercise.analyzer.onRep = null;
    widget.exercise.analyzer.onFeedback = null;
    widget.exercise.analyzer.onCorrection = null;
    widget.exercise.analyzer.onSafetyAlert = null;
    widget.exercise.analyzer.onNoRep = null;
    widget.exercise.analyzer.onIgnored = null;
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
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview + pose overlay share one correctly-proportioned
          // box so the image isn't stretched and the skeleton stays aligned.
          if (_cameraController != null)
            Center(
              child: AspectRatio(
                aspectRatio: MediaQuery.of(context).orientation ==
                        Orientation.portrait
                    ? 1 / _cameraController!.value.aspectRatio
                    : _cameraController!.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_cameraController!),
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
                                rotation: _posesRotation,
                                previewRotation: _imageRotation,
                                lensDirection: _lensDirection,
                                squatState:
                                    widget.exercise.analyzer is SquatAnalyzer
                                        ? (widget.exercise.analyzer
                                                as SquatAnalyzer)
                                            .squatState
                                        : null,
                                activeLandmarkTypes: widget
                                    .exercise.analyzer.activeLandmarkTypes,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            const ColoredBox(color: Colors.black),

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
                          label: widget.exercise.analyzer.isTimedHold
                              ? 'SECONDS'
                              : 'REPS',
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

          // Setup Guidance & Calibration Overlay
          if (!_isCalibrated) _buildStartupOverlay(),

          // Rest Overlay
          if (_isResting) _buildRestOverlay(),

          // Zoom slider
          if (_maxZoom > _minZoom)
            Positioned(
              left: 20,
              right: 20,
              bottom: 132,
              child: _GlassContainer(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_out, color: Colors.white, size: 20),
                    Expanded(
                      child: Slider(
                        value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
                        min: _minZoom,
                        max: _maxZoom,
                        onChanged: _setZoom,
                      ),
                    ),
                    const Icon(Icons.zoom_in, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_zoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

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
            if (_lastSetSummary != null) ...[
              const SizedBox(height: 24),
              _buildLastSetCard(_lastSetSummary!),
            ],
            const SizedBox(height: 32),
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

  /// A few lines on the set that just ended: what counted, what did not, and the
  /// one thing to fix next set.
  Widget _buildLastSetCard(PerformanceMetrics summary) {
    final type = widget.exercise.type;
    final unit = type.isTimedHold ? 'seconds held' : (summary.totalReps == 1 ? 'rep' : 'reps');
    final lines = <String>[
      '${summary.totalReps} $unit counted',
      if (summary.noRepCount > 0)
        '${summary.noRepCount} ${type.isTimedHold ? 'paused' : "didn't count"}'
            ' (${summary.noReps.entries.map((e) => '${e.key.toLowerCase()} x${e.value}').join(', ')})',
    ];
    final fix = summary.noReps.isNotEmpty
        ? FeedbackCopy.tip(type, _topKey(summary.noReps)).fix
        : (summary.commonIssues.isNotEmpty
            ? FeedbackCopy.tip(type, summary.commonIssues.first).fix
            : 'Clean set. Keep that form.');
    return Container(
      key: const Key('rest-last-set'),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines)
            Text(
              line,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 8),
          Text(
            'Next set: $fix',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppColors.accentCyan, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  static String _topKey(Map<String, int> counts) =>
      (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

  Widget _buildStartupOverlay() {
    if (_isSetupGuiding) {
      final orientation = widget.exercise.analyzer.requiredOrientation;
      final isSideOn = orientation == ViewOrientation.sideOn;
      final issue = _setupIssue;
      final isConfirmed = issue == null;

      // Framing gets its own copy; a confirmed or wrong-orientation state
      // both fall back to the orientation copy, matching the screen's
      // original behavior of always showing the orientation instruction
      // except when framing is the actual blocker.
      final headline = issue == SetupIssue.notInFrame
          ? CameraSetupCopy.notInFrameHeadline
          : CameraSetupCopy.headlineFor(orientation);
      final subtext = issue == SetupIssue.notInFrame
          ? CameraSetupCopy.notInFrameSubtext
          : CameraSetupCopy.subtextFor(orientation);
      final pillText = switch (issue) {
        null => 'Position confirmed',
        SetupIssue.notInFrame => 'Step back a little...',
        SetupIssue.wrongOrientation => 'Adjust your position...',
      };
      final badgeIcon = switch (issue) {
        null => Icons.check_rounded,
        SetupIssue.notInFrame => Icons.zoom_out_map_rounded,
        SetupIssue.wrongOrientation =>
          isSideOn ? Icons.swap_horiz_rounded : Icons.accessibility_new_rounded,
      };

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startCountdown,
        child: Container(
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing Icon Badge
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    border: Border.all(
                      color: isConfirmed
                          ? AppColors.goodGreen
                          : AppColors.accentCyan,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isConfirmed
                                ? AppColors.goodGreen
                                : AppColors.accentCyan)
                            .withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    badgeIcon,
                    size: 44,
                    color: isConfirmed
                        ? AppColors.goodGreen
                        : AppColors.accentCyan,
                  ),
                ),
                const SizedBox(height: 24),

                // Category Header
                Text(
                  'CAMERA SETUP',
                  style: AppTextStyles.setupHeader,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Main Instruction Headline
                Text(
                  headline,
                  style: AppTextStyles.setupInstruction,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Subtext / Description
                Text(
                  subtext,
                  style: AppTextStyles.setupSubtext,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // What counts, in a couple of lines: the rules are strict now, so
                // say them before the set rather than after a rep is turned down.
                Text(
                  widget.exercise.instructions,
                  key: const Key('setup-instructions'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Status Indicator Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: isConfirmed
                        ? AppColors.goodGreen.withValues(alpha: 0.15)
                        : AppColors.surface.withValues(alpha: 0.6),
                    border: Border.all(
                      color: isConfirmed ? AppColors.goodGreen : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConfirmed
                            ? Icons.check_circle_rounded
                            : Icons.videocam_outlined,
                        size: 16,
                        color: isConfirmed
                            ? AppColors.goodGreen
                            : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pillText,
                        style: TextStyle(
                          color: isConfirmed
                              ? AppColors.goodGreen
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Tap to skip hint
                const Text(
                  'Tap anywhere to start countdown',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Countdown Overlay
    return Container(
      color: Colors.black54,
      child: Center(
        child: Text(
          '$_calibrationCountdown',
          style: AppTextStyles.calibrationCountdown,
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
    unawaited(_gravity.stop());
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

/// Shown when the athlete ends a workout in which nothing was counted.
class _EmptySetSheet extends StatefulWidget {
  const _EmptySetSheet({required this.unit});

  /// What is being counted: "reps" or "seconds".
  final String unit;

  /// Returned from the sheet to mean "throw this set away".
  static const int discard = -1;

  @override
  State<_EmptySetSheet> createState() => _EmptySetSheetState();
}

class _EmptySetSheetState extends State<_EmptySetSheet> {
  int _amount = 1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOTHING WAS COUNTED',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'If you did some, say how many and it will be saved. It will not '
              'get a form score, because nothing was analysed.',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: const Key('empty-minus'),
                  onPressed: _amount > 1 ? () => setState(() => _amount = math.max(1, _amount - 1)) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: Colors.white70,
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '$_amount ${widget.unit}',
                    textAlign: TextAlign.center,
                    key: const Key('empty-value'),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('empty-plus'),
                  onPressed: _amount < 999 ? () => setState(() => _amount = math.min(999, _amount + 1)) : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: AppColors.accentCyan,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('empty-save'),
                onPressed: () => Navigator.pop(context, _amount),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentCyan,
                  foregroundColor: Colors.black,
                ),
                child: Text('SAVE $_amount ${widget.unit.toUpperCase()}'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('empty-keep-going'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('KEEP GOING'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    key: const Key('empty-discard'),
                    onPressed: () => Navigator.pop(context, _EmptySetSheet.discard),
                    child: const Text('DISCARD'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
