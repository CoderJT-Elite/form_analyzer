/// Notices when the phone itself is being picked up or moved.
///
/// The end of a set is the worst moment for a rep counter: the athlete walks up
/// to the phone, and the frames of a person looming at the lens and a camera
/// being carried produce phantom reps (an extra overhead press and a fake
/// plank "second" on live test #3) and false form flags. Counting should simply
/// pause while the camera is not still.
///
/// A phone on the floor also shakes: jumping jacks land hard enough to jolt an
/// accelerometer, and none of that is the phone being *moved*. So this watches
/// the *direction* of gravity, which vibration averages out of, and only calls
/// the phone moving when it has tilted away from where it was resting.
library;

import 'dart:math' as math;

class PhoneMotionMonitor {
  PhoneMotionMonitor({
    this.tiltThresholdDegrees = 8,
    this.settleDegrees = 3,
    this.movingFor = const Duration(milliseconds: 200),
    this.quietFor = const Duration(milliseconds: 800),
    this.fastAlpha = 0.2,
    this.slowAlpha = 0.02,
  });

  /// Angle between the quick and slow gravity estimates that means the phone is
  /// being moved.
  final double tiltThresholdDegrees;

  /// Angle below which the phone is considered at rest again.
  final double settleDegrees;

  /// How long the angle must stay past the threshold to count as movement, so
  /// one jolt does not pause counting.
  final Duration movingFor;

  /// How long the phone must be still before counting resumes.
  final Duration quietFor;

  final double fastAlpha;
  final double slowAlpha;

  _Vec? _fast;
  _Vec? _slow;
  DateTime? _overSince;
  _Vec? _restRef;
  DateTime? _restSince;
  bool _moving = false;
  DateTime? _movingSince;

  /// True while the phone is being moved.
  bool get isMoving => _moving;

  /// When the current bout of movement began, if any.
  DateTime? get movingSince => _movingSince;

  void reset() {
    _fast = null;
    _slow = null;
    _overSince = null;
    _restRef = null;
    _restSince = null;
    _moving = false;
    _movingSince = null;
  }

  /// Feed a raw (unfiltered) accelerometer sample. Returns [isMoving].
  bool addSample(double ax, double ay, double az, DateTime at) {
    final v = _Vec(ax, ay, az);
    if (v.length < 1e-6) return _moving;

    final unit = v.scaled(1 / v.length);
    _fast = _fast == null ? unit : _fast!.blend(unit, fastAlpha);
    _slow = _slow == null ? unit : _slow!.blend(unit, slowAlpha);

    final degrees = _fast!.angleTo(_slow!);

    if (!_moving) {
      if (degrees > tiltThresholdDegrees) {
        _overSince ??= at;
        if (at.difference(_overSince!) >= movingFor) {
          _moving = true;
          _movingSince = _overSince;
          _restRef = null;
          _restSince = null;
        }
      } else {
        _overSince = null;
      }
      return _moving;
    }

    // Moving: it is over once the phone's own attitude has stopped changing for
    // [quietFor], wherever it came to rest. (Waiting for the slow estimate to
    // catch up would take seconds.)
    final ref = _restRef;
    if (ref == null || _fast!.angleTo(ref) > settleDegrees) {
      _restRef = _fast;
      _restSince = at;
    } else if (at.difference(_restSince!) >= quietFor) {
      _moving = false;
      _movingSince = null;
      _overSince = null;
      _restRef = null;
      _restSince = null;
      _slow = _fast;
    }
    return _moving;
  }
}

class _Vec {
  const _Vec(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  double get length => math.sqrt(x * x + y * y + z * z);

  _Vec scaled(double k) => _Vec(x * k, y * k, z * k);

  _Vec blend(_Vec other, double alpha) => _Vec(
        x + alpha * (other.x - x),
        y + alpha * (other.y - y),
        z + alpha * (other.z - z),
      );

  double angleTo(_Vec other) {
    final m = length * other.length;
    if (m < 1e-9) return 0;
    final cos = ((x * other.x + y * other.y + z * other.z) / m).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }
}
