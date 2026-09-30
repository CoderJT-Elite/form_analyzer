/// Judges whether the hips are sagging or piked, without flip-flopping.
///
/// Poses arrive gravity-aligned (see `normalizePose`), so "sagging" is simply
/// "the hip is lower than the straight line from shoulder to knee/ankle".
///
/// Two things went wrong before this existed (live tests #2 and #3):
///   * the verdict was recomputed from a single frame, so a plank read "hips
///     too high" and "hips too low" within seconds of each other, and
///   * it was answered even when there is no floor to sag toward. Leaning on a
///     wall, the body is nearly vertical and "lower than the line" means
///     nothing; the athlete still deserves to hear their body line is broken,
///     just not in a direction.
library;

import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum HipVerdict {
  /// Not enough signal yet to call it either way.
  undecided,

  /// Hips below the line, toward the floor.
  sagging,

  /// Hips above the line, away from the floor.
  piked,

  /// The body is too upright for a floor-relative verdict (wall lean, steep
  /// incline). The line may still be broken; the direction is unknowable.
  unjudgeable,
}

class HipLineJudge {
  HipLineJudge({
    this.smoothing = 0.25,
    this.enter = 0.03,
    this.switchMargin = 0.05,
    this.maxTiltDegrees = 60,
    this.dwellFrames = 8,
    this.minReversal = const Duration(seconds: 4),
  });

  /// Weight of each new sample in the running offset.
  final double smoothing;

  /// Smoothed offset (fraction of body length) needed to call a direction.
  final double enter;

  /// How far past zero the opposite way the smoothed offset must go before a
  /// standing verdict is reversed.
  final double switchMargin;

  /// Beyond this angle from horizontal there is no floor line to sag toward.
  final double maxTiltDegrees;

  /// A new verdict must hold for this many consecutive frames before it stands.
  /// While an athlete is still moving into position the reading swings by more
  /// than the switch margin in a fraction of a second.
  final int dwellFrames;

  /// Once a direction has been called, the opposite one is not called again for
  /// this long: "hips up" followed by "lower your hips" a second later (live
  /// test #3) teaches the athlete nothing.
  final Duration minReversal;

  double? _offset;
  HipVerdict _verdict = HipVerdict.undecided;
  HipVerdict _candidate = HipVerdict.undecided;
  int _candidateFrames = 0;
  HipVerdict? _lastDirection;
  DateTime? _lastDirectionAt;

  HipVerdict get verdict => _verdict;

  void reset() {
    _offset = null;
    _verdict = HipVerdict.undecided;
    _candidate = HipVerdict.undecided;
    _candidateFrames = 0;
    _lastDirection = null;
    _lastDirectionAt = null;
  }

  /// Signed distance of [hip] below the shoulder-[end] line, as a fraction of
  /// that line's length. Positive means toward gravity (sagging). Null when the
  /// line is too short to mean anything.
  static double? offsetRatio(PoseLandmark shoulder, PoseLandmark hip, PoseLandmark end) {
    final dx = end.x - shoulder.x;
    final dy = end.y - shoulder.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-6) return null;
    // Perpendicular component of (hip - shoulder), signed so that "down the
    // image" is positive whichever way the body lies.
    final cross = dx * (hip.y - shoulder.y) - dy * (hip.x - shoulder.x);
    final side = dx >= 0 ? 1.0 : -1.0;
    return side * cross / (length * length);
  }

  /// Degrees the shoulder-end line is from horizontal: 0 lying flat on the
  /// floor, 90 standing upright.
  static double tiltFromHorizontal(PoseLandmark shoulder, PoseLandmark end) {
    final dx = (end.x - shoulder.x).abs();
    final dy = (end.y - shoulder.y).abs();
    return math.atan2(dy, dx) * 180 / math.pi;
  }

  /// Feed one frame and return the current verdict. [now] enables the minimum
  /// time between opposite calls.
  HipVerdict update(PoseLandmark shoulder, PoseLandmark hip, PoseLandmark end, {DateTime? now}) {
    if (tiltFromHorizontal(shoulder, end) > maxTiltDegrees) {
      _offset = null;
      return _settle(HipVerdict.unjudgeable, now);
    }
    final ratio = offsetRatio(shoulder, hip, end);
    if (ratio == null) return _verdict;

    final previous = _offset;
    final offset = previous == null ? ratio : previous + smoothing * (ratio - previous);
    _offset = offset;

    HipVerdict wanted = _verdict;
    switch (_verdict) {
      case HipVerdict.undecided:
      case HipVerdict.unjudgeable:
        if (offset >= enter) {
          wanted = HipVerdict.sagging;
        } else if (offset <= -enter) {
          wanted = HipVerdict.piked;
        } else {
          wanted = HipVerdict.undecided;
        }
      case HipVerdict.sagging:
        if (offset <= -switchMargin) wanted = HipVerdict.piked;
      case HipVerdict.piked:
        if (offset >= switchMargin) wanted = HipVerdict.sagging;
    }
    return _settle(wanted, now);
  }

  /// Adopt [wanted] only once it has persisted, and not too soon after the
  /// last opposite call.
  HipVerdict _settle(HipVerdict wanted, DateTime? now) {
    if (wanted == _verdict) {
      _candidate = wanted;
      _candidateFrames = 0;
      return _verdict;
    }
    if (wanted == _candidate) {
      _candidateFrames++;
    } else {
      _candidate = wanted;
      _candidateFrames = 1;
    }
    final directional = wanted == HipVerdict.sagging || wanted == HipVerdict.piked;
    // Judged against the last *direction called*, not the current verdict: an
    // athlete standing up passes through "unjudgeable" on the way from one to
    // the other, which must not launder a reversal.
    final tooSoon = directional &&
        now != null &&
        _lastDirection != null &&
        wanted != _lastDirection &&
        _lastDirectionAt != null &&
        now.difference(_lastDirectionAt!) < minReversal;
    if (_candidateFrames >= dwellFrames && !tooSoon) {
      _verdict = wanted;
      _candidateFrames = 0;
      if (directional) {
        _lastDirection = wanted;
        _lastDirectionAt = now;
      }
    }
    return _verdict;
  }
}
