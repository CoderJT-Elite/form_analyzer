import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/core/app_constants.dart';
import 'package:form_analyzer/logic/cue_engine.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'support/pose_fixtures.dart';
import 'support/test_clock.dart';

/// Hold a single pose for enough frames that the moving-average and
/// exponential filters settle on it.
void settle(ExerciseAnalyzer analyzer, pose, {int frames = 15}) {
  for (var i = 0; i < frames; i++) {
    analyzer.processPose(pose);
  }
}

/// Move the squat knee angle smoothly from [from] to [to].
void sweepSquat(
  ExerciseAnalyzer analyzer, {
  required double from,
  required double to,
  double forwardLean = 0.0,
  double lateralSpread = 0.0,
  int steps = 24,
}) {
  for (var i = 0; i <= steps; i++) {
    final angle = from + (to - from) * (i / steps);
    analyzer.processPose(
      PoseFixtures.squat(
        kneeAngle: angle,
        forwardLean: forwardLean,
        lateralSpread: lateralSpread,
      ),
    );
  }
}

/// Move the pushup elbow angle smoothly from [from] to [to].
void sweepPushup(
  ExerciseAnalyzer analyzer, {
  required double from,
  required double to,
  int steps = 24,
}) {
  for (var i = 0; i <= steps; i++) {
    final angle = from + (to - from) * (i / steps);
    analyzer.processPose(PoseFixtures.pushup(elbowAngle: angle));
  }
}

/// One full squat: stand, descend to [bottom], stand back up.
void performSquatRep(
  ExerciseAnalyzer analyzer, {
  double bottom = 80.0,
  double forwardLean = 0.0,
}) {
  sweepSquat(analyzer, from: 175, to: bottom, forwardLean: forwardLean);
  settle(analyzer, PoseFixtures.squat(kneeAngle: bottom, forwardLean: forwardLean),
      frames: 6);
  sweepSquat(analyzer, from: bottom, to: 175, forwardLean: forwardLean);
  settle(analyzer, PoseFixtures.squat(kneeAngle: 175, forwardLean: forwardLean),
      frames: 6);
}

