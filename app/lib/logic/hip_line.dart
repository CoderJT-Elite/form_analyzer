/// Judges whether the hips are sagging or piked, from one number.
///
/// Poses arrive gravity-aligned (see `normalizePose`), so "sagging" is simply
/// "the hip is lower than the straight line from shoulder to ankle".
///
/// Live test #5 heard "Hips are too high, flatten your body out" from a plank
/// whose hips were sagging. The "line is broken" decision came from one
/// unsmoothed angle while the *direction* came from a separate, sticky verdict
/// that stayed on "piked" until the offset had crossed well past zero, held for
/// eight frames and waited four seconds. Two measurements disagreed, and the
/// athlete was told the opposite of the truth. Here there is one smoothed signed
/// offset: whether the line is broken and which way are read from the same
/// number, so they cannot disagree.
library;

import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'signal_filters.dart';

enum HipVerdict {
  /// The body line is straight enough.
  straight,

  /// Hips below the line, toward the floor.
  sagging,

  /// Hips above the line, away from the floor.
  piked,

  /// The body is too upright for a floor-relative verdict (wall lean, steep
  /// incline). The line may still be broken; the direction is unknowable.
  unjudgeable,
}

class HipLineMeter {
  HipLineMeter({
    this.sagBreak = 0.10,
    this.sagClear = 0.07,
    this.pikeBreak = -0.15,
    this.pikeClear = -0.11,
    this.maxTiltDegrees = 60,
    this.smoothing = 0.35,
    this.medianWindow = 5,
  }) : _median = MedianFilter(medianWindow);

  /// Hip offset (share of the shoulder-to-end line's length, positive toward the
  /// floor) at which the hips are called sagging, and below which the call is
  /// withdrawn. About 157 degrees at the hip breaks; 164 clears. (Real sagging
  /// planks in live test #5 read 0.10-0.18; straight ones 0.0-0.08.)
  final double sagBreak;
  final double sagClear;

  /// The same for piking. Pose models place the hip landmark a little high, so a
  /// perfectly decent plank reads a few percent piked (stock clips: median -0.06)
  /// and a pike has to be clearly past that before it is called.
  final double pikeBreak;
  final double pikeClear;

  /// Beyond this angle from horizontal there is no floor line to sag toward.
  final double maxTiltDegrees;

  /// Weight of each new (median-filtered) sample in the running offset.
  final double smoothing;
  final int medianWindow;

  final MedianFilter _median;
  double? _offset;
  HipVerdict _verdict = HipVerdict.straight;

  HipVerdict get verdict => _verdict;

  /// The smoothed offset behind [verdict], or null before the first sample or
  /// while the body is too upright to judge.
  double? get offset => _offset;

  void reset() {
    _median.reset();
    _offset = null;
    _verdict = HipVerdict.straight;
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

  /// Feed one frame and return the verdict.
  HipVerdict update(PoseLandmark shoulder, PoseLandmark hip, PoseLandmark end) {
    if (tiltFromHorizontal(shoulder, end) > maxTiltDegrees) {
      _offset = null;
      _median.reset();
      return _verdict = HipVerdict.unjudgeable;
    }
    final ratio = offsetRatio(shoulder, hip, end);
    if (ratio == null) return _verdict;

    final filtered = _median.add(ratio);
    final previous = _offset;
    final offset = previous == null ? filtered : previous + smoothing * (filtered - previous);
    _offset = offset;

    // Hysteresis: a verdict that stands is only withdrawn once the offset is
    // clearly back inside the (narrower) clear band, so it cannot flicker at the
    // boundary.
    switch (_verdict) {
      case HipVerdict.unjudgeable:
      case HipVerdict.straight:
        if (offset >= sagBreak) {
          _verdict = HipVerdict.sagging;
        } else if (offset <= pikeBreak) {
          _verdict = HipVerdict.piked;
        } else {
          _verdict = HipVerdict.straight;
        }
      case HipVerdict.sagging:
        if (offset < sagClear) {
          _verdict = offset <= pikeBreak ? HipVerdict.piked : HipVerdict.straight;
        }
      case HipVerdict.piked:
        if (offset > pikeClear) {
          _verdict = offset >= sagBreak ? HipVerdict.sagging : HipVerdict.straight;
        }
    }
    return _verdict;
  }
}
