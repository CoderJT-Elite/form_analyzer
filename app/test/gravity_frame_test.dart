import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/logic/gravity_frame.dart';

/// Accelerometer reaction (device axes: x right, y up the screen) for a phone
/// rotated [degrees] counter-clockwise from upright, i.e. Android's
/// Surface.ROTATION_0/90/180/270.
(double, double) reading(int degrees, {double g = 9.81}) => switch (degrees) {
      0 => (0.0, g),
      90 => (g, 0.0),
      180 => (0.0, -g),
      270 => (-g, 0.0),
      _ => throw ArgumentError(degrees),
    };

/// The rotation Android's camera documentation prescribes for ML Kit given the
/// display rotation. Written independently of the implementation under test.
int documentedRotation({
  required int sensorOrientation,
  required int displayRotation,
  required bool front,
}) =>
    front
        ? (sensorOrientation + displayRotation) % 360
        : (sensorOrientation - displayRotation + 360) % 360;

void main() {
  group('detection rotation matches the documented compensation', () {
    for (final front in [true, false]) {
      for (final sensor in [90, 270]) {
        for (final rot in [0, 90, 180, 270]) {
          test('${front ? "front" : "back"} camera, sensor $sensor, phone rotated $rot', () {
            final (ax, ay) = reading(rot);
            final e = DeviceGravity.estimate(
              ax: ax,
              ay: ay,
              frontCamera: front,
              sensorOrientation: sensor,
            )!;
            expect(
              e.detectionRotation.rawValue,
              documentedRotation(sensorOrientation: sensor, displayRotation: rot, front: front),
            );
            // Whatever the quadrant, gravity ends up pointing (about) down.
            expect(e.residual.x.abs(), lessThan(0.01));
            expect(e.residual.y, closeTo(1, 0.01));
          });
        }
      }
    }
  });

  group('tilt within a quadrant', () {
    test('a phone leaning 20 degrees leaves a 20 degree residual, not a new quadrant', () {
      final a = 20 * math.pi / 180;
      final e = DeviceGravity.estimate(
        ax: 9.81 * math.sin(a),
        ay: 9.81 * math.cos(a),
        frontCamera: false,
        sensorOrientation: 90,
      )!;
      expect(e.quarterTurns, 0);
      expect(e.residual.tiltDegrees, closeTo(20, 0.5));
    });

    test('hysteresis: stays in the previous quadrant until 60 degrees away', () {
      DeviceGravity.estimate(ax: 0, ay: 9.81, frontCamera: false, sensorOrientation: 90);
      GravityEstimate at(double degreesFromUpright, int previous) {
        final a = degreesFromUpright * math.pi / 180;
        return DeviceGravity.estimate(
          ax: 9.81 * math.sin(a),
          ay: 9.81 * math.cos(a),
          frontCamera: false,
          sensorOrientation: 90,
          previousQuarterTurns: previous,
        )!;
      }

      // 50 degrees is past the 45 degree boundary but inside the hysteresis band.
      expect(at(50, 0).quarterTurns, 0);
      // 70 degrees is not.
      expect(at(70, 0).quarterTurns, isNot(0));
      // And coming back needs the same margin: at 40 degrees from upright the
      // phone is still 50 from the other quadrant, so it stays put...
      final flipped = at(70, 0).quarterTurns;
      expect(at(40, flipped).quarterTurns, flipped);
      // ...until it is well back.
      expect(at(25, flipped).quarterTurns, 0);
    });

    test('a phone lying flat gives no estimate', () {
      expect(
        DeviceGravity.estimate(ax: 0.4, ay: 0.6, frontCamera: true, sensorOrientation: 270),
        isNull,
      );
    });
  });

  group('GravityFrame', () {
    test('upright is the identity', () {
      expect(GravityFrame.upright.isUpright, isTrue);
      final (u, v) = GravityFrame.upright.toGravityAligned(30, 70);
      expect(u, 30);
      expect(v, 70);
    });

    test('a displacement along gravity becomes +y', () {
      // Gravity points toward image-left: moving left is "down".
      const g = GravityFrame(-1, 0);
      final (u, v) = g.toGravityAligned(-5, 0);
      expect(u, closeTo(0, 1e-9));
      expect(v, closeTo(5, 1e-9));
    });

    test('is a proper rotation: distances and angles are preserved', () {
      const g = GravityFrame(0.6, 0.8);
      final (u1, v1) = g.toGravityAligned(10, 0);
      final (u2, v2) = g.toGravityAligned(0, 10);
      expect(math.sqrt(u1 * u1 + v1 * v1), closeTo(10, 1e-9));
      expect(u1 * u2 + v1 * v2, closeTo(0, 1e-9));
      // Right-handed stays right-handed (no mirroring).
      expect(u1 * v2 - v1 * u2, greaterThan(0));
    });
  });

  group('pose coordinates', () {
    const raw = Size(640, 480);

    test('frame size swaps for quarter turns', () {
      expect(PoseCoordinates.frameSize(raw, InputImageRotation.rotation0deg), raw);
      expect(PoseCoordinates.frameSize(raw, InputImageRotation.rotation180deg), raw);
      expect(PoseCoordinates.frameSize(raw, InputImageRotation.rotation90deg), const Size(480, 640));
      expect(PoseCoordinates.frameSize(raw, InputImageRotation.rotation270deg), const Size(480, 640));
    });

    test('rotating clockwise four times is the identity', () {
      final (x, y, w, h) = PoseCoordinates.rotateClockwise(100, 40, 640, 480, 4);
      expect((x, y, w, h), (100.0, 40.0, 640.0, 480.0));
    });

    test('a clockwise quarter turn sends the top-left corner to the top-right', () {
      final (x, y, w, h) = PoseCoordinates.rotateClockwise(0, 0, 640, 480, 1);
      expect((x, y, w, h), (480.0, 0.0, 480.0, 640.0));
    });

    test('a point round-trips from any detection rotation back to the preview frame', () {
      // A world point in the sensor-upright frame; build the coordinates ML Kit
      // would report if the image were turned n quarter turns further, then
      // check they map back.
      for (final sensor in [90, 270]) {
        final previewRotation = InputImageRotationValue.fromRawValue(sensor)!;
        final previewSize = PoseCoordinates.frameSize(raw, previewRotation);
        for (var n = 0; n < 4; n++) {
          final poseRotation = InputImageRotationValue.fromRawValue((sensor + 90 * n) % 360)!;
          const px = 123.0, py = 77.0;
          final (qx, qy, _, _) =
              PoseCoordinates.rotateClockwise(px, py, previewSize.width, previewSize.height, n);
          final (bx, by) = PoseCoordinates.toPreviewFrame(
            x: qx,
            y: qy,
            rawImage: raw,
            poseRotation: poseRotation,
            previewRotation: previewRotation,
          );
          expect(bx, closeTo(px, 1e-9), reason: 'sensor $sensor turns $n');
          expect(by, closeTo(py, 1e-9), reason: 'sensor $sensor turns $n');
        }
      }
    });

    test('the same rotation on both sides is a no-op', () {
      final (x, y) = PoseCoordinates.toPreviewFrame(
        x: 50,
        y: 60,
        rawImage: raw,
        poseRotation: InputImageRotation.rotation270deg,
        previewRotation: InputImageRotation.rotation270deg,
      );
      expect((x, y), (50.0, 60.0));
    });
  });
}
