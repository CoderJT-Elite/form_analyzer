import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/app_colors.dart';

class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    this.lastAngle,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
  final double? lastAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.0
      ..color = AppColors.accentCyan;

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    for (final pose in poses) {
      // Draw Connections
      pose.landmarks.forEach((type, landmark) {
        _drawConnection(canvas, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, paint, size);
        
        // Legs
        _drawConnection(canvas, pose, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, paint, size);

        // Arms
        _drawConnection(canvas, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, paint, size);
        _drawConnection(canvas, pose, PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, paint, size);
      });

      // Draw Landmarks
      pose.landmarks.forEach((type, landmark) {
        if (landmark.likelihood < 0.5) return;
        canvas.drawCircle(_transform(landmark.x, landmark.y, size), 4, dotPaint);
      });
    }
  }

  void _drawConnection(Canvas canvas, Pose pose, PoseLandmarkType start, PoseLandmarkType end, Paint paint, Size size) {
    final lm1 = pose.landmarks[start];
    final lm2 = pose.landmarks[end];
    if (lm1 == null || lm2 == null) return;
    if (lm1.likelihood < 0.5 || lm2.likelihood < 0.5) return;

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
    return oldDelegate.poses != poses || oldDelegate.lastAngle != lastAngle;
  }
}
