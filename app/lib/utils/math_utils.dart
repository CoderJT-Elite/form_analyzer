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

class ExponentialSmoothingFilter {
  ExponentialSmoothingFilter({required this.alpha}) : assert(alpha > 0 && alpha <= 1);

  final double alpha;
  double? _state;

  double add(double value) {
    _state = _state == null ? value : (alpha * value) + ((1 - alpha) * _state!);
    return _state!;
  }

  void reset() => _state = null;
}

class SmoothedLandmark {
  const SmoothedLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });

  final double x;
  final double y;
  final double z;
  final double likelihood;
}

class LandmarkSmoother {
  LandmarkSmoother({this.alpha = AppConstants.landmarkSmoothingAlpha});

  final double alpha;
  final Map<String, SmoothedLandmark> _cache = {};

  SmoothedLandmark smooth({
    required String key,
    required double x,
    required double y,
    required double z,
    required double likelihood,
  }) {
    final previous = _cache[key];
    if (previous == null) {
      final initial = SmoothedLandmark(x: x, y: y, z: z, likelihood: likelihood);
      _cache[key] = initial;
      return initial;
    }

    final next = SmoothedLandmark(
      x: (alpha * x) + ((1 - alpha) * previous.x),
      y: (alpha * y) + ((1 - alpha) * previous.y),
      z: (alpha * z) + ((1 - alpha) * previous.z),
      likelihood: (alpha * likelihood) + ((1 - alpha) * previous.likelihood),
    );
    _cache[key] = next;
    return next;
  }

  void reset() => _cache.clear();
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
    return calculateAngle(a, b, c);
  }

  static double calculateAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    return calculateAngleFromCoordinates(
      ax: a.x,
      ay: a.y,
      az: a.z,
      bx: b.x,
      by: b.y,
      bz: b.z,
      cx: c.x,
      cy: c.y,
      cz: c.z,
    );
  }

  static double calculateAngleFromSmoothed(
    SmoothedLandmark a,
    SmoothedLandmark b,
    SmoothedLandmark c,
  ) {
    return calculateAngleFromCoordinates(
      ax: a.x,
      ay: a.y,
      az: a.z,
      bx: b.x,
      by: b.y,
      bz: b.z,
      cx: c.x,
      cy: c.y,
      cz: c.z,
    );
  }

  static double calculateAngleFromCoordinates({
    required double ax,
    required double ay,
    required double az,
    required double bx,
    required double by,
    required double bz,
    required double cx,
    required double cy,
    required double cz,
  }) {
    final v1x = ax - bx;
    final v1y = ay - by;
    final v1z = az - bz;
    final v2x = cx - bx;
    final v2y = cy - by;
    final v2z = cz - bz;

    final hasReliableZ = _hasReliableZCoordinates(az: az, bz: bz, cz: cz);

    final mag1 = hasReliableZ
        ? math.sqrt((v1x * v1x) + (v1y * v1y) + (v1z * v1z))
        : math.sqrt((v1x * v1x) + (v1y * v1y));
    final mag2 = hasReliableZ
        ? math.sqrt((v2x * v2x) + (v2y * v2y) + (v2z * v2z))
        : math.sqrt((v2x * v2x) + (v2y * v2y));

    if (mag1 < AppConstants.minMagnitude || mag2 < AppConstants.minMagnitude) {
      return 0.0;
    }

    final dotProduct =
        hasReliableZ ? (v1x * v2x) + (v1y * v2y) + (v1z * v2z) : (v1x * v2x) + (v1y * v2y);
    final cosine = (dotProduct / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }

  static bool _hasReliableZCoordinates({
    required double az,
    required double bz,
    required double cz,
  }) {
    final allFinite = az.isFinite && bz.isFinite && cz.isFinite;
    final effectivelyFlat =
        az.abs() < AppConstants.minMagnitude &&
        bz.abs() < AppConstants.minMagnitude &&
        cz.abs() < AppConstants.minMagnitude;
    return allFinite && !effectivelyFlat;
  }
}
