import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/app_constants.dart';

class MathUtils {
  static double calculateJointAngleFromOffsets(Offset a, Offset b, Offset c) {
    final ba = Offset(a.dx - b.dx, a.dy - b.dy);
    final bc = Offset(c.dx - b.dx, c.dy - b.dy);
    final dotProduct = (ba.dx * bc.dx) + (ba.dy * bc.dy);
    final baDistanceSquared = (ba.dx * ba.dx) + (ba.dy * ba.dy);
    final bcDistanceSquared = (bc.dx * bc.dx) + (bc.dy * bc.dy);
    final magnitude = math.max(
        math.sqrt(baDistanceSquared * bcDistanceSquared),
        AppConstants.minMagnitude);
    final cosine = (dotProduct / magnitude).clamp(-1.0, 1.0);
    final angle = math.acos(cosine) * 180 / math.pi;
    return angle;
  }

  static double calculateJointAngle(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
    if (a == null || b == null || c == null) return 0.0;

    final dx1 = a.x - b.x;
    final dy1 = a.y - b.y;
    final dz1 = a.z - b.z;

    final dx2 = c.x - b.x;
    final dy2 = c.y - b.y;
    final dz2 = c.z - b.z;

    final mag1 = math.sqrt(dx1 * dx1 + dy1 * dy1 + dz1 * dz1);
    final mag2 = math.sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2);

    if (mag1 < AppConstants.minMagnitude || mag2 < AppConstants.minMagnitude) return 0.0;

    final dotProduct = dx1 * dx2 + dy1 * dy2 + dz1 * dz2;
    final cosine = (dotProduct / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }
}
