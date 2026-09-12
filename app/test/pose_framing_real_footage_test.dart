import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_framing.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'support/recorded_pose_fixtures.dart';

/// Drives [PoseFraming.isInFrame] with landmark sequences extracted from real
/// stock exercise footage (see stock_footage_regression_test.dart) instead of
/// only hand-built poses, using each clip's real resolution so the edge-margin
/// math runs in genuine pixel space.
///
/// This caught a real bug: the original implementation required 80% of ALL
/// required landmarks -- both left and right -- to be individually visible.
/// Side-on filming (or mid-rep occlusion, e.g. the trailing leg of a squat)
/// routinely drops one side's confidence below threshold even though the
/// athlete is perfectly framed, which produced false "step back" prompts on
/// several real clips (measured 0-2% "in frame" before the fix). The fix
/// groups landmarks into side-agnostic joints and only requires one side of
/// each joint to be visible -- the same bilateral-extremum principle already
/// used by SquatAnalyzer/OverheadPressAnalyzer/etc.
void main() {
  group('Well-framed real footage should not trigger false "step back" cues', () {
    test('front-on jumping jacks stay in frame throughout', () {
      final frames = RecordedPoseFixtures.loadSequence('jumpingJack_pixabay_292741');
      final analyzer = JumpingJackAnalyzer();
      const imageSize = Size(3840, 2160);

      final inFrameFraction = _inFrameFraction(frames, analyzer.activeLandmarkTypes, imageSize);

      expect(inFrameFraction, greaterThanOrEqualTo(0.95));
    });

    test('a clean side-on squat set stays in frame throughout', () {
      final frames = RecordedPoseFixtures.loadSequence('squat_pexels_8837221');
      final analyzer = SquatAnalyzer();
      const imageSize = Size(226, 426);

      final inFrameFraction = _inFrameFraction(frames, analyzer.activeLandmarkTypes, imageSize);

      expect(inFrameFraction, greaterThanOrEqualTo(0.95));
    });

    test('a side-on push-up set is not falsely flagged despite the trailing '
        'arm/leg being partly occluded from this angle', () {
      final frames = RecordedPoseFixtures.loadSequence('pushup_pexels_4367576');
      final analyzer = PushupAnalyzer();
      const imageSize = Size(640, 360);

      final inFrameFraction = _inFrameFraction(frames, analyzer.activeLandmarkTypes, imageSize);

      // Before the bilateral-joint fix this clip measured 58% (frequent false
      // "step back" prompts); the far arm being less confident than the near
      // arm during a push-up is normal and must not read as bad framing.
      expect(inFrameFraction, greaterThanOrEqualTo(0.95));
    });

    test('an overhead press set is not falsely flagged by single-arm tracking dips', () {
      final frames = RecordedPoseFixtures.loadSequence('overheadPress_pexels_32239223');
      final analyzer = OverheadPressAnalyzer();
      const imageSize = Size(3840, 2160);

      final inFrameFraction = _inFrameFraction(frames, analyzer.activeLandmarkTypes, imageSize);

      // Measured 77.8% before the fix (one arm's confidence dipping below
      // threshold counted against both), 91.3% after.
      expect(inFrameFraction, greaterThanOrEqualTo(0.85));
    });
  });

  group('Known real-footage limitation (documented, not asserted as passing)', () {
    test('a distant/low-confidence squat clip is NOT reliably read as in-frame', () {
      // MediaPipe's knee/ankle confidence for this clip stays chronically low
      // (means ~0.44 and ~0.25) throughout -- not because those landmarks are
      // near an edge, but because the subject is small/distant in a 4K frame.
      // isInFrame() still gates on AppConstants.visibilityThreshold, so this
      // reads as "not in frame" and the app would say "step back", which is
      // the wrong direction of advice for a too-far-away subject. Fixing this
      // needs a deliberate decision about decoupling confidence from framing
      // (a real tradeoff: loosen it and genuine cropping may go undetected) --
      // flagged for a follow-up decision rather than changed unilaterally here.
      final frames = RecordedPoseFixtures.loadSequence('squat_pixabay_148204');
      final analyzer = SquatAnalyzer();
      const imageSize = Size(3840, 2160);

      final inFrameFraction = _inFrameFraction(frames, analyzer.activeLandmarkTypes, imageSize);

      expect(inFrameFraction, lessThan(0.5));
    });
  });
}

double _inFrameFraction(
  List<Pose> frames,
  Set<PoseLandmarkType> requiredLandmarks,
  Size imageSize,
) {
  var inFrameCount = 0;
  for (final pose in frames) {
    if (PoseFraming.isInFrame(
      pose: pose,
      requiredLandmarks: requiredLandmarks,
      imageSize: imageSize,
    )) {
      inFrameCount++;
    }
  }
  return inFrameCount / frames.length;
}
