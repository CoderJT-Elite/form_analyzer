import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_framing.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'support/recorded_pose_fixtures.dart';

/// Drives [PoseFraming.isInFrame] with landmark sequences extracted from real
/// stock exercise footage across all 10 exercises and 25 clips, using each clip's
/// genuine pixel resolution so edge-margin and presence math runs in real space.
///
/// Findings & Architecture:
/// 1. Bilateral Joint Grouping:
///    Grouping bilateral landmarks into joints ensures that single-side occlusion
///    during side-on filming or mid-rep motion does not cause false "step back" cues.
/// 2. Decoupled Presence vs. Precision Threshold:
///    Framing presence detection uses [PoseFraming.framingVisibilityThreshold] (0.5),
///    decoupled from [AppConstants.visibilityThreshold] (0.7). This prevents
///    transient tracking noise from failing framing for fully-framed athletes while
///    preserving 0.7 for high-precision joint angle rep counting.
/// 3. Visual Ground Truth for Cropped Footage:
///    Visual frame extraction confirmed clips like `squat_pixabay_148204`,
///    `pushup_pixabay_143431`, and `plank_pexels_7117437` are tight close-ups where
///    limbs are physically cropped outside the camera frame ($x < 0, y < 0$ or off-edge).
///    Rejecting these clips (< 50% in-frame) is correct and expected behavior.
void main() {
  group('Well-framed real footage across all 10 exercises maintains high in-frame rate', () {
    test('Glute Bridge: both clips stay 100% in-frame', () {
      final analyzer = GluteBridgeAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('gluteBridge_pexels_4267359');
      expect(_inFrameFraction(f1, req, const Size(3840, 2160)), equals(1.0));

      final f2 = RecordedPoseFixtures.loadSequence('gluteBridge_pexels_6525487');
      expect(_inFrameFraction(f2, req, const Size(1920, 1080)), equals(1.0));
    });

    test('Jumping Jack: both front-on clips maintain >= 95% in-frame', () {
      final analyzer = JumpingJackAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('jumpingJack_pixabay_292741');
      expect(_inFrameFraction(f1, req, const Size(3840, 2160)), equals(1.0));

      final f2 = RecordedPoseFixtures.loadSequence('jumpingJack_pixabay_84375');
      expect(_inFrameFraction(f2, req, const Size(1920, 1080)), greaterThanOrEqualTo(0.95));
    });

    test('Lunge: well-framed vertical clip stays 100% in-frame', () {
      final analyzer = LungeAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('lunge_pexels_4488004');
      expect(_inFrameFraction(f1, req, const Size(1080, 1920)), equals(1.0));
    });

    test('Overhead Press: front and side angles maintain >= 75% in-frame', () {
      final analyzer = OverheadPressAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('overheadPress_pexels_32239223');
      expect(_inFrameFraction(f1, req, const Size(3840, 2160)), equals(1.0));

      final f2 = RecordedPoseFixtures.loadSequence('overheadPress_pexels_4367541');
      expect(_inFrameFraction(f2, req, const Size(1280, 720)), greaterThanOrEqualTo(0.75));
    });

    test('Plank: well-framed horizontal and vertical clips stay 100% in-frame', () {
      final analyzer = PlankAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('plank_pexels_4945589');
      expect(_inFrameFraction(f1, req, const Size(4096, 2160)), equals(1.0));

      final f2 = RecordedPoseFixtures.loadSequence('plank_pexels_6525477');
      expect(_inFrameFraction(f2, req, const Size(1080, 1920)), equals(1.0));
    });

    test('Push-up: clean side-on and floor-angle clips maintain >= 95% in-frame', () {
      final analyzer = PushupAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('pushup_pexels_4367576');
      expect(_inFrameFraction(f1, req, const Size(640, 360)), equals(1.0));

      final f2 = RecordedPoseFixtures.loadSequence('pushup_pixabay_302251');
      expect(_inFrameFraction(f2, req, const Size(3840, 2160)), greaterThanOrEqualTo(0.95));
    });

    test('Sit-up: all 3 clips stay >= 75% in-frame', () {
      final analyzer = SitupAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('situp_pixabay_293079');
      expect(_inFrameFraction(f1, req, const Size(1920, 1080)), greaterThanOrEqualTo(0.95));

      // SitupAnalyzer now also tracks ankles (for the 'Straight Legs' form
      // check added alongside the feedback-depth work), which lowers this
      // clip's rate slightly from the pre-ankle 80%+ since ankle visibility
      // now also counts toward the in-frame joint fraction.
      final f2 = RecordedPoseFixtures.loadSequence('situp_pixabay_296446');
      expect(_inFrameFraction(f2, req, const Size(3840, 2160)), greaterThanOrEqualTo(0.75));

      final f3 = RecordedPoseFixtures.loadSequence('situp_pixabay_84706');
      expect(_inFrameFraction(f3, req, const Size(1920, 1080)), greaterThanOrEqualTo(0.99));
    });

    test('Squat: well-framed clips stay 100% in-frame', () {
      final analyzer = SquatAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('squat_pexels_4764175');
      expect(_inFrameFraction(f1, req, const Size(360, 640)), equals(1.0));

      final f2 = RecordedPoseFixtures.loadSequence('squat_pexels_8837221');
      expect(_inFrameFraction(f2, req, const Size(226, 426)), equals(1.0));
    });

    test('Wall Sit: seated and wall-mounted clips maintain >= 80% in-frame', () {
      final analyzer = WallSitAnalyzer();
      final req = analyzer.activeLandmarkTypes;

      final f1 = RecordedPoseFixtures.loadSequence('wallSit_pexels_6454275');
      expect(_inFrameFraction(f1, req, const Size(2160, 3840)), greaterThanOrEqualTo(0.80));

      final f2 = RecordedPoseFixtures.loadSequence('wallSit_pexels_8402078');
      expect(_inFrameFraction(f2, req, const Size(1920, 1080)), equals(1.0));
    });
  });

  group('Threshold decoupling recovers clips with minor tracking noise', () {
    test('pushup_pixabay_302251 stays well in-frame at both thresholds', () {
      final analyzer = PushupAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('pushup_pixabay_302251');
      const size = Size(3840, 2160);

      // PushupAnalyzer now also tracks hip/knee (for the 'Hips Sagging'/'Hips
      // Piked' form check added alongside the feedback-depth work). Those
      // landmarks track confidently on this clip throughout, which raised
      // the strict-threshold rate from the original 76.3% (measured with
      // only shoulder/elbow/wrist required) well above where the original
      // 0.5-vs-0.7 decoupling comparison this test demonstrated was based.
      final rateStrict = _inFrameFraction(
        frames,
        analyzer.activeLandmarkTypes,
        size,
        minLikelihood: 0.7,
      );
      expect(rateStrict, greaterThanOrEqualTo(0.95));

      final rateDecoupled = _inFrameFraction(
        frames,
        analyzer.activeLandmarkTypes,
        size,
      );
      expect(rateDecoupled, greaterThanOrEqualTo(0.95));
    });

    test('lunge_pexels_8171292 improves from 58.8% to >= 70% with decoupled threshold', () {
      final analyzer = LungeAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('lunge_pexels_8171292');
      const size = Size(3840, 2160);

      final rateStrict = _inFrameFraction(
        frames,
        analyzer.activeLandmarkTypes,
        size,
        minLikelihood: 0.7,
      );
      expect(rateStrict, closeTo(0.588, 0.01));

      final rateDecoupled = _inFrameFraction(
        frames,
        analyzer.activeLandmarkTypes,
        size,
      );
      expect(rateDecoupled, greaterThanOrEqualTo(0.70));
    });

    test('overheadPress_pexels_32239223 achieves 100% in-frame with decoupled threshold', () {
      final analyzer = OverheadPressAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('overheadPress_pexels_32239223');
      const size = Size(3840, 2160);

      final rateDecoupled = _inFrameFraction(
        frames,
        analyzer.activeLandmarkTypes,
        size,
      );
      expect(rateDecoupled, equals(1.0));
    });
  });

  group('Genuinely cropped footage is correctly rejected as not in-frame', () {
    test('squat_pixabay_148204 is cropped at calves/ankles and rejected (< 15% in-frame)', () {
      // Visual inspection confirms tight smith machine close-up cropped above ankles.
      final analyzer = SquatAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('squat_pixabay_148204');
      final fraction = _inFrameFraction(
        frames,
        analyzer.activeLandmarkTypes,
        const Size(3840, 2160),
      );
      expect(fraction, lessThan(0.15));
    });

    test('plank_pexels_7117437 has legs/feet extending off-frame and is rejected (< 20% in-frame)', () {
      // High-angle shot where lower body extends off bottom edge.
      final analyzer = PlankAnalyzer();
      final frames = RecordedPoseFixtures.loadSequence('plank_pexels_7117437');
      final fraction = _inFrameFraction(
        frames,
        analyzer.activeLandmarkTypes,
        const Size(2160, 4096),
      );
      expect(fraction, lessThan(0.20));
    });

    test('pushup_pixabay_143431 & 58984 have shoulders/arms cropped off top border (< 50% in-frame)', () {
      final analyzer = PushupAnalyzer();

      final f1 = RecordedPoseFixtures.loadSequence('pushup_pixabay_143431');
      expect(_inFrameFraction(f1, analyzer.activeLandmarkTypes, const Size(1920, 1080)), lessThan(0.50));

      final f2 = RecordedPoseFixtures.loadSequence('pushup_pixabay_58984');
      expect(_inFrameFraction(f2, analyzer.activeLandmarkTypes, const Size(1920, 1080)), lessThan(0.50));
    });
  });

  group('Boundary-grazing footage is accurately detected', () {
    test('sidePlank clips stay well in-frame with the fuller landmark set', () {
      final analyzer = SidePlankAnalyzer();

      // SidePlankAnalyzer now also tracks elbow/knee (for the 'Elbows Not
      // Under Shoulders'/'Bent Knees' form checks added alongside the
      // feedback-depth work). These clips do briefly touch the edge margin
      // during lift/repositioning (originally measured at ~40-60% in-frame
      // with only shoulder/hip/ankle required), but the added joints are
      // reliably tracked through those same stretches, raising the overall
      // rate well above the original narrower-landmark-set measurement.
      final f1 = RecordedPoseFixtures.loadSequence('sidePlank_pexels_6023264');
      final rate1 = _inFrameFraction(f1, analyzer.activeLandmarkTypes, const Size(3840, 2160));
      expect(rate1, greaterThanOrEqualTo(0.9));

      final f2 = RecordedPoseFixtures.loadSequence('sidePlank_pexels_6023265');
      final rate2 = _inFrameFraction(f2, analyzer.activeLandmarkTypes, const Size(3840, 2160));
      expect(rate2, greaterThanOrEqualTo(0.9));
    });
  });
}

double _inFrameFraction(
  List<Pose> frames,
  Set<PoseLandmarkType> requiredLandmarks,
  Size imageSize, {
  double minLikelihood = PoseFraming.framingVisibilityThreshold,
}) {
  var inFrameCount = 0;
  for (final pose in frames) {
    if (PoseFraming.isInFrame(
      pose: pose,
      requiredLandmarks: requiredLandmarks,
      imageSize: imageSize,
      minLikelihood: minLikelihood,
    )) {
      inFrameCount++;
    }
  }
  return inFrameCount / frames.length;
}
