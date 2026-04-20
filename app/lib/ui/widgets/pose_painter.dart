import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';
import '../../core/app_constants.dart';

class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    this.lastAngle,
    this.squatState,
    this.activeLandmarkTypes,
    this.isBusy = false,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
  final double? lastAngle;

  /// Current squat state used to conditionally colour the femur lines.
  final SquatState? squatState;
  final Set<PoseLandmarkType>? activeLandmarkTypes;

  /// When [isBusy] is true the painter skips repaints to avoid frame stacking.
  final bool isBusy;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.0
      ..color = AppColors.accentCyan;

    // Femur (hip → knee): Green during concentric drive, red otherwise.
    final femurPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.0
      ..color = squatState == SquatState.concentric
          ? AppColors.goodGreen
          : AppColors.badRed;

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
        canvas.drawCircle(_transform(landmark.x, landmark.y, size), 4, dotPaint);
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
      _transform(lm1.x, lm1.y, size),
      _transform(lm2.x, lm2.y, size),
      paint,
    );
  }

  Offset _transform(double x, double y, Size size) {
    double transformedX;
    double transformedY;

    // The imageSize is the size of the image processing by ML Kit
    // In portrait (90 or 270), width and height are swapped relative to the UI
    if (rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg) {
      transformedX = x * size.width / imageSize.height;
      transformedY = y * size.height / imageSize.width;
    } else {
      transformedX = x * size.width / imageSize.width;
      transformedY = y * size.height / imageSize.height;
    }

    // Handle mirrors and flips based on rotation
    if (rotation == InputImageRotation.rotation180deg) {
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
    // isBusy guard: skip repaint while a new frame is being analyzed to
    // prevent frame stacking and maintain high-speed UI responsiveness.
    if (isBusy) return false;
    return oldDelegate.poses != poses ||
        oldDelegate.lastAngle != lastAngle ||
        oldDelegate.squatState != squatState ||
        oldDelegate.activeLandmarkTypes != activeLandmarkTypes;
  }
}
