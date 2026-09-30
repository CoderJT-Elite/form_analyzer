import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';
import '../../core/app_constants.dart';
import '../../logic/gravity_frame.dart';

class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    InputImageRotation? previewRotation,
    required this.lensDirection,
    this.lastAngle,
    this.squatState,
    this.activeLandmarkTypes,
  }) : previewRotation = previewRotation ?? rotation;

  final List<Pose> poses;
  final Size imageSize;
  /// The rotation the pose detector was given. Poses are reported in that
  /// frame, which follows the phone's physical orientation.
  final InputImageRotation rotation;

  /// The rotation the camera preview is drawn with (the sensor orientation: the
  /// UI is locked to portrait). Equal to [rotation] unless the phone is turned.
  final InputImageRotation previewRotation;
  final CameraLensDirection lensDirection;
  final double? lastAngle;

  /// Current squat state used to conditionally colour the femur lines.
  final SquatState? squatState;
  final Set<PoseLandmarkType>? activeLandmarkTypes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.0
      ..color = AppColors.accentCyan;

    // Femur (hip → knee): a squat-only state readout, green during the drive
    // up and red otherwise. For every other exercise there is no such state,
    // and a permanently red thigh just reads as "your legs are wrong".
    final femurPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = squatState == null ? 3.0 : 4.0
      ..color = squatState == null
          ? AppColors.accentCyan
          : (squatState == SquatState.concentric
              ? AppColors.goodGreen
              : AppColors.badRed);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    for (final pose in poses) {
      const skeleton = <(PoseLandmarkType, PoseLandmarkType)>[
        (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
        (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
        (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
        (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
        (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
        (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
        (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
        (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
        (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
        (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
      ];
      for (final connection in skeleton) {
        _drawConnection(canvas, pose, connection.$1, connection.$2, paint, size);
      }

      _drawConnection(canvas, pose, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, femurPaint, size);
      _drawConnection(canvas, pose, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, femurPaint, size);

      // Draw Landmarks
      pose.landmarks.forEach((type, landmark) {
        if (landmark.likelihood < 0.5) return;
        if (activeLandmarkTypes != null && !activeLandmarkTypes!.contains(type)) {
          return;
        }
        canvas.drawCircle(transformPoint(landmark.x, landmark.y, size), 4, dotPaint);
      });
    }
  }

  void _drawConnection(Canvas canvas, Pose pose, PoseLandmarkType start, PoseLandmarkType end, Paint paint, Size size) {
    final lm1 = pose.landmarks[start];
    final lm2 = pose.landmarks[end];
    if (lm1 == null || lm2 == null) return;
    if (lm1.likelihood < 0.5 || lm2.likelihood < 0.5) return;
    if (activeLandmarkTypes != null &&
        (!activeLandmarkTypes!.contains(start) || !activeLandmarkTypes!.contains(end))) {
      return;
    }

    canvas.drawLine(
      transformPoint(lm1.x, lm1.y, size),
      transformPoint(lm2.x, lm2.y, size),
      paint,
    );
  }

  /// Map a pose coordinate to widget coordinates.
  @visibleForTesting
  Offset transformPoint(double x, double y, Size size) {
    // Poses come back in the frame ML Kit was told to detect in; the preview is
    // drawn in the sensor's own portrait frame. Bring the point across first.
    final (px, py) = PoseCoordinates.toPreviewFrame(
      x: x,
      y: y,
      rawImage: imageSize,
      poseRotation: rotation,
      previewRotation: previewRotation,
    );

    double transformedX;
    double transformedY;

    // The imageSize is the size of the image processing by ML Kit
    // In portrait (90 or 270), width and height are swapped relative to the UI
    if (previewRotation == InputImageRotation.rotation90deg ||
        previewRotation == InputImageRotation.rotation270deg) {
      transformedX = px * size.width / imageSize.height;
      transformedY = py * size.height / imageSize.width;
    } else {
      transformedX = px * size.width / imageSize.width;
      transformedY = py * size.height / imageSize.height;
    }

    // Handle mirrors and flips based on rotation
    if (previewRotation == InputImageRotation.rotation180deg) {
      transformedX = size.width - transformedX;
      transformedY = size.height - transformedY;
    }

    if (lensDirection == CameraLensDirection.front) {
      transformedX = size.width - transformedX;
    }

    return Offset(transformedX, transformedY);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    // A new pose list means new landmarks to draw. There used to be an
    // `isBusy` short-circuit here that returned false while a frame was in
    // flight, which suppressed repaints carrying fresh data and left the
    // skeleton visibly trailing the athlete.
    return oldDelegate.poses != poses ||
        oldDelegate.rotation != rotation ||
        oldDelegate.lastAngle != lastAngle ||
        oldDelegate.squatState != squatState ||
        oldDelegate.activeLandmarkTypes != activeLandmarkTypes;
  }
}
