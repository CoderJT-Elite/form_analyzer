import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/phone_motion.dart';

/// Drives a monitor with a synthetic 50 Hz accelerometer.
class Rig {
  final monitor = PhoneMotionMonitor();
  var t = DateTime(2026);
  final rng = math.Random(3);

  /// [seconds] of samples where the phone lies still, tilted [tiltDeg] from
  /// straight up-the-screen, with [noise] m/s^2 of sensor noise and [shake]
  /// m/s^2 of zero-mean vibration.
  bool still(double seconds, {double tiltDeg = 0, double noise = 0.03, double shake = 0}) {
    var moving = monitor.isMoving;
    final a = tiltDeg * math.pi / 180;
    for (var i = 0; i < seconds * 50; i++) {
      t = t.add(const Duration(milliseconds: 20));
      final jolt = shake * (rng.nextDouble() - 0.5) * 2;
      moving = monitor.addSample(
        9.81 * math.sin(a) + (rng.nextDouble() - 0.5) * noise,
        9.81 * math.cos(a) + (rng.nextDouble() - 0.5) * noise + jolt,
        0.2 + (rng.nextDouble() - 0.5) * noise + jolt,
        t,
      );
    }
    return moving;
  }

  /// A smooth tilt from [from] to [to] degrees over [seconds].
  bool tilt(double from, double to, double seconds) {
    var moving = monitor.isMoving;
    final n = (seconds * 50).round();
    for (var i = 0; i <= n; i++) {
      t = t.add(const Duration(milliseconds: 20));
      final a = (from + (to - from) * i / n) * math.pi / 180;
      moving = monitor.addSample(9.81 * math.sin(a), 9.81 * math.cos(a), 0.2, t);
    }
    return moving;
  }
}

void main() {
  test('a phone lying still is never moving', () {
    final rig = Rig();
    expect(rig.still(10), isFalse);
  });

  test('a phone at any resting angle is still', () {
    for (final tilt in [0.0, 25.0, 90.0, 180.0]) {
      final rig = Rig();
      expect(rig.still(5, tiltDeg: tilt), isFalse, reason: 'tilt $tilt');
    }
  });

  test('floor vibration from jumping jacks does not count as moving', () {
    final rig = Rig();
    rig.still(2);
    // Impacts of several m/s^2 that average out.
    for (var i = 0; i < 10; i++) {
      expect(rig.still(1, shake: 4), isFalse, reason: 'second $i');
    }
  });

  test('picking the phone up is movement', () {
    final rig = Rig();
    rig.still(3);
    expect(rig.tilt(0, 40, 0.6), isTrue);
  });

  test('a small nudge is not movement, a big one is', () {
    final small = Rig()..still(3);
    expect(small.tilt(0, 3, 0.6), isFalse);
    final big = Rig()..still(3);
    expect(big.tilt(0, 20, 0.6), isTrue);
  });

  test('counting resumes only after the phone has been still for a while', () {
    final rig = Rig();
    rig.still(3);
    rig.tilt(0, 40, 0.6);
    expect(rig.monitor.isMoving, isTrue);
    // Put down at a new angle: still moving until it has rested.
    expect(rig.still(0.4, tiltDeg: 40), isTrue);
    expect(rig.still(2, tiltDeg: 40), isFalse);
  });

  test('after being set down the new resting angle is the baseline', () {
    final rig = Rig();
    rig.still(3);
    rig.tilt(0, 60, 0.5);
    rig.still(3, tiltDeg: 60);
    expect(rig.monitor.isMoving, isFalse);
    expect(rig.still(5, tiltDeg: 60), isFalse);
  });

  test('a single jolt is not movement', () {
    final rig = Rig();
    rig.still(3);
    rig.tilt(0, 30, 0.05); // 50 ms
    expect(rig.monitor.isMoving, isFalse);
  });

  test('reset clears it', () {
    final rig = Rig();
    rig.still(3);
    rig.tilt(0, 40, 0.6);
    rig.monitor.reset();
    expect(rig.monitor.isMoving, isFalse);
  });
}
