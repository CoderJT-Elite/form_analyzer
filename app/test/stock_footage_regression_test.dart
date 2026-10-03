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
    test('set of 6 full overhead presses counted cleanly, including a strained final rep',
        () {
      final analyzer = OverheadPressAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('overheadPress_pexels_4367541');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // A prior pass over this pipeline lowered overheadPressLockoutThreshold
      // from 165 to 152 and called it done at 5 reps. That missed a real 6th
      // rep: this clip's final press is visibly effortful (confirmed by
      // screenshotting the source video directly -- strained expression,
      // genuine full lockout at frames ~682-715 of 715), and it only failed
      // to register because OverheadPressAnalyzer picked a single arm by ML
      // Kit confidence, the same bug already fixed in SquatAnalyzer/
      // LungeAnalyzer/GluteBridgeAnalyzer. During this final rep the
      // right arm's tracking confidence dropped (likely the athlete
      // straining/tilting) right as it reached genuine lockout, so the
      // "more confident" left arm's angle was trusted instead -- and never
      // read as fully locked out on its own within this window. Fixed by
      // taking whichever visible arm reads more extended for the
      // lockout/neutral-threshold comparisons (max) and whichever reads more
      // flexed for the bottom-of-press check (min), the same bilateral
      // principle as the other fixes -- confirmed by re-screenshotting the
      // same frames and by this test.
      expect(analyzer.repCount, 6);
      // Rep 2 carries a real 'Wrist Not Stacked' flag (0.8) -- the wrist drifts
      // out from directly above the elbow on that specific press, recovering by
      // rep 3. The other 5 reps score clean.
      expect(analyzer.repScores, [1.0, 0.8, 1.0, 1.0, 1.0, 1.0]);
    });

    test('a machine press with a confidence-degraded arm is still counted correctly', () {
      final analyzer = OverheadPressAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('overheadPress_pexels_32239223');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // A prior pass labeled this clip "found but not fixed by design":
      // elbow angle allegedly topped out at 144 degrees, so 0 reps was
      // called correct. That was wrong -- verified by screenshotting the
      // source video directly, this is a shoulder-press MACHINE (not free
      // weights), so both arms are mechanically constrained to move
      // together; the athlete presses to genuine full lockout repeatedly.
      // The right arm's raw angle reaches 156-171 degrees several times
      // (comfortably past even the old 165 degree threshold) while the
      // left arm -- which ML Kit was more "confident" about throughout --
      // never exceeds ~150. Same bilateral-confidence bug as above; same
      // fix recovers the real reps.
      expect(analyzer.repCount, 4);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
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
      // returned 'Adjust Camera' on 100% of frames. Bilateral check now evaluates hold.
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      expect(analyzer.heldSeconds, greaterThanOrEqualTo(2));
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
    test('bent-knee sit-ups complete reps at realistic floor rest angle', () {
      final analyzer = SitupAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('situp_pixabay_293079');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // Bent-knee sit-up lying on floor measures 130-135 degrees.
      // Requiring 150 degrees caused reps to never finish concentric phase.
      expect(analyzer.repCount, 4);
      expect(analyzer.repScores.length, 4);
    });

    test('situp clip 296446 counts the whole fast set, with a genuine side imbalance', () {
      final run = replay('situp_pixabay_296446', (c) => SitupAnalyzer(clock: c), fps: 30);

      // 15 seconds of fast sit-ups. Run in a tight loop with no time passing
      // this used to read as 2 reps; with real frame timing the set is 7.
      expect(run.analyzer.repCount, inInclusiveRange(6, 9));
      // The left/right shoulder-hip-knee angle genuinely diverges past the
      // threshold on some reps, so the imbalance flag is real.
      expect(run.issues, contains('Uneven Sides'));
    });
  });

  group('Jumping Jack, real footage', () {
    test('jumping jack clip 292741 counts 7 reps, two with genuinely uneven arms', () {
      final analyzer = JumpingJackAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('jumpingJack_pixabay_292741');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      expect(analyzer.repCount, 7);
      // Reps 2 and 3 carry a real 'Uneven Arms' flag (0.85 each) -- the two
      // arms' hip-shoulder-elbow angles genuinely diverge past the threshold on
      // those specific reps, recovering from rep 4 onward.
      expect(analyzer.repScores, [1.0, 0.85, 0.85, 1.0, 1.0, 1.0, 1.0]);
    });

    test('continuous rhythmic jumping jacks with bouncing rest arms complete reps', () {
      final analyzer = JumpingJackAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('jumpingJack_pixabay_84375');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // During rapid continuous jacks, arms descend to 50-55 degrees at the bottom.
      // Requiring <= 45 degrees stalled concentric phase. Hardened rest angle counts 5 reps.
      expect(analyzer.repCount, 5);
      expect(analyzer.repScores.length, 5);
    });
  });

  group('Wall Sit, real footage', () {
    test('wall sit hold duration is tracked and scored', () {
      var simulatedTime = DateTime(2026, 9, 10, 12, 0, 0);
      final analyzer = WallSitAnalyzer(clock: () => simulatedTime);
      final frames = RecordedPoseFixtures.loadSequence('wallSit_pexels_6454275');

      for (final pose in frames) {
        simulatedTime = simulatedTime.add(const Duration(milliseconds: 33));
        analyzer.processPose(pose);
      }

      expect(analyzer.heldSeconds, greaterThanOrEqualTo(5));
      expect(analyzer.repRecords, isNotEmpty);
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
