import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/app_constants.dart';

/// A simple moving-average filter that smooths a stream of values.
class MovingAverageFilter {
  final int windowSize;
  final List<double> _buffer = [];

  MovingAverageFilter({this.windowSize = 5});

  /// Add [value] to the buffer and return the current average.
  double add(double value) {
    _buffer.add(value);
    if (_buffer.length > windowSize) _buffer.removeAt(0);
    return _buffer.reduce((a, b) => a + b) / _buffer.length;
  }

  void reset() => _buffer.clear();
}

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

  /// Calculates the interior angle at point [b] using the **Law of Cosines**
  /// with full 3D coordinates (x, y, z).
  ///
  /// For the triangle formed by [a], [b], [c]:
  ///   cos(B) = (|AB|² + |BC|² − |AC|²) / (2·|AB|·|BC|)
  static double calculateAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final ab = math.sqrt(
      math.pow(a.x - b.x, 2) +
      math.pow(a.y - b.y, 2) +
      math.pow(a.z - b.z, 2),
    );
    final bc = math.sqrt(
      math.pow(b.x - c.x, 2) +
      math.pow(b.y - c.y, 2) +
      math.pow(b.z - c.z, 2),
    );
    final ac = math.sqrt(
      math.pow(a.x - c.x, 2) +
      math.pow(a.y - c.y, 2) +
      math.pow(a.z - c.z, 2),
    );

    if (ab < AppConstants.minMagnitude || bc < AppConstants.minMagnitude) {
      return 0.0;
    }

    // Law of Cosines: cos(B) = (ab² + bc² − ac²) / (2·ab·bc)
    final cosB = ((ab * ab + bc * bc - ac * ac) / (2 * ab * bc)).clamp(-1.0, 1.0);
    return math.acos(cosB) * 180 / math.pi;
  }
}
