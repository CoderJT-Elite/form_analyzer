/// Rejects "poses" that are not an athlete.
///
/// ML Kit will happily return a skeleton for anything vaguely person-shaped. On
/// live test #3 it drew one on a barbell plate leaning against a rack (twice,
/// for several seconds) and fitted one to the blurred close-up of a face while
/// the phone was being put down. Feeding those to a rep counter is how a
/// counter moves when nobody is exercising, and painting them makes the app
/// look broken.
///
/// This is deliberately a cheap plausibility check, not a second detector.
library;

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseValidator {
  PoseValidator({
    this.minConfidence = 0.5,
    this.minLandmarks = 5,
    this.minSpanFraction = 0.08,
    this.maxJumpFraction = 0.45,
    this.acceptNewPlaceAfter = 6,
  });

  /// Landmark likelihood that counts as "seen".
  final double minConfidence;

  /// How many of the body's main joints must be seen.
  final int minLandmarks;

  /// Smallest span of the visible joints, as a fraction of the frame diagonal.
  /// A person filling any real share of the shot spans 25% or more; real frames
  /// on the recordings never dipped under 11%. A plate is a few percent.
  final double minSpanFraction;

  /// A sudden move of the whole skeleton by more than this fraction of the
  /// frame diagonal between consecutive frames is a detector glitch...
  final double maxJumpFraction;

  /// ...unless it persists this many frames, in which case the athlete really
  /// is somewhere else.
  final int acceptNewPlaceAfter;

  static const _core = <PoseLandmarkType>[
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  ];

  ({double x, double y})? _lastCentre;
  int _rejectedRun = 0;

  void reset() {
    _lastCentre = null;
    _rejectedRun = 0;
  }

  /// Whether [pose] (in a frame of [frameSize]) looks like an athlete.
  bool accepts(Pose pose, Size frameSize) {
    final seen = <PoseLandmark>[
      for (final type in _core)
        if ((pose.landmarks[type]?.likelihood ?? 0) >= minConfidence) pose.landmarks[type]!,
    ];
    if (seen.length < minLandmarks) return _reject();

    final diagonal = math.sqrt(frameSize.width * frameSize.width + frameSize.height * frameSize.height);
    if (diagonal <= 0) return true;

    var span = 0.0;
    var cx = 0.0, cy = 0.0;
    for (var i = 0; i < seen.length; i++) {
      cx += seen[i].x;
      cy += seen[i].y;
      for (var j = i + 1; j < seen.length; j++) {
        final dx = seen[i].x - seen[j].x;
        final dy = seen[i].y - seen[j].y;
        span = math.max(span, math.sqrt(dx * dx + dy * dy));
      }
    }
    if (span / diagonal < minSpanFraction) return _reject();

    cx /= seen.length;
    cy /= seen.length;
    final last = _lastCentre;
    if (last != null) {
      final jump = math.sqrt(math.pow(cx - last.x, 2) + math.pow(cy - last.y, 2)) / diagonal;
      if (jump > maxJumpFraction && _rejectedRun < acceptNewPlaceAfter) {
        return _reject();
      }
    }
    _lastCentre = (x: cx, y: cy);
    _rejectedRun = 0;
    return true;
  }

  bool _reject() {
    _rejectedRun++;
    return false;
  }
}
