import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/logic/gravity_frame.dart';
import 'package:form_analyzer/logic/hip_line.dart';
import 'package:form_analyzer/logic/pose_normalizer.dart';

import 'support/pose_fixtures.dart';

PoseLandmark lm(PoseLandmarkType t, double x, double y) =>
    PoseFixtures.landmark(t, x, y);

PoseLandmark shoulder(double x, double y) => lm(PoseLandmarkType.leftShoulder, x, y);
PoseLandmark hip(double x, double y) => lm(PoseLandmarkType.leftHip, x, y);
PoseLandmark knee(double x, double y) => lm(PoseLandmarkType.leftKnee, x, y);

/// Feed [frames] identical frames and return the final verdict.
HipVerdict settle(
  HipLineMeter judge,
  PoseLandmark s,
  PoseLandmark h,
  PoseLandmark k, {
  int frames = 12,
}) {
  var v = judge.verdict;
  for (var i = 0; i < frames; i++) {
    v = judge.update(s, h, k);
  }
  return v;
}

void main() {
  group('offsetRatio', () {
    test('a hip below a horizontal line is positive (sagging), above is negative', () {
      expect(HipLineMeter.offsetRatio(shoulder(0, 0), hip(100, 30), knee(200, 0)), closeTo(0.15, 1e-9));
      expect(HipLineMeter.offsetRatio(shoulder(0, 0), hip(100, -30), knee(200, 0)), closeTo(-0.15, 1e-9));
    });

    test('the answer does not depend on which way the athlete faces', () {
      // Mirror the body left-to-right: shoulder on the right, knee on the left.
      expect(HipLineMeter.offsetRatio(shoulder(200, 0), hip(100, 30), knee(0, 0)), closeTo(0.15, 1e-9));
      expect(HipLineMeter.offsetRatio(shoulder(200, 0), hip(100, -30), knee(0, 0)), closeTo(-0.15, 1e-9));
    });

    test('works on a sloped body line (an incline push-up)', () {
      // Line from (0,0) to (200,60): at x=100 it is at y=30.
      expect(HipLineMeter.offsetRatio(shoulder(0, 0), hip(100, 50), knee(200, 60))!, greaterThan(0));
      expect(HipLineMeter.offsetRatio(shoulder(0, 0), hip(100, 10), knee(200, 60))!, lessThan(0));
    });

    test('a degenerate line gives no answer', () {
      expect(HipLineMeter.offsetRatio(shoulder(5, 5), hip(9, 9), knee(5, 5)), isNull);
    });
  });

  group('HipLineMeter', () {
    test('calls a sag and a pike', () {
      expect(settle(HipLineMeter(), shoulder(0, 0), hip(100, 30), knee(200, 0)), HipVerdict.sagging);
      expect(settle(HipLineMeter(), shoulder(0, 0), hip(100, -40), knee(200, 0)), HipVerdict.piked);
    });

    test('a straight line stays straight', () {
      expect(settle(HipLineMeter(), shoulder(0, 0), hip(100, 1), knee(200, 0)), HipVerdict.straight);
    });

    test('a noisy frame does not flip a standing verdict', () {
      final judge = HipLineMeter();
      settle(judge, shoulder(0, 0), hip(100, 30), knee(200, 0));
      // One frame that looks piked, then back to sagging.
      judge.update(shoulder(0, 0), hip(100, -40), knee(200, 0));
      expect(judge.verdict, HipVerdict.sagging);
      settle(judge, shoulder(0, 0), hip(100, 30), knee(200, 0), frames: 3);
      expect(judge.verdict, HipVerdict.sagging);
    });

    test('a sustained change of posture does reverse it', () {
      final judge = HipLineMeter();
      settle(judge, shoulder(0, 0), hip(100, 30), knee(200, 0));
      expect(settle(judge, shoulder(0, 0), hip(100, -40), knee(200, 0), frames: 20), HipVerdict.piked);
    });

    test('never alternates on a jittery plank (live test #3)', () {
      final judge = HipLineMeter();
      final rng = math.Random(7);
      final seen = <HipVerdict>{};
      for (var i = 0; i < 300; i++) {
        // A real 8% sag with +-4% frame-to-frame noise.
        final y = 16 + (rng.nextDouble() - 0.5) * 16;
        seen.add(judge.update(shoulder(0, 0), hip(100, y), knee(200, 0)));
      }
      expect(seen, isNot(contains(HipVerdict.piked)));
    });

    test('a nearly vertical body (leaning on a wall) is not judged', () {
      final judge = HipLineMeter();
      // Shoulder above, knee below, hip barely off the line.
      expect(settle(judge, shoulder(0, 0), hip(20, 260), knee(40, 520)), HipVerdict.unjudgeable);
    });

    test('a steep-but-floor incline is still judged', () {
      // 25 degrees from horizontal.
      final dx = 200 * math.cos(25 * math.pi / 180);
      final dy = 200 * math.sin(25 * math.pi / 180);
      final judge = HipLineMeter();
      final v = settle(judge, shoulder(0, 0), hip(dx / 2, dy / 2 + 25), knee(dx, dy));
      expect(v, HipVerdict.sagging);
    });

    test('the line is called broken, and which way, from the same number', () {
      // Live test #5 said "hips too high" to a sagging plank because the
      // "broken" decision and the direction came from different measurements.
      // Whatever the (noisy) input, a sag verdict must have a positive offset
      // and a pike verdict a negative one.
      final meter = HipLineMeter();
      final rng = math.Random(3);
      var y = 0.0;
      for (var i = 0; i < 2000; i++) {
        // A slow random walk from pike through straight to sag and back.
        y = (y + (rng.nextDouble() - 0.5) * 12).clamp(-45.0, 45.0);
        final verdict = meter.update(shoulder(0, 0), hip(100, y), knee(200, 0));
        final offset = meter.offset;
        if (offset == null) continue;
        if (verdict == HipVerdict.sagging) expect(offset, greaterThan(0));
        if (verdict == HipVerdict.piked) expect(offset, lessThan(0));
      }
    });

    test('a sag that is straightening is not called straight until it clears the band', () {
      final meter = HipLineMeter();
      settle(meter, shoulder(0, 0), hip(100, 30), knee(200, 0)); // 0.15: sagging
      // 0.085 is inside the break/clear band: the verdict stands rather than
      // flickering at the boundary.
      expect(settle(meter, shoulder(0, 0), hip(100, 17), knee(200, 0)), HipVerdict.sagging);
      expect(settle(meter, shoulder(0, 0), hip(100, 5), knee(200, 0)), HipVerdict.straight);
    });

    test('reset forgets the verdict', () {
      final judge = HipLineMeter();
      settle(judge, shoulder(0, 0), hip(100, 30), knee(200, 0));
      judge.reset();
      expect(judge.verdict, HipVerdict.straight);
    });
  });

  group('through the gravity normalizer: the phone can be turned any way', () {
    // A plank built upright, then rotated by [degrees] as if the phone were
    // turned, with gravity reported in the turned frame.
    HipVerdict verdictFor(double degrees, double hipDrop) {
      final t = degrees * math.pi / 180;
      final c = math.cos(t), s = math.sin(t);
      PoseLandmark rotated(PoseLandmarkType type, double x, double y) =>
          lm(type, c * x - s * y, s * x + c * y);
      final pose = PoseFixtures.fromLandmarks([
        rotated(PoseLandmarkType.leftShoulder, 0, 0),
        rotated(PoseLandmarkType.leftHip, 100, hipDrop),
        rotated(PoseLandmarkType.leftKnee, 200, 0),
      ]);
      // Gravity was (0, 1) upright; the same rotation carries it here.
      final level = normalizePose(pose, GravityFrame(-s, c));
      return settle(
        HipLineMeter(),
        level.landmarks[PoseLandmarkType.leftShoulder]!,
        level.landmarks[PoseLandmarkType.leftHip]!,
        level.landmarks[PoseLandmarkType.leftKnee]!,
      );
    }

    for (final degrees in [0.0, 90.0, 180.0, 270.0, 33.0, -20.0]) {
      test('rotated $degrees degrees: same verdicts', () {
        expect(verdictFor(degrees, 30), HipVerdict.sagging);
        expect(verdictFor(degrees, -40), HipVerdict.piked);
      });
    }
  });
}
