import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:form_analyzer/main.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

void main() {
  test('calculateJointAngle returns 180 degrees for a straight line', () {
    final angle = calculateJointAngle(
      const Offset(-1, 0),
      const Offset(0, 0),
      const Offset(1, 0),
    );
    expect(angle, closeTo(180, 0.001));
  });

  test('calculateJointAngle returns 90 degrees for right angle', () {
    final angle = calculateJointAngle(
      const Offset(0, 1),
      const Offset(0, 0),
      const Offset(1, 0),
    );
    expect(angle, closeTo(90, 0.001));
  });

  test('calculateJointAngle handles acute angles', () {
    final angle = calculateJointAngle(
      const Offset(0, 1),
      const Offset(0, 0),
      const Offset(1, 1),
    );
    expect(angle, greaterThan(0));
    expect(angle, lessThan(135));
  });

  group('calculateAngle with PoseLandmarks', () {
    test('returns 180 degrees for straight line configuration', () {
      final first = PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: 0,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      final second = PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: 0,
        y: 1,
        z: 0,
        likelihood: 1.0,
      );
      final third = PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: 0,
        y: 2,
        z: 0,
        likelihood: 1.0,
      );
      
      final angle = calculateAngle(first, second, third);
      expect(angle, closeTo(180, 0.1));
    });

    test('returns 90 degrees for right angle configuration', () {
      final first = PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: 0,
        y: 1,
        z: 0,
        likelihood: 1.0,
      );
      final second = PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: 0,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      final third = PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: 1,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      
      final angle = calculateAngle(first, second, third);
      expect(angle, closeTo(90, 0.1));
    });

    test('handles 3D coordinates correctly', () {
      final first = PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: 1,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      final second = PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: 0,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      final third = PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: 0,
        y: 0,
        z: 1,
        likelihood: 1.0,
      );
      
      final angle = calculateAngle(first, second, third);
      expect(angle, closeTo(90, 0.1));
    });

    test('returns valid angle for squat depth range', () {
      // Simulating a squat at ~70 degree knee angle
      final hip = PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: 0,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      final knee = PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: 0.5,
        y: 1,
        z: 0,
        likelihood: 1.0,
      );
      final ankle = PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: 0.8,
        y: 1.8,
        z: 0,
        likelihood: 1.0,
      );
      
      final angle = calculateAngle(hip, knee, ankle);
      expect(angle, greaterThan(0));
      expect(angle, lessThan(180));
    });

    test('handles zero magnitude vectors gracefully', () {
      final first = PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: 0,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      final second = PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: 0,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      final third = PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: 1,
        y: 0,
        z: 0,
        likelihood: 1.0,
      );
      
      final angle = calculateAngle(first, second, third);
      expect(angle, equals(0.0));
    });
  });
}
