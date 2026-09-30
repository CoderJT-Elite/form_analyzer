import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../logic/gravity_frame.dart';
import '../logic/phone_motion.dart';

/// One raw accelerometer reading, kept for the session recorder so the
/// device-axis conventions can be verified against real captures.
class AccelerometerSample {
  const AccelerometerSample(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// Tracks which way is down using the accelerometer.
///
/// The camera's detection rotation follows the phone's physical orientation,
/// so a phone lying on its side still hands ML Kit an upright scene, and the
/// residual tilt is available to level the poses (see `normalizePose`). If the
/// sensor is missing or the phone lies flat, the last known answer (or plain
/// portrait) is used, which is exactly the behaviour before this existed.
class DeviceGravityService {
  DeviceGravityService({
    Stream<AccelerometerSample> Function()? source,
    DateTime Function()? clock,
  })  : _source = source ?? _sensorStream,
        _now = clock ?? DateTime.now;

  final Stream<AccelerometerSample> Function() _source;
  final DateTime Function() _now;
  final PhoneMotionMonitor _motion = PhoneMotionMonitor();

  static Stream<AccelerometerSample> _sensorStream() => accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).map((e) => AccelerometerSample(e.x, e.y, e.z));

  /// Weight of each new sample in the low-pass filter. A person moving into
  /// position sloshes the reading around; this settles it in about a second.
  static const double smoothing = 0.08;

  StreamSubscription<AccelerometerSample>? _subscription;
  bool _front = true;
  int _sensorOrientation = 270;
  double? _ax;
  double? _ay;
  double? _az;
  GravityEstimate? _estimate;

  /// Latest estimate, or null until the first usable reading.
  GravityEstimate? get estimate => _estimate;

  /// The most recent filtered reading, for logging.
  AccelerometerSample? get lastSample => _ax == null ? null : AccelerometerSample(_ax!, _ay!, _az ?? 0);

  /// Called whenever the quadrant (and so the detection rotation) changes.
  VoidCallback? onQuadrantChanged;

  bool get isRunning => _subscription != null;

  /// True while the phone is being picked up or carried, as opposed to lying
  /// still (floor vibration does not count).
  bool get phoneIsMoving => _motion.isMoving;

  /// When the current bout of movement began.
  DateTime? get phoneMovingSince => _motion.movingSince;

  void start({required bool frontCamera, required int sensorOrientation}) {
    _front = frontCamera;
    _sensorOrientation = sensorOrientation;
    _estimate = null;
    _ax = _ay = _az = null;
    _motion.reset();
    _subscription?.cancel();
    try {
      _subscription = _source().listen(_onSample, onError: (Object _) {});
    } catch (_) {
      // No accelerometer: behave as an upright phone.
      _subscription = null;
    }
  }

  void _onSample(AccelerometerSample s) {
    // Motion is judged from the raw reading; the filtered one is for direction.
    _motion.addSample(s.x, s.y, s.z, _now());
    _ax = _ax == null ? s.x : _ax! + smoothing * (s.x - _ax!);
    _ay = _ay == null ? s.y : _ay! + smoothing * (s.y - _ay!);
    _az = _az == null ? s.z : _az! + smoothing * (s.z - _az!);
    update(_ax!, _ay!);
  }

  /// Feed an already-filtered reading. Public so tests can drive it.
  @visibleForTesting
  void update(double ax, double ay) {
    final previous = _estimate;
    final next = DeviceGravity.estimate(
      ax: ax,
      ay: ay,
      frontCamera: _front,
      sensorOrientation: _sensorOrientation,
      previousQuarterTurns: previous?.quarterTurns,
    );
    if (next == null) return;
    _estimate = next;
    if (previous == null || previous.quarterTurns != next.quarterTurns) {
      onQuadrantChanged?.call();
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() => stop();
}

/// The camera's own rotation, for when there is no gravity information.
InputImageRotation sensorRotation(int sensorOrientation) =>
    InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg;
