import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Builders for synthetic poses, so analyzers can be driven through real
/// movement in tests instead of only having their fields poked directly.
///
/// Coordinates are in an arbitrary pixel-like space with y increasing
/// downward, matching ML Kit's image coordinates.
class PoseFixtures {
  static const double _defaultLikelihood = 0.95;

  static PoseLandmark landmark(
    PoseLandmarkType type,
    double x,
    double y, {
    double z = 0.0,
    double likelihood = _defaultLikelihood,
  }) {
    return PoseLandmark(
      type: type,
      x: x,
      y: y,
      z: z,
      likelihood: likelihood,
    );
  }

  static Pose fromLandmarks(List<PoseLandmark> landmarks) {
    return Pose(
      landmarks: {for (final lm in landmarks) lm.type: lm},
    );
  }

  /// A side-on squat pose whose hip-knee-ankle angle is [kneeAngle] degrees and
  /// whose shoulder-hip-knee (back) angle is [backAngle] degrees.
  ///
  /// The knee is the origin. The ankle is placed straight down from it and the
  /// hip is rotated away by [kneeAngle], so the measured joint angle comes out
  /// as requested. The shoulder is then placed relative to the hip to produce
  /// the requested back angle.
  /// [lateralSpread] separates the left and right landmarks horizontally.
  ///
  /// Zero puts them on top of each other, which is what a profile view looks
  /// like to the detector. A wide spread looks like someone facing the camera.
  /// Because both sides shift by the same amount, every within-side joint angle
  /// is unchanged — so the same movement can be replayed from either view.
  static Pose squat({
    required double kneeAngle,
    double backAngle = 175.0,
    double lateralSpread = 0.0,
    double likelihood = _defaultLikelihood,
  }) {
    const kneeX = 200.0;
    const kneeY = 300.0;
    const segment = 100.0;

    const ankle = Offset(kneeX, kneeY + segment);

    // Rotate the hip up-and-forward from the downward ankle direction.
    final kneeRad = _radians(kneeAngle);
    final hip = Offset(
      kneeX + segment * math.sin(kneeRad),
      kneeY + segment * math.cos(kneeRad),
    );

    // Direction hip->knee, rotated by the back angle, gives hip->shoulder.
    final hipToKnee = math.atan2(kneeY - hip.dy, kneeX - hip.dx);
    final shoulderDir = hipToKnee + _radians(backAngle);
    final shoulder = Offset(
      hip.dx + segment * math.cos(shoulderDir),
      hip.dy + segment * math.sin(shoulderDir),
    );

    final halfSpread = lateralSpread / 2;

    return fromLandmarks([
      for (final (side, dx) in [
        (_Side.left, -halfSpread),
        (_Side.right, halfSpread),
      ]) ...[
        landmark(side.shoulder, shoulder.dx + dx, shoulder.dy,
            likelihood: likelihood),
        landmark(side.hip, hip.dx + dx, hip.dy, likelihood: likelihood),
        landmark(side.knee, kneeX + dx, kneeY, likelihood: likelihood),
        landmark(side.ankle, ankle.dx + dx, ankle.dy, likelihood: likelihood),
      ],
    ]);
  }

  /// A side-on plank pose whose shoulder-hip-knee angle is [backAngle].
  ///
  /// When [sagging] is true the hip sits below the shoulder-knee midline
  /// (hips dropped); when false it sits above it (hips piked). At a straight
  /// [backAngle] of 180 the distinction is moot.
  static Pose plank({
    required double backAngle,
    bool sagging = true,
    double likelihood = _defaultLikelihood,
  }) {
    const hipX = 200.0;
    const hipY = 300.0;
    const segment = 100.0;

    const knee = Offset(hipX + segment, hipY);

    // Rotate the shoulder away from straight. Sagging puts the hip lowest on
    // screen, which means lifting both ends: shoulder goes up (smaller y).
    final deviation = 180.0 - backAngle;
    final rad = _radians(sagging ? 180.0 - deviation : 180.0 + deviation);
    final shoulder = Offset(
      hipX + segment * math.cos(rad),
      hipY - segment * math.sin(rad),
    );

    return fromLandmarks([
      for (final side in const [_Side.left, _Side.right]) ...[
        landmark(side.shoulder, shoulder.dx, shoulder.dy,
            likelihood: likelihood),
        landmark(side.hip, hipX, hipY, likelihood: likelihood),
        landmark(side.knee, knee.dx, knee.dy, likelihood: likelihood),
      ],
    ]);
  }

