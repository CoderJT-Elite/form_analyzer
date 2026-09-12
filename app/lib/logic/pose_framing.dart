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

  /// At least this fraction of the exercise's required landmarks must be
  /// both visible and away from the frame edge to count as "in frame".
  static const double minVisibleFraction = 0.8;

  /// [imageSize] is the analyzed frame's dimensions in the same pixel space
  /// as the landmark coordinates. When unavailable (e.g. camera not yet
  /// initialized), this doesn't block -- there's nothing to check against.
  static bool isInFrame({
    required Pose pose,
    required Set<PoseLandmarkType> requiredLandmarks,
    required Size? imageSize,
  }) {
    if (requiredLandmarks.isEmpty) return true;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return true;
    }

    final marginX = imageSize.width * edgeMarginFraction;
    final marginY = imageSize.height * edgeMarginFraction;

    var visibleCount = 0;
    for (final type in requiredLandmarks) {
      final landmark = pose.landmarks[type];
      if (landmark == null ||
          landmark.likelihood < AppConstants.visibilityThreshold) {
        continue;
      }
      final nearEdge = landmark.x < marginX ||
          landmark.x > imageSize.width - marginX ||
          landmark.y < marginY ||
          landmark.y > imageSize.height - marginY;
      if (!nearEdge) visibleCount++;
    }

    return visibleCount / requiredLandmarks.length >= minVisibleFraction;
  }
}
