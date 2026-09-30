import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/logic/pose_validity.dart';

import 'support/pose_fixtures.dart';
import 'support/recorded_pose_fixtures.dart';

const frame = Size(1080, 1600);

/// A full-body pose scaled to [scale] and placed at ([ox], [oy]).
Pose body({double scale = 1, double ox = 300, double oy = 300, double likelihood = 0.95}) {
  PoseLandmark at(PoseLandmarkType t, double x, double y) =>
      PoseFixtures.landmark(t, ox + x * scale, oy + y * scale, likelihood: likelihood);
  return PoseFixtures.fromLandmarks([
    at(PoseLandmarkType.leftShoulder, 0, 0),
    at(PoseLandmarkType.rightShoulder, 60, 0),
    at(PoseLandmarkType.leftElbow, -20, 150),
    at(PoseLandmarkType.rightElbow, 80, 150),
    at(PoseLandmarkType.leftWrist, -30, 290),
    at(PoseLandmarkType.rightWrist, 90, 290),
    at(PoseLandmarkType.leftHip, 10, 300),
    at(PoseLandmarkType.rightHip, 50, 300),
    at(PoseLandmarkType.leftKnee, 10, 550),
    at(PoseLandmarkType.rightKnee, 50, 550),
    at(PoseLandmarkType.leftAnkle, 10, 800),
    at(PoseLandmarkType.rightAnkle, 50, 800),
  ]);
}

void main() {
  test('a full-size athlete is accepted', () {
    expect(PoseValidator().accepts(body(), frame), isTrue);
  });

  test('a tiny skeleton (a barbell plate) is rejected', () {
    // The whole "body" fits in a few percent of the frame.
    expect(PoseValidator().accepts(body(scale: 0.04), frame), isFalse);
  });

  test('a small but real athlete far from the camera is accepted', () {
    expect(PoseValidator().accepts(body(scale: 0.35), frame), isTrue);
  });

  test('too few confident joints is rejected', () {
    expect(PoseValidator().accepts(body(likelihood: 0.2), frame), isFalse);
    expect(PoseValidator().accepts(PoseFixtures.empty(), frame), isFalse);
  });

  test('a sudden teleport is a glitch, but a lasting move is accepted', () {
    final v = PoseValidator();
    expect(v.accepts(body(ox: 100, oy: 200), frame), isTrue);
    // Jumps most of the way across the frame in one frame.
    final far = body(ox: 900, oy: 800);
    expect(v.accepts(far, frame), isFalse);
    // Still there five frames later: the athlete really has moved.
    for (var i = 0; i < 4; i++) {
      expect(v.accepts(far, frame), isFalse);
    }
    var accepted = false;
    for (var i = 0; i < 4; i++) {
      accepted = v.accepts(far, frame) || accepted;
    }
    expect(accepted, isTrue);
  });

  test('ordinary movement is never mistaken for a teleport', () {
    final v = PoseValidator();
    for (var i = 0; i < 100; i++) {
      // Walks 12 px a frame.
      expect(v.accepts(body(ox: 100 + i * 12.0, oy: 300), frame), isTrue, reason: 'frame $i');
    }
  });

  test('reset forgets where the athlete was', () {
    final v = PoseValidator();
    v.accepts(body(ox: 100, oy: 200), frame);
    v.reset();
    expect(v.accepts(body(ox: 900, oy: 800), frame), isTrue);
  });

  group('real footage: almost every frame of a real set is accepted', () {
    for (final name in [
      'live3_squat', 'live3_pushupSide', 'live3_pushupFront', 'live3_pushupFloor',
      'live3_lunge', 'live3_jumpingJack', 'live3_overheadPress', 'live3_situp',
      'live3_gluteBridge', 'live3_plank', 'live2_squat', 'live2_situp',
    ]) {
      test(name, () {
        final v = PoseValidator();
        final poses = RecordedPoseFixtures.loadSequence(name);
        final rejected = poses.where((p) => !v.accepts(p, frame)).length;
        expect(rejected / poses.length, lessThan(0.05),
            reason: '$rejected of ${poses.length} frames rejected');
      });
    }
  });
}