  /// A pushup pose whose shoulder-elbow-wrist angle is [elbowAngle] degrees.
  static Pose pushup({
    required double elbowAngle,
    double likelihood = _defaultLikelihood,
  }) {
    const elbowX = 200.0;
    const elbowY = 300.0;
    const segment = 100.0;

    const wrist = Offset(elbowX, elbowY + segment);

    final rad = _radians(elbowAngle);
    final shoulder = Offset(
      elbowX + segment * math.sin(rad),
      elbowY + segment * math.cos(rad),
    );

    return fromLandmarks([
      landmark(PoseLandmarkType.leftShoulder, shoulder.dx, shoulder.dy,
          likelihood: likelihood),
      landmark(PoseLandmarkType.leftElbow, elbowX, elbowY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.leftWrist, wrist.dx, wrist.dy,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightShoulder, shoulder.dx, shoulder.dy,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightElbow, elbowX, elbowY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightWrist, wrist.dx, wrist.dy,
          likelihood: likelihood),
    ]);
  }

  /// A front-on pose with the arms abducted to [armAngle] at the shoulder,
  /// measured hip-shoulder-elbow. Arms by the sides is near 0; overhead is
  /// near 180.
  ///
  /// Shoulder and hip widths are kept equal so the shoulder-to-hip vector is
  /// exactly vertical and the requested angle comes out precisely.
  static Pose jumpingJack({
    required double armAngle,
    double bodyWidth = 120,
    double torsoHeight = 160,
    double likelihood = _defaultLikelihood,
  }) {
    const centreX = 200.0;
    const shoulderY = 200.0;
    const armLength = 100.0;
    final hipY = shoulderY + torsoHeight;
    final half = bodyWidth / 2;

    final rad = _radians(armAngle);
    final dx = armLength * math.sin(rad);
    final dy = armLength * math.cos(rad);

    return fromLandmarks([
      landmark(PoseLandmarkType.leftShoulder, centreX - half, shoulderY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightShoulder, centreX + half, shoulderY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.leftHip, centreX - half, hipY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightHip, centreX + half, hipY,
          likelihood: likelihood),
      // Arms swing outward, away from the midline.
      landmark(PoseLandmarkType.leftElbow, centreX - half - dx,
          shoulderY + dy,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightElbow, centreX + half + dx,
          shoulderY + dy,
          likelihood: likelihood),
    ]);
  }

  /// A side-on pose whose shoulder-hip-ankle angle is [bodyAngle].
  static Pose sidePlank({
    required double bodyAngle,
    double likelihood = _defaultLikelihood,
  }) {
    const hipX = 200.0;
    const hipY = 300.0;
    const segment = 100.0;

    const ankle = Offset(hipX + segment, hipY);
    final rad = _radians(bodyAngle);
    final shoulder = Offset(
      hipX + segment * math.cos(rad),
      hipY - segment * math.sin(rad),
    );

    return fromLandmarks([
      for (final side in const [_Side.left, _Side.right]) ...[
        landmark(side.shoulder, shoulder.dx, shoulder.dy,
            likelihood: likelihood),
        landmark(side.hip, hipX, hipY, likelihood: likelihood),
        landmark(side.ankle, ankle.dx, ankle.dy, likelihood: likelihood),
      ],
    ]);
  }

  /// A bare torso: four landmarks positioned to give exact shoulder width,
  /// hip width and torso height, for orientation tests.
  static Pose torso({
    required double shoulderWidth,
    required double hipWidth,
    required double torsoHeight,
    double likelihood = _defaultLikelihood,
  }) {
    const centreX = 200.0;
    const shoulderY = 200.0;
    final hipY = shoulderY + torsoHeight;

    return fromLandmarks([
      landmark(PoseLandmarkType.leftShoulder, centreX - shoulderWidth / 2,
          shoulderY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightShoulder, centreX + shoulderWidth / 2,
          shoulderY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.leftHip, centreX - hipWidth / 2, hipY,
          likelihood: likelihood),
      landmark(PoseLandmarkType.rightHip, centreX + hipWidth / 2, hipY,
          likelihood: likelihood),
    ]);
  }

  /// An empty pose — nothing visible, so analyzers should bail out.
  static Pose empty() => fromLandmarks(const []);

  static double _radians(double degrees) => degrees * math.pi / 180.0;
}

class Offset {
  final double dx;
  final double dy;
  const Offset(this.dx, this.dy);
}

class _Side {
  final PoseLandmarkType shoulder;
  final PoseLandmarkType hip;
  final PoseLandmarkType knee;
  final PoseLandmarkType ankle;

  const _Side._(this.shoulder, this.hip, this.knee, this.ankle);

  static const left = _Side._(
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.leftAnkle,
  );

  static const right = _Side._(
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.rightAnkle,
  );
}
