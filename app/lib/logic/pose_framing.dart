import 'dart:ui';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/app_constants.dart';

/// Whether enough of the athlete is visible and comfortably inside the
/// camera frame to actually be tracked -- distinct from [PoseOrientation]
/// (in `pose_orientation.dart`), which only classifies front-on vs side-on
/// and says nothing about distance or cropping.
///
/// A phone held too close crops limbs out of frame before ML Kit's
/// per-landmark confidence necessarily drops enough to be caught by
/// [AppConstants.visibilityThreshold] alone -- a landmark can sit right at
/// the frame edge and still read as reasonably confident. Checking
/// proximity to the edge directly is a more direct signal for "you're too
/// close" than confidence alone.
class PoseFraming {
  const PoseFraming._();

  /// Landmarks within this fraction of the image's width/height from any
  /// edge are treated as likely cropped, even if still reported with
  /// reasonable confidence.
  static const double edgeMarginFraction = 0.03;

  /// At least this fraction of the exercise's required joints must be
  /// visible and away from the frame edge to count as "in frame".
  static const double minVisibleFraction = 0.8;

  /// Minimum landmark confidence required for the framing presence check.
  /// Decoupled from [AppConstants.visibilityThreshold] (0.7), which is tuned
  /// for precise joint-angle math during rep counting. For framing, 0.5
  /// matches the pose detector's presence threshold and avoids false
  /// "step back" cues when well-framed athletes experience minor tracking noise.
  static const double framingVisibilityThreshold = 0.5;

  /// Maps each bilateral landmark to a side-agnostic joint key so that one
  /// occluded side doesn't count against framing -- self-occlusion of the
  /// far side is normal and expected when filming side-on or mid-rep (e.g.
  /// the trailing knee in a side-on squat, or the far elbow in a push-up),
  /// the same bilateral-extremum reasoning already applied when analyzers
  /// pick a rep angle (see SquatAnalyzer, OverheadPressAnalyzer, etc. in
  /// exercise_analyzer.dart). A landmark with no entry here is its own group.
  static const Map<PoseLandmarkType, String> _jointGroup = {
    PoseLandmarkType.leftShoulder: 'shoulder',
    PoseLandmarkType.rightShoulder: 'shoulder',
    PoseLandmarkType.leftElbow: 'elbow',
    PoseLandmarkType.rightElbow: 'elbow',
    PoseLandmarkType.leftWrist: 'wrist',
    PoseLandmarkType.rightWrist: 'wrist',
    PoseLandmarkType.leftHip: 'hip',
    PoseLandmarkType.rightHip: 'hip',
    PoseLandmarkType.leftKnee: 'knee',
    PoseLandmarkType.rightKnee: 'knee',
    PoseLandmarkType.leftAnkle: 'ankle',
    PoseLandmarkType.rightAnkle: 'ankle',
  };

  /// [imageSize] is the analyzed frame's dimensions in the same pixel space
  /// as the landmark coordinates. When unavailable (e.g. camera not yet
  /// initialized), this doesn't block -- there's nothing to check against.
  static bool isInFrame({
    required Pose pose,
    required Set<PoseLandmarkType> requiredLandmarks,
    required Size? imageSize,
    double minLikelihood = framingVisibilityThreshold,
  }) {
    if (requiredLandmarks.isEmpty) return true;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return true;
    }

    final marginX = imageSize.width * edgeMarginFraction;
    final marginY = imageSize.height * edgeMarginFraction;

    bool isVisibleAndFramed(PoseLandmarkType type) {
      final landmark = pose.landmarks[type];
      if (landmark == null || landmark.likelihood < minLikelihood) {
        return false;
      }
      final nearEdge = landmark.x < marginX ||
          landmark.x > imageSize.width - marginX ||
          landmark.y < marginY ||
          landmark.y > imageSize.height - marginY;
      return !nearEdge;
    }

    final joints = <String, List<PoseLandmarkType>>{};
    for (final type in requiredLandmarks) {
      final key = _jointGroup[type] ?? type.toString();
      joints.putIfAbsent(key, () => []).add(type);
    }

    final visibleJointCount = joints.values
        .where((types) => types.any(isVisibleAndFramed))
        .length;

    return visibleJointCount / joints.length >= minVisibleFraction;
  }
}
