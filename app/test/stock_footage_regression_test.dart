import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_orientation.dart';

import 'support/recorded_pose_fixtures.dart';

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

    test(
        'a front-facing squat never closes a rep, regardless of depth, but '
        'the analyzer correctly tells the athlete to turn side-on', () {
      final analyzer = SquatAnalyzer();
      final corrections = <String>[];
      analyzer.onCorrection = corrections.add;
      final frames = RecordedPoseFixtures.loadSequence('squat_pexels_4764175');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      expect(analyzer.repCount, 0);
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      expect(analyzer.orientationTracker.orientation, ViewOrientation.frontOn);
      expect(
        corrections.any((message) => message.toLowerCase().contains('side')),
        isTrue,
        reason: 'The athlete should be told to turn side-on, since their '
            'reps otherwise silently never count.',
      );
    });
  });

  group('Pushup, real footage', () {
    test('a real set of push-ups is counted correctly', () {
      final analyzer = PushupAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('pushup_pexels_4367576');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      expect(analyzer.repCount, 4);
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      for (final score in analyzer.repScores) {
        expect(score, inInclusiveRange(0.0, 1.0));
      }
    });

    test('genuine depth and lockout do not receive false penalties from tremor', () {
      final analyzer = PushupAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('pushup_pixabay_302251');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // Athlete reaches 78 degrees depth (<= 90) and locks out to 165 degrees (>= 155).
      // Descent or ascent tremors must not leave persistent Insufficient Depth or
      // Incomplete Lockout penalties once depth and lockout are reached.
      expect(analyzer.repCount, 1);
      expect(analyzer.repScores.first, 1.0);
      expect(analyzer.allRepIssues.first, isEmpty);
    });
  });

  group('Lunge, real footage', () {
    test('split/stationary lunge with bent rear knee does not deadlock in concentric', () {
      final analyzer = LungeAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('lunge_pexels_8171292');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // In stationary/split lunges, the rear knee stays bent (reading ~121 degrees),
      // so min(leftKnee, rightKnee) never reaches 160 degrees. Tracking the
      // standing leg allows the concentric phase to complete cleanly.
      expect(analyzer.repCount, 3);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
    });

    test('alternating lunge counts completed reps cleanly', () {
      final analyzer = LungeAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('lunge_pexels_4488004');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      expect(analyzer.repCount, 3);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
    });
  });

  group('Overhead Press, real footage', () {
    test('set of 5 full overhead presses counted cleanly with realistic lockout', () {
      final analyzer = OverheadPressAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('overheadPress_pexels_4367541');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // Athlete presses to 152-165 degrees overhead lockout across 5 reps.
      // Requiring 165 degrees caused reps 2-5 to stall in concentric.
      // Threshold hardened to 152 degrees recognizes all 5 reps cleanly.
      expect(analyzer.repCount, 5);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
    });

    test('press failing to achieve overhead lockout does not count reps', () {
      final analyzer = OverheadPressAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('overheadPress_pexels_32239223');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // Elbow angle tops out at 144 degrees (< 152 threshold), so no full reps count.
      expect(analyzer.repCount, 0);
      expect(analyzer.statusMessage, 'Reach higher');
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

    test('situp clip 296446 counts 2 clean reps', () {
      final analyzer = SitupAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('situp_pixabay_296446');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      expect(analyzer.repCount, 2);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
    });
  });

  group('Jumping Jack, real footage', () {
    test('jumping jack clip 292741 counts 7 clean reps', () {
      final analyzer = JumpingJackAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('jumpingJack_pixabay_292741');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      expect(analyzer.repCount, 7);
      for (final score in analyzer.repScores) {
        expect(score, 1.0);
      }
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
