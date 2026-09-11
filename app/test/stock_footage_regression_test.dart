import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_orientation.dart';

import 'support/recorded_pose_fixtures.dart';

/// Drives the real, unmodified analyzers with landmark sequences extracted
/// from real stock exercise footage via MediaPipe Pose (see
/// tools/extract_pose_fixtures.py), instead of only the hand-authored,
/// idealized angle sweeps in pose_fixtures.dart / analyzer_behavior_test.dart.
///
/// MediaPipe is a stand-in for ML Kit's pose model -- close enough
/// anatomically to drive the same rep-counting/scoring logic, but not a
/// guarantee ML Kit's own output looks identical on a real device.
///
/// The expected counts below were derived by tracing each analyzer's actual
/// `lastProcessedAngle`/`squatState`/`phase` frame-by-frame against the real
/// data (not by eyeballing the source video and assuming the app must agree)
/// -- an earlier version of this file got several things wrong that way, all
/// fixed along with SquatAnalyzer.processPose itself:
///   1. Zeroing landmark Z during extraction "to be safe" silently forced
///      MathUtils into 2D-only angle math (see
///      MathUtils._hasReliableZCoordinates). For a front-facing camera, knee
///      flexion happens mostly in depth, so a genuinely deep squat measured
///      as barely bending -- fixed by carrying MediaPipe's real Z through
///      (see extract_pose_fixtures.py).
///   2. Sampling at 10fps missed the true bottom of fast reps -- fixed by
///      sampling at the source frame rate.
///   3. SquatAnalyzer's depth check compared against an angle that had been
///      through two stages of smoothing (a per-landmark exponential filter,
///      then a 5-frame moving average). A fast rep's true bottom can survive
///      neither: real footage showed a rep that hit 61-66 degrees at its
///      truly deepest frame read as high as 100 degrees post-smoothing,
///      missing squatDepthThreshold despite genuinely reaching depth. Fixed
///      by checking depth against the unsmoothed landmarks directly -- depth
///      is a one-shot "did they ever get there" check, not something that
///      benefits from temporal stability the way the eccentric/concentric
///      direction-reversal check does.
///   4. That depth check also picked a leg by ML Kit's confidence score, on
///      the assumption the more confident leg is the more accurate one. Real
///      footage showed the opposite for a full rep: the higher-confidence
///      leg read 100-160 degrees for its entire duration while the other
///      leg (still comfortably above the visibility threshold) read 66-95
///      degrees for the same frames. A squat's depth is bilaterally
///      symmetric, so a confidence gap between the two sides reflects
///      estimation error, not anatomy -- fixed by taking whichever visible
///      leg reads deeper for the depth check specifically, while the primary
///      display angle still picks by confidence for a stable single reading.
void main() {
  group('Squat, real footage', () {
    test('a side-on set of 5 real squats is counted correctly', () {
      final analyzer = SquatAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('squat_pexels_8837221');

      for (final pose in frames) {
        analyzer.processPose(pose);
      }

      // The raw knee angle dips below 90 degrees in all 5 reps in this clip
      // (as low as 44-70 degrees at the true minimum). All 5 are now
      // detected, each triggering "Great depth, stand up" promptly after the
      // eccentric phase begins rather than missing depth or triggering late.
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

      // This clip is filmed front-on rather than side-on. The athlete does
      // go deep -- the 3D knee angle bottoms out around 32-35 degrees, well
      // past the depth threshold -- but SquatAnalyzer.processPose closes a
      // rep by requiring the SAME hip-knee-ankle angle to climb back to
      // AppConstants.squatNeutralThreshold (160) while "standing". From this
      // camera's perspective, MediaPipe's 3D reconstruction of a standing
      // pose never reads above ~146-149 degrees, so the state machine can
      // never transition back to neutral and no rep is ever counted -- not
      // because the depth was insufficient, but because this camera angle
      // can't produce a "fully extended" reading the app recognizes at all.
      expect(analyzer.repCount, 0);
      expect(analyzer.statusMessage, isNot('Adjust Camera'));

      // This isn't a silent failure, though: updateOrientation (called
      // unconditionally every frame, independent of the exercise-specific
      // checks below it) already detects the front-on framing via
      // PoseOrientation's width-to-height ratio -- a pure 2D measurement,
      // unaffected by the Z-accuracy issues above -- and fires the same
      // "turn side-on" cue the back-angle safety check relies on, repeating
      // every 5 seconds (CueIds.turnSideOn's cooldown) for as long as the
      // athlete stays front-on. No code change was needed for this part.
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

      // Filmed from an angle where both the depth dip (elbow angle to
      // ~63-79 degrees) and the lockout recovery (~160-171 degrees) survive
      // the smoothing pipeline cleanly across all four visible push-ups, so
      // this one didn't need the same depth-check fix as SquatAnalyzer.
      expect(analyzer.repCount, 4);
      expect(analyzer.statusMessage, isNot('Adjust Camera'));
      for (final score in analyzer.repScores) {
        expect(score, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