void main() {
  group('Pose fixtures produce the angles they claim', () {
    test('squat knee angle round-trips', () {
      final analyzer = SquatAnalyzer();
      settle(analyzer, PoseFixtures.squat(kneeAngle: 90));
      expect(analyzer.lastProcessedAngle, closeTo(90, 1.0));
    });

    test('plank back angle round-trips', () {
      final analyzer = PlankAnalyzer();
      analyzer.processPose(PoseFixtures.plank(backAngle: 178));
      expect(analyzer.lastProcessedAngle, closeTo(178, 1.0));
    });
  });

  group('SquatAnalyzer', () {
    late SquatAnalyzer analyzer;

    setUp(() => analyzer = SquatAnalyzer());

    test('counts a clean rep and scores it perfect', () {
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      expect(analyzer.repCount, 0);

      performSquatRep(analyzer);

      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.single, 1.0);
      expect(analyzer.allRepIssues.single, isEmpty);
    });

    test('fires onRep with the running count', () {
      final seen = <int>[];
      analyzer.onRep = seen.add;

      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      performSquatRep(analyzer);
      performSquatRep(analyzer);

      expect(seen, [1, 2]);
    });

    test('does not count a rep that never reaches depth', () {
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      // 120 degrees is a long way short of the 90 degree depth threshold.
      performSquatRep(analyzer, bottom: 120);

      expect(analyzer.repCount, 0);
    });

    test('turns down a squat folded over at the bottom, and says why', () {
      // A torso 70 degrees from vertical is a hip hinge or a crouch to the
      // floor, not a squat: live test #5 counted and praised eight of them.
      final reasons = <String>[];
      analyzer.onNoRep = (reason, spoken) => reasons.add(reason);
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      performSquatRep(analyzer, forwardLean: 70);

      expect(analyzer.repCount, 0);
      expect(analyzer.noRepCount, 1);
      expect(reasons.single, contains('chest up'));
      expect(analyzer.noRepRecords.single.counted, isFalse);
    });

    test('penalises a chest collapsing forward relative to the shins', () {
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      performSquatRep(analyzer, forwardLean: 50);

      expect(analyzer.repCount, 1);
      expect(analyzer.allRepIssues.single, contains('Excessive Forward Lean'));
      expect(
        analyzer.repScores.single,
        closeTo(1.0 - AppConstants.squatTorsoLeanPenalty, 0.001),
      );
    });

    test('a deep squat with a sound torso is never called back rounding', () {
      // Regression: shoulder-hip-knee closes to well under 145 degrees at the
      // bottom of every deep squat (it is hip flexion), and the old check
      // flagged each one as critical back rounding -- live tests 2026-09-13
      // and 2026-09-20.
      final alerts = <String>[];
      analyzer.onSafetyAlert = alerts.add;

      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      performSquatRep(analyzer, bottom: 60);
      performSquatRep(analyzer, bottom: 60);

      expect(analyzer.repCount, 2);
      expect(alerts, isEmpty);
      for (final issues in analyzer.allRepIssues) {
        expect(issues, isNot(contains('Rounded Back')));
        expect(issues, isNot(contains('Critical Back Rounding')));
        expect(issues, isNot(contains('Excessive Forward Lean')));
      }
      expect(analyzer.repScores, everyElement(1.0));
    });

    test('works from one visible leg when the far leg is hidden', () {
      // Side-on, the far leg is often occluded and reads low confidence.
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      var pose = PoseFixtures.squat(kneeAngle: 175);
      Pose hideRight(Pose p) => Pose(landmarks: {
            for (final e in p.landmarks.entries)
              e.key: (e.key.name.startsWith('right'))
                  ? PoseLandmark(
                      type: e.value.type,
                      x: e.value.x,
                      y: e.value.y,
                      z: e.value.z,
                      likelihood: 0.1,
                    )
                  : e.value,
          });
      for (var i = 0; i <= 24; i++) {
        pose = PoseFixtures.squat(kneeAngle: 175 + (80 - 175) * (i / 24));
        analyzer.processPose(hideRight(pose));
      }
      for (var i = 0; i < 6; i++) {
        analyzer.processPose(hideRight(PoseFixtures.squat(kneeAngle: 80)));
      }
      for (var i = 0; i <= 24; i++) {
        pose = PoseFixtures.squat(kneeAngle: 80 + (175 - 80) * (i / 24));
        analyzer.processPose(hideRight(pose));
      }
      for (var i = 0; i < 6; i++) {
        analyzer.processPose(hideRight(PoseFixtures.squat(kneeAngle: 175)));
      }

      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      expect(analyzer.repCount, 1);
    });

    test('coaches a chest that collapses forward, seen side-on', () {
      final corrections = <String>[];
      analyzer.onCorrection = corrections.add;

      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      performSquatRep(analyzer, forwardLean: 80);

      expect(corrections, contains(anyOf('Keep your chest up', 'Stay more upright')));
    });

    test(
        'does not silently pass the back check when the athlete faces the camera',
        () {
      final clock = ManualClock();
      final facing = SquatAnalyzer(clock: clock.call);
      final corrections = <String>[];
      facing.onCorrection = corrections.add;

      // Identical joint angles to the side-on case above -- a badly rounded
      // back -- but viewed head-on, where shoulder/hip/knee are near-collinear
      // in the image and the measured angle is meaningless. The athlete is told
      // to turn once the view has stayed wrong for a few seconds with nothing
      // counting (said sooner, or mid-set, it is a nag).
      final pose = PoseFixtures.squat(kneeAngle: 175, forwardLean: 80, lateralSpread: 90);
      for (var i = 0; i < 5 * 15; i++) {
        clock.advance(const Duration(milliseconds: 66));
        facing.processPose(pose);
      }

      expect(
        corrections.any((message) => message.toLowerCase().contains('side')),
        isTrue,
        reason: 'The athlete should be asked to turn side-on.',
      );
    });

    test('counts reps normally even when the view is head-on', () {
      // Rep counting uses the knee angle, which survives a front view; only
      // the back-angle safety check needs the side view.
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175, lateralSpread: 90));
      sweepSquat(analyzer, from: 175, to: 80, lateralSpread: 90);
      sweepSquat(analyzer, from: 80, to: 175, lateralSpread: 90);
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175, lateralSpread: 90),
          frames: 6);

      expect(analyzer.repCount, 1);
    });

    test('does not carry issues from an aborted rep into the next one', () {
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));

      // A shallow rep with a badly rounded back: no rep is counted, but the
      // issue used to linger in currentRepIssues.
      performSquatRep(analyzer, bottom: 120, forwardLean: 80);
      expect(analyzer.repCount, 0);

      // A clean rep afterwards must score perfectly.
      performSquatRep(analyzer);

      expect(analyzer.repCount, 1);
      expect(analyzer.allRepIssues.single, isEmpty);
      expect(analyzer.repScores.single, 1.0);
    });

    test('bails out when landmarks are not visible', () {
      analyzer.processPose(PoseFixtures.empty());
      expect(analyzer.statusMessage, 'Adjust Camera');
      expect(analyzer.repCount, 0);
    });

    test('reset clears tracking state', () {
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      performSquatRep(analyzer);
      expect(analyzer.repCount, 1);

      analyzer.reset();

      expect(analyzer.repCount, 0);
      expect(analyzer.repScores, isEmpty);
      expect(analyzer.allRepIssues, isEmpty);
      expect(analyzer.phase, RepPhase.neutral);
    });
  });

  group('PlankAnalyzer', () {
    late ManualClock clock;
    late PlankAnalyzer analyzer;

    setUp(() {
      clock = ManualClock();
      analyzer = PlankAnalyzer(clock: clock.call);
    });

    /// Hold [pose] for [seconds] at 15 fps through the real frame path.
    void hold(Pose pose, double seconds) {
      for (var i = 0; i < seconds * 15; i++) {
        clock.advance(const Duration(milliseconds: 66));
        analyzer.processPose(pose);
      }
    }

    /// Hold for [seconds] and return the verdict on the last frame.
    HoldEvaluation? judgeAfter(Pose pose, double seconds) {
      HoldEvaluation? last;
      for (var i = 0; i < seconds * 15; i++) {
        clock.advance(const Duration(milliseconds: 66));
        last = analyzer.evaluateHold(pose);
      }
      return last;
    }

    test('a straight back is a good hold', () {
      final evaluation = judgeAfter(PoseFixtures.plank(backAngle: 178), 3);
      expect(evaluation, isNotNull);
      expect(evaluation!.isCorrect, isTrue);
    });

    test('sagging hips are told to lift, not lower', () {
      final evaluation = judgeAfter(PoseFixtures.plank(backAngle: 140, sagging: true), 3)!;

      expect(evaluation.isCorrect, isFalse);
      expect(evaluation.issue, 'Hips Sagging');
      expect(evaluation.cueId, CueIds.hipsSagging);
    });

    test('piked hips are told to lower', () {
      final evaluation = judgeAfter(PoseFixtures.plank(backAngle: 140, sagging: false), 3)!;

      expect(evaluation.isCorrect, isFalse);
      expect(evaluation.issue, 'Hips Piked');
      expect(evaluation.cueId, CueIds.hipsPiked);
    });

    test('the seconds spent lowering into position are not judged', () {
      final first = analyzer.evaluateHold(PoseFixtures.plank(backAngle: 140, sagging: true))!;
      expect(first.leftPosition, isTrue);
      expect(first.cueId, isEmpty, reason: 'no cue while settling');
    });

    test('an upright body is not a plank, and is told so', () {
      Pose upright(Pose p) => PoseFixtures.fromLandmarks([
            for (final lm in p.landmarks.values)
              PoseFixtures.landmark(lm.type, -lm.y, lm.x, likelihood: lm.likelihood),
          ]);
      final evaluation = judgeAfter(upright(PoseFixtures.plank(backAngle: 178)), 3)!;
      expect(evaluation.leftPosition, isTrue);
      expect(evaluation.cueId, CueIds.getInPlank);

      hold(upright(PoseFixtures.plank(backAngle: 178)), 5);
      expect(analyzer.repCount, 0, reason: 'no time credited while standing');
      expect(analyzer.statusMessage, contains('plank'));
    });

    test('without a known gravity a sideways plank is not mistaken for standing', () {
      // No accelerometer: a plank filmed with the phone on its side is
      // indistinguishable from a person upright, so it must not be refused.
      analyzer.gravityKnown = false;
      Pose sideways(Pose p) => PoseFixtures.fromLandmarks([
            for (final lm in p.landmarks.values)
              PoseFixtures.landmark(lm.type, -lm.y, lm.x, likelihood: lm.likelihood),
          ]);
      final evaluation = judgeAfter(sideways(PoseFixtures.plank(backAngle: 178)), 3)!;
      expect(evaluation.leftPosition, isFalse);
      expect(evaluation.isCorrect, isTrue);

      hold(sideways(PoseFixtures.plank(backAngle: 178)), 6);
      expect(analyzer.repCount, greaterThanOrEqualTo(3));
    });

    test('returns null when landmarks are missing', () {
      expect(analyzer.evaluateHold(PoseFixtures.empty()), isNull);
      analyzer.processPose(PoseFixtures.empty());
      expect(analyzer.statusMessage, 'Adjust Camera');
    });

    test('reports held seconds through onRep so the session can be saved', () {
      final seen = <int>[];
      analyzer.onRep = seen.add;

      hold(PoseFixtures.plank(backAngle: 178), 4);

      expect(seen, isNotEmpty,
          reason: 'ExerciseScreen only saves a session when onRep has fired.');
      expect(analyzer.repCount, greaterThanOrEqualTo(2));
      expect(analyzer.repScores, isNotEmpty);
    });

    test('scores seconds held with broken form lower than clean ones', () {
      hold(PoseFixtures.plank(backAngle: 178), 3);
      hold(PoseFixtures.plank(backAngle: 140, sagging: true), 3);

      expect(analyzer.repScores, isNotEmpty);
      expect(analyzer.repScores.last, lessThan(1.0));
    });

    test('a badly held plank is forgiven for a moment, then the clock pauses', () {
      // Live test #5 credited 32 seconds of plank for about 15 good ones, because
      // a sagging plank kept the clock running as "time under tension".
      hold(PoseFixtures.plank(backAngle: 178), 3);
      final good = analyzer.heldSeconds;
      final inPosition = analyzer.inPositionSeconds;

      hold(PoseFixtures.plank(backAngle: 140, sagging: true), 8);

      expect(analyzer.heldSeconds, lessThanOrEqualTo(good + 2),
          reason: 'one second of grace, then nothing');
      expect(analyzer.inPositionSeconds, greaterThanOrEqualTo(inPosition + 6),
          reason: 'the athlete is still in position, just not holding it well');
      expect(analyzer.isPaused, isTrue);
      expect(analyzer.statusMessage, contains('Paused'));
      expect(analyzer.statusMessage.toLowerCase(), contains('hips sagging'));
    });

    test('the paused seconds are recorded as seconds that did not count', () {
      hold(PoseFixtures.plank(backAngle: 178), 3);
      hold(PoseFixtures.plank(backAngle: 140, sagging: true), 6);

      expect(analyzer.noRepRecords, isNotEmpty);
      expect(analyzer.noRepRecords.every((r) => !r.counted), isTrue);
      expect(analyzer.noRepRecords.first.noRepReason, 'Hips Sagging');
      final metrics = analyzer.getPerformanceMetrics();
      expect(metrics.noRepCount, analyzer.noRepRecords.length);
    });

    test('the clock resumes once the position has been right for half a second', () {
      hold(PoseFixtures.plank(backAngle: 178), 3);
      hold(PoseFixtures.plank(backAngle: 140, sagging: true), 4);
      expect(analyzer.isPaused, isTrue);

      final pausedAt = analyzer.heldSeconds;
      hold(PoseFixtures.plank(backAngle: 178), 4);

      expect(analyzer.isPaused, isFalse);
      expect(analyzer.heldSeconds, greaterThan(pausedAt));
    });

    test('a hold that starts piked is not credited until the line is right', () {
      hold(PoseFixtures.plank(backAngle: 140, sagging: false), 6);
      expect(analyzer.heldSeconds, 0);
      expect(analyzer.isPaused, isTrue);
    });

    test('reset stops and zeroes the clock', () {
      hold(PoseFixtures.plank(backAngle: 178), 4);
      expect(analyzer.repCount, greaterThanOrEqualTo(1));

      analyzer.reset();

      expect(analyzer.repCount, 0);
      expect(analyzer.heldSeconds, 0);
      expect(analyzer.repScores, isEmpty);
    });
  });

  group('PushupAnalyzer', () {
    late PushupAnalyzer analyzer;

    setUp(() => analyzer = PushupAnalyzer(clock: TestClock().call));

    test('counts a clean rep to full lockout', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      sweepPushup(analyzer, from: 175, to: 70);
      sweepPushup(analyzer, from: 70, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.single, 1.0);
    });

    test('counts a rep that stops a little short of depth, and scores it short', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      // 110 degrees misses the 100 degree depth target by a few degrees but is
      // 65 degrees of real travel: it counts, and costs score.
      sweepPushup(analyzer, from: 175, to: 110);
      sweepPushup(analyzer, from: 110, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.allRepIssues.single, contains('Insufficient Depth'));
      expect(analyzer.repScores.single, lessThan(1.0));
      expect(analyzer.phase, RepPhase.neutral,
          reason: 'Must recover to neutral, not stick in eccentric.');
    });

    test('turns down a rep that only bends to 125 degrees, and says so', () {
      final reasons = <String>[];
      analyzer.onNoRep = (reason, spoken) => reasons.add(reason);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      sweepPushup(analyzer, from: 175, to: 125);
      sweepPushup(analyzer, from: 125, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 0);
      expect(reasons, ['not deep enough']);
      expect(analyzer.phase, RepPhase.neutral);
    });

    test('turns down a rep that never locks out and drops again', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      sweepPushup(analyzer, from: 175, to: 70);
      sweepPushup(analyzer, from: 70, to: 125); // halfway up...
      sweepPushup(analyzer, from: 125, to: 70); // ...and back down: a pulse
      sweepPushup(analyzer, from: 70, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 1, reason: 'only the final full rep counts');
      expect(analyzer.noRepRecords.map((r) => r.noRepReason), ['No Full Lockout']);
    });

    test('does not count a wobble that is not a push-up', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      sweepPushup(analyzer, from: 175, to: 158);
      sweepPushup(analyzer, from: 158, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 0);
      expect(analyzer.phase, RepPhase.neutral);
    });

    test('a shallow rep does not stop the next full one scoring cleanly', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));

      sweepPushup(analyzer, from: 175, to: 110);
      sweepPushup(analyzer, from: 110, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      sweepPushup(analyzer, from: 175, to: 70);
      sweepPushup(analyzer, from: 70, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 2);
      expect(analyzer.allRepIssues.first, contains('Insufficient Depth'));
      expect(analyzer.allRepIssues.last, isEmpty);
      expect(analyzer.repScores.last, 1.0);
    });

    test('counts every rep of a set with no pause between them', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      for (var i = 0; i < 6; i++) {
        sweepPushup(analyzer, from: 175, to: 70, steps: 12);
        sweepPushup(analyzer, from: 70, to: 175, steps: 12);
      }
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 6);
    });

    test('incomplete lockout now costs score instead of being ignored', () {
      expect(
        AppConstants.incompleteLockoutPenalty,
        greaterThan(0),
        reason: 'A rep that never locks out must not score a clean 1.0.',
      );
    });
  });
}
