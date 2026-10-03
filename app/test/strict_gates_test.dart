import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'support/pose_fixtures.dart';
import 'support/test_clock.dart';

/// The rules for what counts, on synthetic poses, independent of any footage.
///
/// Live test #5 showed an app that counted nearly everything. Each test below is
/// a way a rep can be bad, and what the app must do about it: count it with a
/// lower score, turn it down and say why, or ignore it as not an attempt.
class Feed {
  Feed(this.analyzer, this.clock);

  final ExerciseAnalyzer analyzer;
  final ManualClock clock;

  void frame(Pose pose, {int ms = 66}) {
    clock.advance(Duration(milliseconds: ms));
    analyzer.processPose(pose);
  }

  void hold(Pose pose, int frames) {
    for (var i = 0; i < frames; i++) {
      frame(pose);
    }
  }

  /// Smoothly from [from] to [to] in [steps] frames, building each pose with [build].
  void sweep(Pose Function(double) build, double from, double to, {int steps = 12}) {
    for (var i = 0; i <= steps; i++) {
      frame(build(from + (to - from) * i / steps));
    }
  }
}

class Outcome {
  final counted = <int>[];
  final noReps = <String>[];
  final spoken = <String?>[];
}

(Feed, Outcome) setup<T extends ExerciseAnalyzer>(T Function(DateTime Function()) make) {
  final clock = ManualClock();
  final analyzer = make(clock.call);
  final outcome = Outcome();
  analyzer.onRep = outcome.counted.add;
  analyzer.onNoRep = (reason, spoken) {
    outcome.noReps.add(reason);
    outcome.spoken.add(spoken);
  };
  return (Feed(analyzer, clock), outcome);
}

