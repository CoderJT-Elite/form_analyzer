import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/logic/gravity_frame.dart';
import 'package:form_analyzer/ui/widgets/pose_painter.dart';

/// The skeleton must land on the person whichever way the phone is turned: a
/// point in the world has one screen position no matter which rotation ML Kit
/// was asked to detect in.
void main() {
  const raw = Size(640, 480);
  const widget = Size(360, 480);

  for (final front in [true, false]) {
    for (final sensor in [90, 270]) {
      test('${front ? "front" : "back"} camera, sensor $sensor: same screen point at every rotation', () {
        final previewRotation = InputImageRotationValue.fromRawValue(sensor)!;
        final previewSize = PoseCoordinates.frameSize(raw, previewRotation);
        final lens = front ? CameraLensDirection.front : CameraLensDirection.back;

        // Where the point lands with the phone upright (rotation == preview).
        PosePainter painter(InputImageRotation rotation) => PosePainter(
              poses: const [],
              imageSize: raw,
              rotation: rotation,
              previewRotation: previewRotation,
              lensDirection: lens,
            );

        const px = 150.0, py = 90.0; // in the sensor-upright frame
        final expected = painter(previewRotation).transformPoint(px, py, widget);

        for (var n = 0; n < 4; n++) {
          final rotation = InputImageRotationValue.fromRawValue((sensor + 90 * n) % 360)!;
          final (qx, qy, _, _) =
              PoseCoordinates.rotateClockwise(px, py, previewSize.width, previewSize.height, n);
          final got = painter(rotation).transformPoint(qx, qy, widget);
          expect(got.dx, closeTo(expected.dx, 1e-6), reason: 'turns $n');
          expect(got.dy, closeTo(expected.dy, 1e-6), reason: 'turns $n');
        }
      });
    }
  }
}
