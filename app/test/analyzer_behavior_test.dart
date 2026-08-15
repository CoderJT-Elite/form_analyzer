import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_constants.dart';
import 'package:form_analyzer/logic/cue_engine.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'support/pose_fixtures.dart';

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
  double backAngle = 175.0,
  double lateralSpread = 0.0,
  int steps = 24,
}) {
  for (var i = 0; i <= steps; i++) {
    final angle = from + (to - from) * (i / steps);
    analyzer.processPose(
      PoseFixtures.squat(
        kneeAngle: angle,
        backAngle: backAngle,
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
  double backAngle = 175.0,
}) {
  sweepSquat(analyzer, from: 175, to: bottom, backAngle: backAngle);
  settle(analyzer, PoseFixtures.squat(kneeAngle: bottom, backAngle: backAngle),
      frames: 6);
  sweepSquat(analyzer, from: bottom, to: 175, backAngle: backAngle);
  settle(analyzer, PoseFixtures.squat(kneeAngle: 175, backAngle: backAngle),
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

    test('penalises a rounded back', () {
      settle(analyzer, PoseFixtures.squat(kneeAngle: 175));
      performSquatRep(analyzer, backAngle: 150);

      expect(analyzer.repCount, 1);
      expect(analyzer.allRepIssues.single, contains('Rounded Back'));
      expect(
        analyzer.repScores.single,
        closeTo(1.0 - AppConstants.squatRoundedBackPenalty, 0.001),
      );
    });

    test('raises a safety alert on critical back rounding, seen side-on', () {
      final alerts = <String>[];
      analyzer.onSafetyAlert = alerts.add;

      settle(analyzer, PoseFixtures.squat(kneeAngle: 175, backAngle: 130));

      expect(alerts, isNotEmpty);
    });

    test(
        'does not silently pass the back check when the athlete faces the camera',
        () {
      final alerts = <String>[];
      final corrections = <String>[];
      analyzer.onSafetyAlert = alerts.add;
      analyzer.onCorrection = corrections.add;

      // Identical joint angles to the side-on case above — a badly rounded
      // back — but viewed head-on, where shoulder/hip/knee are near-collinear
      // in the image and the measured angle is meaningless.
      settle(
        analyzer,
        PoseFixtures.squat(kneeAngle: 175, backAngle: 130, lateralSpread: 90),
        frames: 30,
      );

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
      performSquatRep(analyzer, bottom: 120, backAngle: 130);
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
    late PlankAnalyzer analyzer;

    setUp(() => analyzer = PlankAnalyzer());

    test('a straight back is a good hold', () {
      final evaluation = analyzer.evaluateHold(PoseFixtures.plank(backAngle: 178));
      expect(evaluation, isNotNull);
      expect(evaluation!.isCorrect, isTrue);
    });

    test('sagging hips are told to lift, not lower', () {
      final evaluation = analyzer.evaluateHold(
        PoseFixtures.plank(backAngle: 140, sagging: true),
      );

      expect(evaluation!.isCorrect, isFalse);
      expect(evaluation.issue, 'Hips Sagging');
      expect(evaluation.cueId, CueIds.hipsSagging);
    });

    test('piked hips are told to lower', () {
      final evaluation = analyzer.evaluateHold(
        PoseFixtures.plank(backAngle: 140, sagging: false),
      );

      expect(evaluation!.isCorrect, isFalse);
      expect(evaluation.issue, 'Hips Piked');
      expect(evaluation.cueId, CueIds.hipsPiked);
    });

    test('returns null when landmarks are missing', () {
      expect(analyzer.evaluateHold(PoseFixtures.empty()), isNull);
      analyzer.processPose(PoseFixtures.empty());
      expect(analyzer.statusMessage, 'Adjust Camera');
    });

    test('reports held seconds through onRep so the session can be saved',
        () async {
      final seen = <int>[];
      analyzer.onRep = seen.add;

      final good = PoseFixtures.plank(backAngle: 178);
      analyzer.processPose(good);

      // The hold clock is real time; wait past the first second boundary.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      analyzer.processPose(good);

      expect(seen, isNotEmpty,
          reason: 'ExerciseScreen only saves a session when onRep has fired.');
      expect(analyzer.repCount, greaterThanOrEqualTo(1));
      expect(analyzer.repScores, isNotEmpty);
    });

    test('scores seconds held with broken form lower than clean ones',
        () async {
      analyzer.processPose(PoseFixtures.plank(backAngle: 178));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      analyzer.processPose(PoseFixtures.plank(backAngle: 140, sagging: true));

      expect(analyzer.repScores, isNotEmpty);
      expect(analyzer.repScores.last, lessThan(1.0));
    });

    test('reset stops and zeroes the clock', () async {
      analyzer.processPose(PoseFixtures.plank(backAngle: 178));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      analyzer.processPose(PoseFixtures.plank(backAngle: 178));
      expect(analyzer.repCount, greaterThanOrEqualTo(1));

      analyzer.reset();

      expect(analyzer.repCount, 0);
      expect(analyzer.heldSeconds, 0);
      expect(analyzer.repScores, isEmpty);
    });
  });

  group('PushupAnalyzer', () {
    late PushupAnalyzer analyzer;

    setUp(() => analyzer = PushupAnalyzer());

    test('counts a clean rep to full lockout', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      sweepPushup(analyzer, from: 175, to: 70);
      sweepPushup(analyzer, from: 70, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.single, 1.0);
    });

    test('does not count a rep that never reaches depth', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));
      // 120 degrees never crosses the 90 degree depth threshold.
      sweepPushup(analyzer, from: 175, to: 120);
      sweepPushup(analyzer, from: 120, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 0);
      expect(analyzer.phase, RepPhase.neutral,
          reason: 'Must recover to neutral, not stick in eccentric.');
    });

    test('recovers from a shallow rep and scores the next one cleanly', () {
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175));

      sweepPushup(analyzer, from: 175, to: 120);
      sweepPushup(analyzer, from: 120, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      sweepPushup(analyzer, from: 175, to: 70);
      sweepPushup(analyzer, from: 70, to: 175);
      settle(analyzer, PoseFixtures.pushup(elbowAngle: 175), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.allRepIssues.single, isEmpty);
      expect(analyzer.repScores.single, 1.0);
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