void main() {
  group('squat', () {
    Pose squatAt(double knee, {double lean = 0}) => PoseFixtures.squat(kneeAngle: knee, forwardLean: lean);

    void rep(Feed f, double bottom, {double lean = 0, double speed = 14}) {
      f.hold(squatAt(175), 6);
      f.sweep((k) => squatAt(k, lean: lean), 175, bottom, steps: speed.round());
      f.hold(squatAt(bottom, lean: lean), 3);
      f.sweep((k) => squatAt(k, lean: lean), bottom, 175, steps: speed.round());
      f.hold(squatAt(175), 6);
    }

    test('a full-depth squat counts, cleanly', () {
      final (f, out) = setup((c) => SquatAnalyzer(clock: c));
      rep(f, 80);
      expect(out.counted, [1]);
      expect(f.analyzer.repScores.single, 1.0);
      expect(out.noReps, isEmpty);
    });

    test('a squat that stops just short of parallel counts but is scored short', () {
      final (f, out) = setup((c) => SquatAnalyzer(clock: c));
      rep(f, 110);
      expect(out.counted, [1]);
      expect(f.analyzer.allRepIssues.single, contains('Insufficient Depth'));
      expect(f.analyzer.repScores.single, lessThan(1.0));
    });

    test('a squat well above parallel is turned down, and the athlete is told', () {
      final (f, out) = setup((c) => SquatAnalyzer(clock: c));
      rep(f, 120);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['not deep enough']);
      // The "a little deeper" cue was already said during the rep, so the verdict
      // is just "No rep" (with no cue it would say why).
      expect(out.spoken.single, startsWith('No rep'));
      expect(f.analyzer.noRepRecords.single.counted, isFalse);
    });

    test('a small bend is not an attempt at all: no verdict, no noise', () {
      final (f, out) = setup((c) => SquatAnalyzer(clock: c));
      rep(f, 135);
      expect(out.counted, isEmpty);
      expect(out.noReps, isEmpty);
      expect(f.analyzer.ignoredAttempts, 1);
    });

    test('folded over at the bottom is a hinge, not a squat', () {
      final (f, out) = setup((c) => SquatAnalyzer(clock: c));
      rep(f, 90, lean: 75);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['chest up, sit back instead of bending over']);
    });

    test('pulsing at the bottom does not count: each bounce is a no-rep, the finished rep counts', () {
      final (f, out) = setup((c) => SquatAnalyzer(clock: c));
      f.hold(squatAt(175), 6);
      f.sweep(squatAt, 175, 85); // down
      f.sweep(squatAt, 85, 125); // up a little...
      f.hold(squatAt(125), 6);
      f.sweep(squatAt, 125, 85); // ...and down again, without standing
      f.sweep(squatAt, 85, 175); // now all the way up
      f.hold(squatAt(175), 6);

      expect(out.noReps, ['stand all the way up']);
      expect(out.counted, [1], reason: 'only the rep that finished standing');
    });

    test('one noisy frame cannot make a shallow squat deep', () {
      final (f, out) = setup((c) => SquatAnalyzer(clock: c));
      f.hold(squatAt(175), 6);
      f.sweep(squatAt, 175, 125); // a shallow squat...
      f.frame(squatAt(70)); // ...with one flipped-landmark frame at 70 degrees
      f.sweep(squatAt, 125, 175);
      f.hold(squatAt(175), 6);
      expect(out.counted, isEmpty, reason: 'a median of three frames, not one');
    });

    test('a faster or slower squat is judged the same', () {
      for (final steps in [6, 14, 30]) {
        final (f, out) = setup((c) => SquatAnalyzer(clock: c));
        rep(f, 80, speed: steps.toDouble());
        expect(out.counted, [1], reason: '$steps frames each way');
      }
    });
  });

  group('push-up', () {
    /// A side-on push-up body: elbow bent to [elbow], hips [hipOffset] of body
    /// length below (positive) or above the shoulder-ankle line.
    Pose body(double elbow, {double hipOffset = 0.0, bool knees = false}) {
      const elbowX = 200.0, elbowY = 300.0, seg = 100.0;
      final rad = elbow * math.pi / 180;
      final shoulderX = elbowX + seg * math.sin(rad);
      final shoulderY = elbowY + seg * math.cos(rad);
      const length = 400.0;
      final ankleX = shoulderX + length;
      final hipX = shoulderX + length / 2;
      final hipY = shoulderY + hipOffset * length;
      // Knees on the floor: the shin folds back behind the hip.
      final kneeX = knees ? hipX + 60 : hipX + length / 4;
      final kneeY = knees ? shoulderY + 90 : shoulderY + hipOffset * length / 2;
      final ankleY = knees ? shoulderY + 20 : shoulderY;
      return PoseFixtures.fromLandmarks([
        for (final side in const ['left', 'right']) ...[
          PoseFixtures.landmark(side == 'left' ? PoseLandmarkType.leftShoulder : PoseLandmarkType.rightShoulder, shoulderX, shoulderY),
          PoseFixtures.landmark(side == 'left' ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow, elbowX, elbowY),
          PoseFixtures.landmark(side == 'left' ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist, elbowX, elbowY + seg),
          PoseFixtures.landmark(side == 'left' ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip, hipX, hipY),
          PoseFixtures.landmark(side == 'left' ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee, kneeX, kneeY),
          PoseFixtures.landmark(side == 'left' ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle, ankleX, ankleY),
        ],
      ]);
    }

    void rep(Feed f, {double bottom = 70, double top = 175, double hips = 0, bool knees = false, int steps = 14}) {
      f.hold(body(top, hipOffset: hips, knees: knees), 8);
      f.sweep((e) => body(e, hipOffset: hips, knees: knees), top, bottom, steps: steps);
      f.sweep((e) => body(e, hipOffset: hips, knees: knees), bottom, top, steps: steps);
      f.hold(body(top, hipOffset: hips, knees: knees), 8);
    }

    test('a straight-body push-up to full depth and lockout counts, cleanly', () {
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      rep(f);
      expect(out.counted, [1]);
      expect(f.analyzer.repScores.single, 1.0);
    });

    test('sagging hips for the whole rep: no rep, and it says why', () {
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      rep(f, hips: 0.16);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['hips sagged']);
    });

    test('hips that rise (a pike) for the whole rep: no rep', () {
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      rep(f, hips: -0.2);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['hips too high']);
    });

    test('knees on the floor: no rep', () {
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      rep(f, knees: true);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['knees on the floor']);
    });

    test('sag at the bottom that straightens at the top is no longer forgiven', () {
      // The old code erased hip flags whenever the back straightened at the top
      // of the rep, so a rep that sagged all the way up counted clean.
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      f.hold(body(175), 8);
      f.sweep((e) => body(e, hipOffset: 0.16), 175, 70);
      f.sweep((e) => body(e, hipOffset: 0.16), 70, 160);
      f.sweep((e) => body(e, hipOffset: 0.0), 160, 175, steps: 3); // straightens at the very top
      f.hold(body(175), 8);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['hips sagged']);
    });

    test('a sag in a small part of the rep costs score but does not turn it down', () {
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      f.hold(body(175), 8);
      f.sweep((e) => body(e), 175, 70);
      f.sweep((e) => body(e, hipOffset: 0.16), 70, 100, steps: 5); // a few frames of sag
      f.sweep((e) => body(e), 100, 175);
      f.hold(body(175), 8);
      expect(out.counted, [1]);
      expect(out.noReps, isEmpty);
    });

    test('a half rep that never locks out is turned down', () {
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      f.hold(body(175), 8);
      f.sweep((e) => body(e), 175, 70, steps: 16);
      f.sweep((e) => body(e), 70, 120, steps: 16); // stops at 120...
      f.hold(body(120), 6);
      f.sweep((e) => body(e), 120, 70, steps: 16); // ...and goes down again
      f.sweep((e) => body(e), 70, 175, steps: 16);
      f.hold(body(175), 8);
      expect(out.noReps, ['lock your arms out at the top']);
      expect(out.counted, [1], reason: 'the rep that did finish');
    });

    test('landmark flicker faster than anyone can push up is not a rep', () {
      final (f, out) = setup((c) => PushupAnalyzer(clock: c));
      f.hold(body(175), 8);
      for (var i = 0; i < 6; i++) {
        f.frame(body(90), ms: 40);
        f.frame(body(170), ms: 40);
      }
      f.hold(body(175), 8);
      expect(out.counted, isEmpty);
    });
  });

  group('lunge', () {
    Pose legs(double knee) => PoseFixtures.squat(kneeAngle: knee);

    void rep(Feed f, double bottom) {
      f.hold(legs(175), 6);
      f.sweep(legs, 175, bottom);
      f.hold(legs(bottom), 3);
      f.sweep(legs, bottom, 175);
      f.hold(legs(175), 6);
    }

    test('a deep lunge counts, and the athlete is allowed to say "good depth"', () {
      final (f, out) = setup((c) => LungeAnalyzer(clock: c));
      rep(f, 85);
      expect(out.counted, [1]);
      expect(f.analyzer.repScores.single, 1.0);
    });

    test('a shallow dip is turned down', () {
      final (f, out) = setup((c) => LungeAnalyzer(clock: c));
      rep(f, 125);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['not deep enough']);
    });

    test('a tiny bend is not an attempt', () {
      final (f, out) = setup((c) => LungeAnalyzer(clock: c));
      rep(f, 142);
      expect(out.counted, isEmpty);
      expect(out.noReps, isEmpty);
    });

    test('there is no knee-past-toe verdict: it is not a fault', () {
      final (f, out) = setup((c) => LungeAnalyzer(clock: c));
      rep(f, 85);
      expect(f.analyzer.allRepIssues.single, isNot(contains('Knee Past Toe')));
    });
  });

  group('overhead press', () {
    /// An arm pressing: [t] 0 = rack (bar at the shoulders, elbows low and in
    /// front, forearms folded back up), 1 = locked out overhead. 100 per segment.
    Pose arms(double t, {double torsoLean = 0, bool knees = true, double kneeBend = 0}) {
      const shoulderY = 300.0;
      // Upper arm swings from forward-and-down (rack) to straight up (lockout).
      final upper = (1 - t) * 130 * math.pi / 180; // from vertical
      final elbowX = 200 + 100 * math.sin(upper);
      final elbowY = shoulderY - 100 * math.cos(upper);
      // Forearm folds back toward the shoulder at the rack, straight at lockout.
      final fore = (1 - t) * -30 * math.pi / 180;
      final wristX = elbowX + 100 * math.sin(fore);
      final wristY = elbowY - 100 * math.cos(fore);
      final lm = <PoseLandmark>[];
      for (final left in [true, false]) {
        final dx = left ? -30.0 : 30.0;
        lm.addAll([
          PoseFixtures.landmark(left ? PoseLandmarkType.leftShoulder : PoseLandmarkType.rightShoulder, 200 + dx, shoulderY),
          PoseFixtures.landmark(left ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow, elbowX + dx, elbowY),
          PoseFixtures.landmark(left ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist, wristX + dx, wristY),
        ]);
      }
      if (knees || torsoLean > 0) {
        final hipX = 200 + 220 * math.sin(torsoLean * math.pi / 180);
        final hipY = shoulderY + 220 * math.cos(torsoLean * math.pi / 180);
        // Straight legs unless [kneeBend] says otherwise.
        final bend = kneeBend * math.pi / 180;
        final kneeX = hipX + 120 * math.sin(bend);
        final kneeY = hipY + 120 * math.cos(bend);
        lm.addAll([
          PoseFixtures.landmark(PoseLandmarkType.leftHip, hipX, hipY),
          PoseFixtures.landmark(PoseLandmarkType.leftKnee, kneeX, kneeY),
          PoseFixtures.landmark(PoseLandmarkType.leftAnkle, hipX, hipY + 240),
        ]);
      }
      return PoseFixtures.fromLandmarks(lm);
    }

    void rep(Feed f, {double bottom = 0.0, double top = 1.0, double torsoLean = 0, double kneeBend = 0}) {
      Pose at(double t) => arms(t, torsoLean: torsoLean, kneeBend: kneeBend);
      f.hold(at(top), 6);
      f.sweep(at, top, bottom, steps: 14);
      f.hold(at(bottom), 4);
      f.sweep(at, bottom, top, steps: 14);
      f.hold(at(top), 6);
    }

    test('rack to lockout and back counts, counted as the arms lock out', () {
      final (f, out) = setup((c) => OverheadPressAnalyzer(clock: c));
      rep(f);
      expect(out.counted, [1]);
      expect(f.analyzer.repScores.single, 1.0);
    });

    test('a press that stops short of lockout and comes back down is turned down', () {
      final (f, out) = setup((c) => OverheadPressAnalyzer(clock: c));
      f.hold(arms(1.0), 6);
      f.sweep((t) => arms(t), 1.0, 0.0, steps: 14);
      f.hold(arms(0.0), 4);
      f.sweep((t) => arms(t), 0.0, 0.55, steps: 10); // bar overhead-ish, arms not locked
      f.hold(arms(0.55), 8);
      f.sweep((t) => arms(t), 0.55, 0.0, steps: 10);
      f.hold(arms(0.0), 6);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['press all the way up']);
    });

    test('bending the knees to get the bar up (a push press) is flagged', () {
      final (f, out) = setup((c) => OverheadPressAnalyzer(clock: c));
      f.hold(arms(1.0), 6);
      f.sweep((t) => arms(t), 1.0, 0.0, steps: 14);
      f.hold(arms(0.0), 4);
      // The dip and drive: knees bend 35 degrees as the bar goes up.
      for (var i = 0; i <= 14; i++) {
        final t = i / 14;
        f.frame(arms(t, kneeBend: 35 * math.sin(math.pi * t)));
      }
      f.hold(arms(1.0), 6);
      expect(out.counted, [1]);
      expect(f.analyzer.allRepIssues.single, contains('Leg Drive'));
      expect(f.analyzer.repScores.single, lessThan(1.0));
    });

    test('folding over to set the bar down is not a press', () {
      final (f, out) = setup((c) => OverheadPressAnalyzer(clock: c));
      f.hold(arms(1.0), 6);
      for (var i = 0; i <= 14; i++) {
        f.frame(arms(1.0 - i / 14, torsoLean: 60 * i / 14));
      }
      f.hold(arms(0.0, torsoLean: 60), 4);
      for (var i = 0; i <= 14; i++) {
        f.frame(arms(i / 14, torsoLean: 60 * (1 - i / 14)));
      }
      f.hold(arms(1.0), 6);
      expect(out.counted, isEmpty);
      expect(out.noReps, isEmpty, reason: 'not an attempt, so no verdict');
    });

    test('the wrist-stack cue is about the wrists, not the elbows', () {
      final (f, _) = setup((c) => OverheadPressAnalyzer(clock: c));
      final said = <String>[];
      f.analyzer.onCorrection = said.add;
      Pose flared(double t) {
        final p = arms(t);
        return PoseFixtures.fromLandmarks([
          for (final lm in p.landmarks.values)
            lm.type == PoseLandmarkType.leftWrist || lm.type == PoseLandmarkType.rightWrist
                ? PoseFixtures.landmark(lm.type, lm.x + 80, lm.y)
                : lm,
        ]);
      }

      f.hold(arms(1.0), 6);
      f.sweep(flared, 1.0, 0.0, steps: 14);
      f.hold(flared(0.0), 4);
      f.sweep(flared, 0.0, 1.0, steps: 14);
      expect(said.any((m) => m.toLowerCase().contains('elbows under')), isFalse);
    });
  });

  group('jumping jack', () {
    /// A front-on jack: feet [spread] torso-lengths apart, arms at [armAngle]
    /// degrees abduction, with the tracker [armConfidence] sure of the arms.
    Pose jack({required double spread, required double armAngle, double armConfidence = 0.95, bool ankles = true}) {
      const torso = 160.0;
      const half = 60.0;
      final rad = armAngle * math.pi / 180;
      final dx = 100 * math.sin(rad), dy = 100 * math.cos(rad);
      final lm = <PoseLandmark>[
        PoseFixtures.landmark(PoseLandmarkType.leftShoulder, 200 - half, 200),
        PoseFixtures.landmark(PoseLandmarkType.rightShoulder, 200 + half, 200),
        PoseFixtures.landmark(PoseLandmarkType.leftHip, 200 - half, 200 + torso),
        PoseFixtures.landmark(PoseLandmarkType.rightHip, 200 + half, 200 + torso),
        PoseFixtures.landmark(PoseLandmarkType.leftElbow, 200 - half - dx, 200 + dy, likelihood: armConfidence),
        PoseFixtures.landmark(PoseLandmarkType.rightElbow, 200 + half + dx, 200 + dy, likelihood: armConfidence),
      ];
      if (ankles) {
        lm.addAll([
          PoseFixtures.landmark(PoseLandmarkType.leftAnkle, 200 - spread * torso / 2, 200 + torso * 2.2),
          PoseFixtures.landmark(PoseLandmarkType.rightAnkle, 200 + spread * torso / 2, 200 + torso * 2.2),
        ]);
      }
      return PoseFixtures.fromLandmarks(lm);
    }

    void cycle(Feed f, {double apart = 1.1, double arms = 165, double armConfidence = 0.95, int count = 1}) {
      for (var n = 0; n < count; n++) {
        f.hold(jack(spread: 0.25, armAngle: 20, armConfidence: armConfidence), 3);
        for (var i = 0; i <= 5; i++) {
          final t = i / 5;
          f.frame(jack(spread: 0.25 + (apart - 0.25) * t, armAngle: 20 + (arms - 20) * t, armConfidence: armConfidence));
        }
        f.hold(jack(spread: apart, armAngle: arms, armConfidence: armConfidence), 2);
        for (var i = 0; i <= 5; i++) {
          final t = i / 5;
          f.frame(jack(spread: apart - (apart - 0.25) * t, armAngle: arms - (arms - 20) * t, armConfidence: armConfidence));
        }
        f.hold(jack(spread: 0.25, armAngle: 20, armConfidence: armConfidence), 3);
      }
    }

    test('counts from the feet: one jump, one jack', () {
      final (f, out) = setup((c) => JumpingJackAnalyzer(clock: c));
      cycle(f, count: 5);
      expect(out.counted, [1, 2, 3, 4, 5]);
      expect(out.noReps, isEmpty);
    });

    test('arms the tracker is unsure of (motion blur) are not coached, and the jack still counts', () {
      final (f, out) = setup((c) => JumpingJackAnalyzer(clock: c));
      final said = <String>[];
      f.analyzer.onCorrection = said.add;
      // The arms read at shoulder height (blurred), at 0.5 confidence.
      cycle(f, arms: 90, armConfidence: 0.5, count: 4);
      expect(out.counted, [1, 2, 3, 4]);
      expect(said.where((m) => m.toLowerCase().contains('arms')), isEmpty);
      expect(f.analyzer.allRepIssues.expand((i) => i), isNot(contains('Arms Not Fully Raised')));
    });

    test('arms that the tracker is sure stayed down turn the jack down', () {
      final (f, out) = setup((c) => JumpingJackAnalyzer(clock: c));
      cycle(f, arms: 40, count: 3);
      expect(out.counted, isEmpty);
      expect(out.noReps, ['arms all the way up', 'arms all the way up', 'arms all the way up']);
    });

    test('arms to shoulder height are counted but scored short', () {
      final (f, out) = setup((c) => JumpingJackAnalyzer(clock: c));
      cycle(f, arms: 92, count: 2);
      expect(out.counted, [1, 2]);
      expect(f.analyzer.allRepIssues.first, contains('Arms Not Fully Raised'));
    });

    test('feet that barely part count, scored short', () {
      final (f, out) = setup((c) => JumpingJackAnalyzer(clock: c));
      cycle(f, apart: 0.72, count: 2);
      expect(out.counted, [1, 2]);
      expect(f.analyzer.allRepIssues.first, contains('Feet Not Spread'));
    });

    test('a shuffle that never opens the feet is not a jack', () {
      final (f, out) = setup((c) => JumpingJackAnalyzer(clock: c));
      cycle(f, apart: 0.58, count: 3);
      expect(out.counted, isEmpty);
    });

    test('no tempo coaching', () {
      expect(JumpingJackAnalyzer().coachesLowering, isFalse);
    });

    test('with the ankles out of frame it falls back to counting the arms', () {
      final (f, out) = setup((c) => JumpingJackAnalyzer(clock: c));
      for (var n = 0; n < 3; n++) {
        f.hold(jack(spread: 0, armAngle: 20, ankles: false), 3);
        for (var i = 0; i <= 6; i++) {
          f.frame(jack(spread: 0, armAngle: 20 + 145 * i / 6, ankles: false));
        }
        for (var i = 0; i <= 6; i++) {
          f.frame(jack(spread: 0, armAngle: 165 - 145 * i / 6, ankles: false));
        }
        f.hold(jack(spread: 0, armAngle: 20, ankles: false), 3);
      }
      expect(out.counted, [1, 2, 3]);
    });
  });
}
