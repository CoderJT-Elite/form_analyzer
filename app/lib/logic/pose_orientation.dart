import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/app_constants.dart';

/// Which way the athlete is standing relative to the camera.
enum ViewOrientation {
  /// Chest toward the camera.
  frontOn,

  /// Profile to the camera — the view most joint-angle checks assume.
  sideOn,

  /// Not enough information, or somewhere in between.
  unknown,
}

/// Infers camera-relative orientation from landmark geometry.
///
/// This matters for correctness, not just polish. A squat's back-angle safety
/// check measures shoulder-hip-knee on one side of the body. Seen from the
/// side that angle genuinely reports spinal flexion; seen head-on the three
/// points are nearly collinear in the image plane no matter what the athlete's
/// back is doing, so the check reads a healthy ~180 degrees and never fires.
/// Silently passing a safety check is worse than not having one, so analyzers
/// use this to gate the checks that depend on a particular view.
class PoseOrientation {
  const PoseOrientation._();

  /// Ratio of average body width to torso height.
  ///
  /// Facing the camera, shoulders and hips are spread wide. In profile the
  /// left and right landmarks sit almost on top of each other, so the ratio
  /// collapses. Dividing by torso height keeps this independent of how far
  /// away the athlete is standing.
  static double? widthToHeightRatio(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    final required = [leftShoulder, rightShoulder, leftHip, rightHip];
    if (required.any((lm) =>
        lm == null || lm.likelihood < AppConstants.visibilityThreshold)) {
      return null;
    }

    final shoulderWidth = _distance(leftShoulder!, rightShoulder!);
    final hipWidth = _distance(leftHip!, rightHip!);

    final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;
    final shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2;
    final hipMidX = (leftHip.x + rightHip.x) / 2;
    final hipMidY = (leftHip.y + rightHip.y) / 2;

    final torsoHeight = math.sqrt(
      math.pow(shoulderMidX - hipMidX, 2) + math.pow(shoulderMidY - hipMidY, 2),
    );

    if (torsoHeight < AppConstants.minMagnitude) return null;

    return ((shoulderWidth + hipWidth) / 2) / torsoHeight;
  }

  /// Single-frame orientation estimate.
  static ViewOrientation detect(Pose pose) {
    final ratio = widthToHeightRatio(pose);
    if (ratio == null) return ViewOrientation.unknown;

    if (ratio <= AppConstants.sideOnMaxWidthRatio) return ViewOrientation.sideOn;
    if (ratio >= AppConstants.frontOnMinWidthRatio) {
      return ViewOrientation.frontOn;
    }
    return ViewOrientation.unknown;
  }

  static double _distance(PoseLandmark a, PoseLandmark b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }
}

/// Debounced orientation, so a single noisy frame can't flip the reading and
/// fire a "turn around" cue at someone who is already standing correctly.
class OrientationTracker {
  ViewOrientation _stable = ViewOrientation.unknown;
  ViewOrientation _candidate = ViewOrientation.unknown;
  int _candidateFrames = 0;

  ViewOrientation get orientation => _stable;

  ViewOrientation update(Pose pose) {
    final observed = PoseOrientation.detect(pose);

    if (observed == _stable) {
      _candidate = observed;
      _candidateFrames = 0;
      return _stable;
    }

    if (observed == _candidate) {
      _candidateFrames++;
    } else {
      _candidate = observed;
      _candidateFrames = 1;
    }

    if (_candidateFrames >= AppConstants.orientationDebounceFrames) {
      _stable = _candidate;
      _candidateFrames = 0;
    }

    return _stable;
  }

  void reset() {
    _stable = ViewOrientation.unknown;
    _candidate = ViewOrientation.unknown;
    _candidateFrames = 0;
  }
}
