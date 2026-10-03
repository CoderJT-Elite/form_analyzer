/// Scale-free body measurements shared by the strict rep gates.
///
/// Everything here is expressed in the gravity-aligned frame (+y is down), as
/// every analyzer receives it, and normalised by the athlete's own leg length so
/// it holds at any camera distance. Hip height is the main one: "how far has the
/// hip dropped toward the ankle, as a share of the leg" is what separates a squat
/// from a toe-touch, which a knee angle alone cannot (live test #5 counted eight
/// hip hinges, and praised them, because the leg landmarks flipped for a frame).
library;

import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'signal_filters.dart';

/// One frame of leg geometry from the more trustworthy side of the body.
class LegSample {
  LegSample({
    required this.hip,
    required this.knee,
    required this.ankle,
    this.shoulder,
    required this.legLength,
    required this.hipHeight,
    required this.kneeAngle,
    required this.torsoFromVertical,
  });

  final PoseLandmark hip;
  final PoseLandmark knee;
  final PoseLandmark ankle;
  final PoseLandmark? shoulder;

  /// Thigh plus shin, in pixels.
  final double legLength;

  /// Vertical distance from ankle up to hip as a share of [legLength]: about
  /// 0.96-1.0 standing, 0.45-0.55 at parallel, 0.25-0.4 in a deep squat, and
  /// 0.75-0.9 at the bottom of a hip hinge.
  final double hipHeight;

  /// Hip-knee-ankle angle measured in the image plane.
  final double kneeAngle;

  /// Shoulder-hip line's angle from vertical, or null without a shoulder.
  final double? torsoFromVertical;

  /// Smallest likelihood among the landmarks this sample was built from.
  double get minLikelihood => math.min(
        math.min(hip.likelihood, knee.likelihood),
        math.min(ankle.likelihood, shoulder?.likelihood ?? 1),
      );
}

double _dist(PoseLandmark a, PoseLandmark b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Angle at [b] between [a] and [c], in the image plane.
double angle2D(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  final v1x = a.x - b.x, v1y = a.y - b.y;
  final v2x = c.x - b.x, v2y = c.y - b.y;
  final d = math.sqrt(v1x * v1x + v1y * v1y) * math.sqrt(v2x * v2x + v2y * v2y);
  if (d < 1e-9) return 180;
  final cos = ((v1x * v2x + v1y * v2y) / d).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// Degrees the line from [lower] up to [upper] leans from straight up.
double degreesFromUp(PoseLandmark upper, PoseLandmark lower) {
  final dx = (upper.x - lower.x).abs();
  final dy = lower.y - upper.y; // positive when upper is above lower
  return math.atan2(dx, dy) * 180 / math.pi;
}

/// Every leg that is visible enough to measure (zero, one or two).
List<LegSample> sampleLegs(Pose pose, double minLikelihood) {
  final legs = <LegSample>[];
  for (final side in const [
    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, PoseLandmarkType.leftShoulder),
    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, PoseLandmarkType.rightShoulder),
  ]) {
    final hip = pose.landmarks[side.$1];
    final knee = pose.landmarks[side.$2];
    final ankle = pose.landmarks[side.$3];
    if (hip == null || knee == null || ankle == null) continue;
    if (hip.likelihood < minLikelihood ||
        knee.likelihood < minLikelihood ||
        ankle.likelihood < minLikelihood) {
      continue;
    }
    final legLength = _dist(hip, knee) + _dist(knee, ankle);
    if (legLength < 1e-6) continue;
    final shoulderLm = pose.landmarks[side.$4];
    final shoulder =
        shoulderLm != null && shoulderLm.likelihood >= minLikelihood ? shoulderLm : null;
    legs.add(LegSample(
      hip: hip,
      knee: knee,
      ankle: ankle,
      shoulder: shoulder,
      legLength: legLength,
      hipHeight: (ankle.y - hip.y) / legLength,
      kneeAngle: angle2D(hip, knee, ankle),
      torsoFromVertical: shoulder == null ? null : degreesFromUp(shoulder, hip),
    ));
  }
  return legs;
}

/// The better-seen leg, or null when neither is visible enough. [minLikelihood]
/// is the usual landmark bar.
LegSample? sampleLeg(Pose pose, double minLikelihood) {
  LegSample? best;
  var bestConfidence = -1.0;
  for (final leg in sampleLegs(pose, minLikelihood)) {
    final confidence = leg.hip.likelihood + leg.knee.likelihood + leg.ankle.likelihood;
    if (confidence > bestConfidence) {
      bestConfidence = confidence;
      best = leg;
    }
  }
  return best;
}

/// Notices the athlete drifting toward or away from the camera.
///
/// Measured from leg length while the athlete stands tall, which is the one
/// moment it is comparable from frame to frame. Live test #5 counted two squats
/// as the athlete walked up to the phone to stop recording.
class ScaleWatch {
  ScaleWatch({this.baselineSamples = 25, this.tolerance = 0.45});

  /// Standing samples that fix the baseline.
  final int baselineSamples;

  /// How far (as a fraction) the recent standing scale may stray from baseline.
  /// Deliberately wide: athletes drift 20% closer over a set without anyone
  /// being wrong (live test #3), so only a walk up to the phone should trip it.
  final double tolerance;

  final List<double> _baseline = [];
  final MedianFilter _recent = MedianFilter(9);
  double? _fixed;
  bool _drifted = false;

  bool get drifted => _drifted;

  void reset() {
    _baseline.clear();
    _recent.reset();
    _fixed = null;
    _drifted = false;
  }

  /// Feed the leg length of a frame in which the athlete is standing tall.
  /// Returns true the moment the drift state flips to drifted.
  bool updateStanding(double legLength) {
    final fixed = _fixed;
    if (fixed == null) {
      _baseline.add(legLength);
      if (_baseline.length >= baselineSamples) _fixed = medianOf(_baseline);
      return false;
    }
    final recent = _recent.add(legLength);
    final now = (recent / fixed - 1).abs() > tolerance;
    final flipped = now && !_drifted;
    _drifted = now;
    return flipped;
  }
}
