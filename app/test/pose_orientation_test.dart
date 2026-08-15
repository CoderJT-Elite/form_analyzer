import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_constants.dart';
import 'package:form_analyzer/logic/pose_orientation.dart';

import 'support/pose_fixtures.dart';

void main() {
  group('PoseOrientation.detect', () {
    test('wide shoulders and hips read as facing the camera', () {
      final pose = PoseFixtures.torso(shoulderWidth: 120, hipWidth: 100,
          torsoHeight: 160);

      expect(PoseOrientation.detect(pose), ViewOrientation.frontOn);
    });

    test('collapsed width reads as a side view', () {
      // In profile the left and right landmarks nearly coincide.
      final pose = PoseFixtures.torso(shoulderWidth: 20, hipWidth: 16,
          torsoHeight: 160);

      expect(PoseOrientation.detect(pose), ViewOrientation.sideOn);
    });

    test('a three-quarter angle is reported as unknown, not guessed', () {
      final midRatio = (AppConstants.sideOnMaxWidthRatio +
              AppConstants.frontOnMinWidthRatio) /
          2;
      final width = midRatio * 160;
      final pose = PoseFixtures.torso(
        shoulderWidth: width,
        hipWidth: width,
        torsoHeight: 160,
      );

      expect(PoseOrientation.detect(pose), ViewOrientation.unknown);
    });

    test('missing landmarks give unknown rather than a false reading', () {
      expect(PoseOrientation.detect(PoseFixtures.empty()),
          ViewOrientation.unknown);
    });

    test('low-confidence landmarks give unknown', () {
      final pose = PoseFixtures.torso(
        shoulderWidth: 120,
        hipWidth: 100,
        torsoHeight: 160,
        likelihood: 0.2,
      );

      expect(PoseOrientation.detect(pose), ViewOrientation.unknown);
    });

    test('the reading is independent of how far away the athlete stands', () {
      final near = PoseFixtures.torso(
          shoulderWidth: 240, hipWidth: 200, torsoHeight: 320);
      final far = PoseFixtures.torso(
          shoulderWidth: 60, hipWidth: 50, torsoHeight: 80);

      expect(PoseOrientation.detect(near), PoseOrientation.detect(far));
    });
  });

  group('OrientationTracker', () {
    test('does not flip on a single noisy frame', () {
      final tracker = OrientationTracker();
      final sideOn =
          PoseFixtures.torso(shoulderWidth: 20, hipWidth: 16, torsoHeight: 160);
      final frontOn = PoseFixtures.torso(
          shoulderWidth: 120, hipWidth: 100, torsoHeight: 160);

      for (var i = 0; i < AppConstants.orientationDebounceFrames + 2; i++) {
        tracker.update(sideOn);
      }
      expect(tracker.orientation, ViewOrientation.sideOn);

      tracker.update(frontOn);
      expect(tracker.orientation, ViewOrientation.sideOn,
          reason: 'One stray frame must not trigger a "turn around" cue.');
    });

    test('flips once the new orientation is sustained', () {
      final tracker = OrientationTracker();
      final sideOn =
          PoseFixtures.torso(shoulderWidth: 20, hipWidth: 16, torsoHeight: 160);
      final frontOn = PoseFixtures.torso(
          shoulderWidth: 120, hipWidth: 100, torsoHeight: 160);

      for (var i = 0; i < 10; i++) {
        tracker.update(sideOn);
      }
      for (var i = 0; i < AppConstants.orientationDebounceFrames + 1; i++) {
        tracker.update(frontOn);
      }

      expect(tracker.orientation, ViewOrientation.frontOn);
    });

    test('reset returns to unknown', () {
      final tracker = OrientationTracker();
      final sideOn =
          PoseFixtures.torso(shoulderWidth: 20, hipWidth: 16, torsoHeight: 160);

      for (var i = 0; i < 10; i++) {
        tracker.update(sideOn);
      }
      tracker.reset();

      expect(tracker.orientation, ViewOrientation.unknown);
    });
  });
}
