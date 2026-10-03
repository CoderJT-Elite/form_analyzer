import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_orientation.dart';

import 'support/recorded_pose_fixtures.dart';
import 'support/replay_harness.dart';

/// Drives the real analyzers with landmark sequences extracted
/// from real stock exercise footage via MediaPipe Pose (see
/// tools/extract_all_fixtures.py), testing all 10 exercises against
/// real-world footage across camera angles, pacing, and body types.
void main() {
  group('Squat, real footage', () {
    test('a side-on set of 5 real squats is counted correctly', () {
      final analyzer = SquatAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('squat_pexels_8837221');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // The raw knee angle dips below 90 degrees in all 5 reps in this clip
      // (as low as 44-70 degrees at the true minimum). All 5 are detected.
      expect(analyzer.repCount, 5);
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      for (final score in analyzer.repScores) {
        expect(score, inInclusiveRange(0.0, 1.0));
      }
    });

    test('a front-facing squat is flagged, and its form checks stay quiet', () {
      final run = replay('squat_pexels_4764175', (c) => SquatAnalyzer(clock: c), fps: 30);
      final analyzer = run.analyzer;

      // Filmed head-on, so checks that need a profile cannot run. The knee angle
      // still moves, so some reps are found (2 of the clip's ~5 with a real
      // clock; in a tight loop it read 0), but not all of them.
      expect(analyzer.repCount, lessThan(5));
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      expect(analyzer.orientationTracker.orientation, ViewOrientation.frontOn);
      expect(run.issues, isNot(contains('Excessive Forward Lean')),
          reason: 'a head-on view must not invent a torso-lean verdict');
    });
  });

  group('Pushup, real footage', () {
    test('a real set of push-ups is counted correctly', () {
      final run = replay('pushup_pexels_4367576', (c) => PushupAnalyzer(clock: c), fps: 30);
      final analyzer = run.analyzer;

      // Filmed from a steep angle the tracker reads as front-on, so this runs
      // on the head-on (shoulder-drop) signal; the elbow signal shows 6 clear
      // descents. The old fixed-threshold machine counted 4.
      expect(analyzer.repCount, inInclusiveRange(5, 6));
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      for (final score in analyzer.repScores) {
        expect(score, inInclusiveRange(0.0, 1.0));
      }
    });

    test('tremor does not multiply reps, and a long real set is counted', () {
      final run = replay('pushup_pixabay_302251', (c) => PushupAnalyzer(clock: c), fps: 30);
      final analyzer = run.analyzer;

      // 24 seconds of push-ups filmed close up, with the landmarks jittering
      // 20-30 degrees frame to frame. The old machine counted 1-2 reps here (it
      // waited for a smoothed 90 degrees that tremor smears away); tremor must
      // also not turn the same set into 30.
      expect(analyzer.repCount, inInclusiveRange(6, 10));
      for (final issues in analyzer.allRepIssues) {
        expect(issues, isNot(contains('Incomplete Lockout')));
      }
    });
  });

  group('Lunge, real footage', () {
    test('split/stationary lunge with bent rear knee does not deadlock in concentric', () {
      // A stationary (split) lunge never stands all the way up between reps and
      // the rear knee stays bent (reading ~121 degrees), so the rep boundary has
      // to be the hips rising, not a fixed straight-knee angle. The clip holds
      // five or six genuine lunges (the old analyzer counted three of them).
      final run = replay('lunge_pexels_8171292', (c) => LungeAnalyzer(clock: c), fps: 30);

      expect(run.analyzer.repCount, inInclusiveRange(5, 6));
      expect(run.noReps, isEmpty);
    });

    test('alternating lunge counts completed reps cleanly', () {
      final run = replay('lunge_pexels_4488004', (c) => LungeAnalyzer(clock: c), fps: 30);

      expect(run.analyzer.repCount, 3);
      for (final score in run.analyzer.repScores) {
        expect(score, greaterThanOrEqualTo(0.7));
      }
    });
  });

  group('Overhead Press, real footage', () {
    test('a free-weight press set is counted at each lockout, none of it dropped', () {
      final run = replay('overheadPress_pexels_4367541', (c) => OverheadPressAnalyzer(clock: c), fps: 30);

      // Three full presses (rack to overhead lockout and back) after the opening
      // top position; the trace of the elbow and wrist heights shows exactly
      // three bottoms and four tops over the 24 s clip. (An earlier version of
      // this test pinned 6, which counted lowering and lockout as separate
      // reps: the clip is slow, about 7 s a rep.) Each rep is counted as the
      // arms lock out.
      expect(run.analyzer.repCount, 3);
      expect(run.noReps, isEmpty);
      expect(run.repTimes, [
        closeTo(7.8, 0.6),
        closeTo(15.4, 0.6),
        closeTo(21.2, 0.6),
      ]);
    });

    test('a machine press with a confidence-degraded arm is still counted correctly', () {
      // A shoulder-press machine: both arms move together, so the more open arm
      // (the one the tracker is less sure about) shows the real lockout and is
      // trusted for it. Three full presses to lockout in the clip.
      final run = replay('overheadPress_pexels_32239223', (c) => OverheadPressAnalyzer(clock: c), fps: 30);

      expect(run.analyzer.repCount, 3);
      expect(run.noReps, isEmpty);
    });
  });

  group('Plank, real footage', () {
    test('right-facing athlete is recognized and evaluated bilaterally', () {
      var simulatedTime = DateTime(2026, 9, 10, 12, 0, 0);
      final analyzer = PlankAnalyzer(clock: () => simulatedTime);
      final frames = RecordedPoseFixtures.loadSequence('plank_pexels_6525477');

      for (final pose in frames) {
        simulatedTime = simulatedTime.add(const Duration(milliseconds: 33));
        analyzer.processPose(pose);
      }

      // Previously checked only left side landmarks; a right-facing athlete
      // returned 'Adjust Camera' on 100% of frames. The athlete is now found and
      // judged: this clip holds the hips about 17% of body length above the
      // shoulder-ankle line, so the position is recognised but not credited.
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      expect(analyzer.inPositionSeconds, greaterThanOrEqualTo(2));
      expect(analyzer.statusMessage.toLowerCase(), contains('hips piked'));
    });
  });

  group('Glute Bridge, real footage', () {
    test('safe straight-line bridge (150-153 degrees) completes reps without stalling', () {
      final analyzer = GluteBridgeAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('gluteBridge_pexels_6525487');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // Athlete reaches 153 degrees (safe hip bridge). Requiring 160 degrees caused
      // reps to be discarded as incomplete upon lowering.
      expect(analyzer.repCount, 2);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
    });

    test('bilateral bridge evaluation picks more extended side', () {
      final analyzer = GluteBridgeAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('gluteBridge_pexels_4267359');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // Camera perspective foreshortens the far side (137 deg) while near side reaches 168 deg.
      // Taking the maximum extended hip angle allows all 6 reps to be counted.
      expect(analyzer.repCount, 6);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
    });
  });

  group('Sit-up, real footage', () {
    test('bent-knee sit-ups are counted as the torso comes up and goes back down', () {
      final run = replay('situp_pixabay_293079', (c) => SitupAnalyzer(clock: c), fps: 30);

      // The torso rises 54-68 degrees off the floor four times (plus a fifth,
      // lower peak), measured from the shoulder-hip line rather than the knee.
      expect(run.analyzer.repCount, inInclusiveRange(4, 5));
      expect(run.analyzer.repScores.length, run.analyzer.repCount);
    });

    test('a fast bouncing set only counts the reps that lie back down', () {
      final run = replay('situp_pixabay_296446', (c) => SitupAnalyzer(clock: c), fps: 30);

      // Seven fast reps in 15 seconds, but in the middle of the set the athlete
      // never gets their shoulders back toward the floor (the torso stays 43-56
      // degrees up between them). Those are bounces, not sit-ups: the reps that
      // return to the floor count, and the going-again-without-lowering ones are
      // turned down instead of being counted as extra reps.
      expect(run.analyzer.repCount, inInclusiveRange(2, 4));
      expect(run.noReps.map((e) => e.$2), contains('come all the way back down first'));
    });
  });

  group('Jumping Jack, real footage', () {
    test('jumping jack clip 292741 is counted from the feet, one per jump', () {
      final run = replay('jumpingJack_pixabay_292741', (c) => JumpingJackAnalyzer(clock: c), fps: 30);

      // The arms peak seven times (every ~2 s) and the feet open eight times.
      expect(run.analyzer.repCount, inInclusiveRange(7, 9));
      expect(run.noReps, isEmpty);
    });

    test('continuous rhythmic jumping jacks are all counted', () {
      final run = replay('jumpingJack_pixabay_84375', (c) => JumpingJackAnalyzer(clock: c), fps: 30);

      // Twelve arm and foot peaks in 12 seconds: one a second. (The old arm
      // machine, which needed the arms to come all the way back to rest,
      // counted 5.)
      expect(run.analyzer.repCount, inInclusiveRange(10, 12));
    });
  });

  group('Wall Sit, real footage', () {
    // Neither stock clip is a wall sit, which is what the old analyzer's 70-110
    // degree band hid: one has the knee at 171 degrees (standing), the other has
    // the hips well above the knees (a shallow, sloping sit).
    test('standing straight is not a wall sit', () {
      var simulatedTime = DateTime(2026, 9, 10, 12, 0, 0);
      final analyzer = WallSitAnalyzer(clock: () => simulatedTime);
      for (final pose in RecordedPoseFixtures.loadSequence('wallSit_pexels_6454275')) {
        simulatedTime = simulatedTime.add(const Duration(milliseconds: 33));
        analyzer.processPose(pose);
      }

      expect(analyzer.heldSeconds, 0);
      expect(analyzer.statusMessage.toLowerCase(), contains('not low enough'));
    });

    test('a shallow, sloping sit is not credited either', () {
      var simulatedTime = DateTime(2026, 9, 10, 12, 0, 0);
      final analyzer = WallSitAnalyzer(clock: () => simulatedTime);
      for (final pose in RecordedPoseFixtures.loadSequence('wallSit_pexels_8402078')) {
        simulatedTime = simulatedTime.add(const Duration(milliseconds: 33));
        analyzer.processPose(pose);
      }

      expect(analyzer.heldSeconds, 0);
      expect(analyzer.inPositionSeconds, greaterThanOrEqualTo(5));
    });
  });

  group('Side Plank, real footage', () {
    test('side plank hold duration is tracked and scored', () {
      var simulatedTime = DateTime(2026, 9, 10, 12, 0, 0);
      final analyzer = SidePlankAnalyzer(clock: () => simulatedTime);
      final frames = RecordedPoseFixtures.loadSequence('sidePlank_pexels_6023264');

      for (final pose in frames) {
        simulatedTime = simulatedTime.add(const Duration(milliseconds: 33));
        analyzer.processPose(pose);
      }

      expect(analyzer.heldSeconds, greaterThanOrEqualTo(4));
      expect(analyzer.repRecords, isNotEmpty);
    });
  });
}
