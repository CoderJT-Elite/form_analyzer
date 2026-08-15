import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/core/app_constants.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_orientation.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';

import 'support/pose_fixtures.dart';

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

    test('counts a rep that reaches full hip extension', () {
      final analyzer = GluteBridgeAnalyzer();
      hold(analyzer, bridge(110));

      sweep(analyzer, bridge, from: 110, to: 175);
      sweep(analyzer, bridge, from: 175, to: 110);
      hold(analyzer, bridge(110), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.single, 1.0);
    });

    test('does not count a rep that never locks the hips out', () {
      final analyzer = GluteBridgeAnalyzer();
      hold(analyzer, bridge(110));

      // 145 is short of the 160 degree target.
      sweep(analyzer, bridge, from: 110, to: 145);
      sweep(analyzer, bridge, from: 145, to: 110);
      hold(analyzer, bridge(110), frames: 6);

      expect(analyzer.repCount, 0);
      expect(analyzer.phase, RepPhase.neutral,
          reason: 'Must return to neutral, not stall mid-rep.');
    });
  });

  group('SitupAnalyzer', () {
    Pose situp(double angle) => PoseFixtures.plank(backAngle: angle);

    test('counts a rep that curls all the way up', () {
      final analyzer = SitupAnalyzer();
      hold(analyzer, situp(170));

      sweep(analyzer, situp, from: 170, to: 80);
      sweep(analyzer, situp, from: 80, to: 170);
      hold(analyzer, situp(170), frames: 6);

      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.single, 1.0);
    });

    test('travels in the opposite direction to the glute bridge', () {
      expect(SitupAnalyzer().worksTowardSmallerAngle, isTrue);
      expect(GluteBridgeAnalyzer().worksTowardSmallerAngle, isFalse);
    });
  });

  group('JumpingJackAnalyzer', () {
    Pose jack(double angle) => PoseFixtures.jumpingJack(armAngle: angle);

    test('is judged from the front', () {
      expect(JumpingJackAnalyzer().requiredOrientation, ViewOrientation.frontOn);
    });

    test('counts a rep when the arms go all the way overhead', () {
      final analyzer = JumpingJackAnalyzer();
      hold(analyzer, jack(20));

      sweep(analyzer, jack, from: 20, to: 165);
      sweep(analyzer, jack, from: 165, to: 20);
      hold(analyzer, jack(20), frames: 6);

      expect(analyzer.repCount, 1);
    });

    test('does not count half-raised arms', () {
      final analyzer = JumpingJackAnalyzer();
      hold(analyzer, jack(20));

      // 100 is short of the 135 degree target.
      sweep(analyzer, jack, from: 20, to: 100);
      sweep(analyzer, jack, from: 100, to: 20);
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
    test('a straight body line is a good hold', () {
      final analyzer = SidePlankAnalyzer();
      final evaluation =
          analyzer.evaluateHold(PoseFixtures.sidePlank(bodyAngle: 175));

      expect(evaluation!.isCorrect, isTrue);
    });

    test('a dropped hip breaks the hold', () {
      final analyzer = SidePlankAnalyzer();
      final evaluation =
          analyzer.evaluateHold(PoseFixtures.sidePlank(bodyAngle: 140));

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
    expect(AppConstants.situpTopAngle, lessThan(AppConstants.situpRestAngle));
    expect(AppConstants.jumpingJackRestAngle,
        lessThan(AppConstants.jumpingJackTopAngle));
    expect(AppConstants.wallSitKneeAngleMin,
        lessThan(AppConstants.wallSitKneeAngleMax));
  });
}
