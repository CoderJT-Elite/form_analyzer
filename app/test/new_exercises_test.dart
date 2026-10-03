import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/core/app_constants.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_orientation.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';

import 'support/pose_fixtures.dart';
import 'support/test_clock.dart';

/// Drive an analyzer through a smooth travel between two angles.
void sweep(
  ExerciseAnalyzer analyzer,
  Pose Function(double angle) build, {
  required double from,
  required double to,
  int steps = 24,
}) {
  for (var i = 0; i <= steps; i++) {
    analyzer.processPose(build(from + (to - from) * (i / steps)));
  }
}

void hold(ExerciseAnalyzer analyzer, Pose pose, {int frames = 15}) {
  for (var i = 0; i < frames; i++) {
    analyzer.processPose(pose);
  }
}

void main() {
  group('GluteBridgeAnalyzer', () {
    Pose bridge(double angle) => PoseFixtures.plank(backAngle: angle);
    late GluteBridgeAnalyzer analyzer;
    late List<String> turnedDown;

    setUp(() {
      analyzer = GluteBridgeAnalyzer(clock: TestClock().call);
      turnedDown = [];
      analyzer.onNoRep = (reason, spoken) => turnedDown.add(reason);
    });

    test('counts a rep that reaches full hip extension', () {
      hold(analyzer, bridge(125));

      sweep(analyzer, bridge, from: 125, to: 175);
      sweep(analyzer, bridge, from: 175, to: 125);
      hold(analyzer, bridge(125), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.single, 1.0);
    });

    test('a hip twitch is not a rep: 15 degrees of travel is ignored, silently', () {
      hold(analyzer, bridge(125));

      // The old 138-to-150 range gave full credit for exactly this.
      sweep(analyzer, bridge, from: 125, to: 140);
      sweep(analyzer, bridge, from: 140, to: 125);
      hold(analyzer, bridge(125), frames: 6);

      expect(analyzer.repCount, 0);
      expect(turnedDown, isEmpty, reason: 'a twitch is not worth a verdict');
      expect(analyzer.phase, RepPhase.neutral,
          reason: 'Must return to neutral, not stall mid-rep.');
    });

    test('a half bridge is turned down, and says to push the hips higher', () {
      hold(analyzer, bridge(125));

      sweep(analyzer, bridge, from: 125, to: 152);
      sweep(analyzer, bridge, from: 152, to: 125);
      hold(analyzer, bridge(125), frames: 6);

      expect(analyzer.repCount, 0);
      expect(turnedDown, ['push your hips higher']);
    });

    test('a bridge that comes up and goes again without lowering is a no-rep', () {
      hold(analyzer, bridge(125));

      sweep(analyzer, bridge, from: 125, to: 175);
      sweep(analyzer, bridge, from: 175, to: 155); // only part way down...
      sweep(analyzer, bridge, from: 155, to: 175); // ...and up again
      sweep(analyzer, bridge, from: 175, to: 125);
      hold(analyzer, bridge(125), frames: 6);

      expect(turnedDown, ['come all the way back down first']);
    });
  });

  group('SitupAnalyzer', () {
    Pose situp(double elevation) => PoseFixtures.situp(elevation: elevation);
    late SitupAnalyzer analyzer;
    late List<String> turnedDown;

    setUp(() {
      analyzer = SitupAnalyzer(clock: TestClock().call);
      turnedDown = [];
      analyzer.onNoRep = (reason, spoken) => turnedDown.add(reason);
    });

    test('counts a rep that sits all the way up', () {
      hold(analyzer, situp(5));

      sweep(analyzer, situp, from: 5, to: 75);
      sweep(analyzer, situp, from: 75, to: 5);
      hold(analyzer, situp(5), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.single, 1.0);
    });

    test('a crunch is not a sit-up: 22 degrees off the floor is ignored', () {
      hold(analyzer, situp(5));

      sweep(analyzer, situp, from: 5, to: 22);
      sweep(analyzer, situp, from: 22, to: 5);
      hold(analyzer, situp(5), frames: 6);

      expect(analyzer.repCount, 0);
      expect(turnedDown, isEmpty);
    });

    test('a half sit-up is turned down ("sit up higher")', () {
      hold(analyzer, situp(5));

      sweep(analyzer, situp, from: 5, to: 38);
      sweep(analyzer, situp, from: 38, to: 5);
      hold(analyzer, situp(5), frames: 6);

      expect(analyzer.repCount, 0);
      expect(turnedDown, ['sit up higher']);
    });

    test('is measured as how high the torso has come up, not a knee-dependent angle', () {
      // Bending or straightening the knees must not move the reading.
      final bent = analyzer.measureAngle(PoseFixtures.situp(elevation: 50, kneeAngle: 80))!;
      final straight = analyzer.measureAngle(PoseFixtures.situp(elevation: 50, kneeAngle: 170))!;
      expect(bent, closeTo(50, 0.5));
      expect(straight, closeTo(bent, 0.5));
      expect(analyzer.measureAngle(PoseFixtures.situp(elevation: 5))!, lessThan(10));
    });
  });

  group('JumpingJackAnalyzer', () {
    Pose jack(double angle) => PoseFixtures.jumpingJack(armAngle: angle);

    test('is judged from the front', () {
      expect(JumpingJackAnalyzer().requiredOrientation, ViewOrientation.frontOn);
    });

    test('with the ankles out of frame, counts a rep when the arms go all the way overhead', () {
      final analyzer = JumpingJackAnalyzer(clock: TestClock().call);
      hold(analyzer, jack(20));

      sweep(analyzer, jack, from: 20, to: 165);
      sweep(analyzer, jack, from: 165, to: 20);
      hold(analyzer, jack(20), frames: 6);

      expect(analyzer.repCount, 1);
    });

    test('does not count half-raised arms', () {
      final analyzer = JumpingJackAnalyzer(clock: TestClock().call);
      hold(analyzer, jack(20));

      // 98 is short of the 105 degree bar for arms-only counting.
      sweep(analyzer, jack, from: 20, to: 98);
      sweep(analyzer, jack, from: 98, to: 20);
      hold(analyzer, jack(20), frames: 6);

      expect(analyzer.repCount, 0);
    });
  });

  group('WallSitAnalyzer', () {
    test('a right angle at the knee is a good hold', () {
      final analyzer = WallSitAnalyzer();
      final evaluation =
          analyzer.evaluateHold(PoseFixtures.squat(kneeAngle: 90));

      expect(evaluation!.isCorrect, isTrue);
    });

    test('standing too tall is called out as not low enough', () {
      final analyzer = WallSitAnalyzer();
      final evaluation =
          analyzer.evaluateHold(PoseFixtures.squat(kneeAngle: 140));

      expect(evaluation!.isCorrect, isFalse);
      expect(evaluation.issue, 'Not Low Enough');
    });

    test('sliding below a right angle is called out as too low', () {
      final analyzer = WallSitAnalyzer();
      final evaluation =
          analyzer.evaluateHold(PoseFixtures.squat(kneeAngle: 50));

      expect(evaluation!.isCorrect, isFalse);
      expect(evaluation.issue, 'Too Low');
    });

    test('reports held seconds through onRep', () async {
      final analyzer = WallSitAnalyzer();
      final seen = <int>[];
      analyzer.onRep = seen.add;

      final good = PoseFixtures.squat(kneeAngle: 90);
      analyzer.processPose(good);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      analyzer.processPose(good);

      expect(seen, isNotEmpty);
    });
  });

  group('SidePlankAnalyzer', () {
    /// Hold [pose] for [seconds] and return the verdict on the last frame. A
    /// hold is not judged until the athlete has settled into position.
    HoldEvaluation? judgeAfter(SidePlankAnalyzer analyzer, ManualClock clock, Pose pose,
        [double seconds = 3]) {
      HoldEvaluation? last;
      for (var i = 0; i < seconds * 15; i++) {
        clock.advance(const Duration(milliseconds: 66));
        last = analyzer.evaluateHold(pose);
      }
      return last;
    }

    test('a straight body line is a good hold', () {
      final clock = ManualClock();
      final analyzer = SidePlankAnalyzer(clock: clock.call);
      final evaluation = judgeAfter(analyzer, clock, PoseFixtures.sidePlank(bodyAngle: 175));

      expect(evaluation!.isCorrect, isTrue);
    });

    test('a dropped hip breaks the hold', () {
      final clock = ManualClock();
      final analyzer = SidePlankAnalyzer(clock: clock.call);
      final evaluation = judgeAfter(analyzer, clock, PoseFixtures.sidePlank(bodyAngle: 140));

      expect(evaluation!.isCorrect, isFalse);
      expect(evaluation.issue, 'Hips Sagging');
    });

    test('returns null when landmarks are missing', () {
      expect(SidePlankAnalyzer().evaluateHold(PoseFixtures.empty()), isNull);
    });
  });

  group('Catalog', () {
    test('offers ten exercises', () {
      expect(ExerciseCatalog.definitions, hasLength(10));
      expect(ExerciseType.values, hasLength(10));
    });

    test('builds a distinct analyzer instance every time', () {
      for (final type in ExerciseType.values) {
        final a = ExerciseCatalog.exerciseForType(type);
        final b = ExerciseCatalog.exerciseForType(type);
        expect(identical(a.analyzer, b.analyzer), isFalse, reason: '$type');
      }
    });

    test('repeated reads of `all` do not share analyzer state', () {
      final first = ExerciseCatalog.all.first;
      first.analyzer.repCount = 7;

      expect(ExerciseCatalog.all.first.analyzer.repCount, 0,
          reason: 'Catalog entries must not carry state between workouts.');
    });

    test('every analyzer declares the landmarks it needs', () {
      for (final definition in ExerciseCatalog.definitions) {
        expect(definition.createAnalyzer().activeLandmarkTypes, isNotEmpty,
            reason: definition.name);
      }
    });

    test('timed exercises start with a zeroed clock', () {
      for (final definition in ExerciseCatalog.definitions) {
        final analyzer = definition.createAnalyzer();
        if (analyzer is TimedExerciseAnalyzer) {
          expect(analyzer.heldSeconds, 0, reason: definition.name);
          expect(analyzer.repCount, 0, reason: definition.name);
        }
      }
    });
  });

  test('range thresholds are ordered correctly for each new exercise', () {
    expect(AppConstants.gluteBridgeRestAngle,
        lessThan(AppConstants.gluteBridgeTopAngle));
    expect(AppConstants.situpRestAngle, lessThan(AppConstants.situpTopAngle));
    expect(AppConstants.jumpingJackRestAngle,
        lessThan(AppConstants.jumpingJackTopAngle));
    expect(AppConstants.wallSitKneeAngleMin,
        lessThan(AppConstants.wallSitKneeAngleMax));
  });
}
