/// Which way is down, as the pose detector sees it.
///
/// The app is locked to portrait, but people put a phone on the floor on its
/// side to film a plank or a sit-up (5 of the 10 sets in live test #3). Nothing
/// downstream knew: "hips too low" is a statement about gravity, and joint
/// angles of a body lying across the image are judged very differently by the
/// pose model than the upright people it was trained on.
///
/// This file is pure geometry with no plugin dependencies, so it can be tested
/// exhaustively. `DeviceGravityService` feeds it accelerometer readings.
///
/// Conventions (all images: x to the right, y down):
///   * The *sensor-upright frame* is the camera image rotated by the camera's
///     sensor orientation, i.e. what a phone held upright in portrait shows.
///   * ML Kit's `rotation` is the number of degrees clockwise the raw image must
///     be turned to be upright for the model. Pose coordinates come back in that
///     rotated frame.
///   * The accelerometer reports the *reaction* to gravity, in device axes
///     (x right, y up the screen): +y when held upright.
library;

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Gravity's direction in the coordinates poses are reported in.
class GravityFrame {
  const GravityFrame(this.x, this.y);

  /// Phone held upright: gravity points straight down the image.
  static const GravityFrame upright = GravityFrame(0, 1);

  /// Unit vector, x to the right and y down.
  final double x;
  final double y;

  /// Degrees between gravity and image-down.
  double get tiltDegrees => math.atan2(x.abs(), y) * 180 / math.pi;

  /// True when the tilt is too small to be worth correcting.
  bool get isUpright => tiltDegrees < 2 && y > 0;

  /// Express an image point in a frame whose +y axis points along gravity
  /// (a proper rotation, so left/right handedness is preserved).
  (double, double) toGravityAligned(double px, double py) =>
      (y * px - x * py, x * px + y * py);
}

/// The outcome of reading the accelerometer.
class GravityEstimate {
  const GravityEstimate({
    required this.quarterTurns,
    required this.detectionRotation,
    required this.residual,
  });

  /// Clockwise quarter turns applied to the sensor-upright frame to make
  /// gravity point (roughly) down.
  final int quarterTurns;

  /// Rotation to hand to ML Kit so the model sees the scene the right way up.
  final InputImageRotation detectionRotation;

  /// Gravity in the resulting frame: within about 60 degrees of straight down.
  final GravityFrame residual;
}

class DeviceGravity {
  const DeviceGravity._();

  /// In-plane acceleration below this (m/s^2) means the phone is lying flat and
  /// the screen plane tells us nothing about which way is down.
  static const double minInPlane = 3.5;

  /// The tracked quadrant only changes once gravity is this far from its down
  /// direction: 45 degrees is the true boundary, the extra is hysteresis so a
  /// phone propped near a diagonal does not flip back and forth.
  static const double switchDegrees = 60;

  /// Turn an accelerometer reading into a detection rotation.
  ///
  /// [ax] and [ay] are the device-axis reading. [sensorOrientation] is the
  /// camera's `sensorOrientation`. [previousQuarterTurns] enables hysteresis.
  /// Returns null when the phone is flat, in which case keep the last estimate.
  static GravityEstimate? estimate({
    required double ax,
    required double ay,
    required bool frontCamera,
    required int sensorOrientation,
    int? previousQuarterTurns,
  }) {
    final inPlane = math.sqrt(ax * ax + ay * ay);
    if (inPlane < minInPlane) return null;

    // Gravity in the sensor-upright frame. The screen is x-right/y-down and
    // the reaction points up, so y is +ay. A front camera's image is not
    // mirrored the way its preview is, which flips x.
    final gx = (frontCamera ? ax : -ax) / inPlane;
    final gy = ay / inPlane;

    int turnsFor(double vx, double vy) {
      var best = 0;
      var bestDot = -2.0;
      var x = vx, y = vy;
      for (var n = 0; n < 4; n++) {
        if (y > bestDot) {
          bestDot = y;
          best = n;
        }
        // One clockwise quarter turn maps a vector (x, y) to (-y, x).
        final nx = -y;
        y = x;
        x = nx;
      }
      return best;
    }

    var turns = turnsFor(gx, gy);
    if (previousQuarterTurns != null && previousQuarterTurns != turns) {
      var x = gx, y = gy;
      for (var i = 0; i < previousQuarterTurns; i++) {
        final nx = -y;
        y = x;
        x = nx;
      }
      final deviation = math.acos(y.clamp(-1.0, 1.0)) * 180 / math.pi;
      if (deviation < switchDegrees) turns = previousQuarterTurns;
    }

    var rx = gx, ry = gy;
    for (var i = 0; i < turns; i++) {
      final nx = -ry;
      ry = rx;
      rx = nx;
    }

    final degrees = (sensorOrientation + 90 * turns) % 360;
    return GravityEstimate(
      quarterTurns: turns,
      detectionRotation:
          InputImageRotationValue.fromRawValue(degrees) ?? InputImageRotation.rotation0deg,
      residual: GravityFrame(rx, ry),
    );
  }
}

/// Maps points between the frames involved in detection and display.
class PoseCoordinates {
  const PoseCoordinates._();

  /// Size of the frame poses are reported in, given the raw camera image size
  /// (landscape on most phones) and the rotation handed to ML Kit.
  static Size frameSize(Size rawImage, InputImageRotation rotation) {
    final swapped = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    return swapped ? Size(rawImage.height, rawImage.width) : rawImage;
  }

  /// Number of clockwise quarter turns between two detection rotations.
  static int quarterTurnsBetween(InputImageRotation from, InputImageRotation to) =>
      (((to.rawValue - from.rawValue) ~/ 90) % 4 + 4) % 4;

  /// Rotate a point clockwise by [turns] quarter turns inside a frame of
  /// [width] x [height]; returns the new point and the new frame size.
  static (double, double, double, double) rotateClockwise(
    double x,
    double y,
    double width,
    double height,
    int turns,
  ) {
    var px = x, py = y, w = width, h = height;
    for (var i = 0; i < turns % 4; i++) {
      final nx = h - py;
      py = px;
      px = nx;
      final nw = h;
      h = w;
      w = nw;
    }
    return (px, py, w, h);
  }

  /// Convert a pose coordinate reported for [poseRotation] into the
  /// sensor-upright frame the camera preview is drawn in ([previewRotation]).
  static (double, double) toPreviewFrame({
    required double x,
    required double y,
    required Size rawImage,
    required InputImageRotation poseRotation,
    required InputImageRotation previewRotation,
  }) {
    final size = frameSize(rawImage, poseRotation);
    final turns = quarterTurnsBetween(poseRotation, previewRotation);
    final (px, py, _, _) = rotateClockwise(x, y, size.width, size.height, turns);
    return (px, py);
  }
}
