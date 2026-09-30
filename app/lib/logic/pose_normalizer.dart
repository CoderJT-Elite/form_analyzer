import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'gravity_frame.dart';

/// Re-expresses a pose so that +y points along gravity.
///
/// Analyzers are written as though the phone were upright ("hips above the
/// floor line", "torso within 25 degrees of vertical"). Rotating the poses once,
/// here, means every analyzer gets that for free instead of each growing its
/// own idea of which way is down. It is a proper rotation, so angles,
/// distances and left/right are all unchanged.
///
/// Depth (z) is untouched: the in-plane rotation does not affect it.
Pose normalizePose(Pose pose, GravityFrame gravity) {
  if (gravity.isUpright) return pose;
  final landmarks = <PoseLandmarkType, PoseLandmark>{};
  pose.landmarks.forEach((type, landmark) {
    final (u, v) = gravity.toGravityAligned(landmark.x, landmark.y);
    landmarks[type] = PoseLandmark(
      type: type,
      x: u,
      y: v,
      z: landmark.z,
      likelihood: landmark.likelihood,
    );
  });
  return Pose(landmarks: landmarks);
}
