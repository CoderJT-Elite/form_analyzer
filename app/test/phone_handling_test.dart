import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_constants.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/services/device_gravity_service.dart';

import 'support/pose_fixtures.dart';
import 'support/test_clock.dart';

/// A push-up set at 15 fps: [reps] full reps.
void pushups(PushupAnalyzer a, ManualClock clock, int reps) {
  void frame(double angle) {
    clock.advance(const Duration(milliseconds: 66));
    a.processPose(PoseFixtures.pushup(elbowAngle: angle));
  }

  for (var i = 0; i < 15; i++) {
    frame(175);
  }
  for (var r = 0; r < reps; r++) {
    for (var i = 0; i <= 12; i++) {
      frame(175 - 105 * i / 12);
    }
    for (var i = 0; i <= 12; i++) {
      frame(70 + 105 * i / 12);
    }
    for (var i = 0; i < 5; i++) {
      frame(175);
    }
  }
}

void main() {
  group('retracting reps when the phone is handled', () {
    test('reps counted since a moment are removed, earlier ones stay', () {
      final clock = ManualClock();
      final a = PushupAnalyzer(clock: clock.call);
      final seen = <int>[];
      a.onRep = seen.add;

      pushups(a, clock, 4);
      expect(a.repCount, 4);

      final since = clock().subtract(const Duration(milliseconds: 1500));
      final removed = a.retractRepsSince(since);

      expect(removed, greaterThanOrEqualTo(1));
      expect(a.repCount, 4 - removed);
      expect(a.repRecords, hasLength(a.repCount));
      expect(a.repScores, hasLength(a.repCount));
      expect(seen.last, a.repCount, reason: 'the on-screen counter is told');
    });

    test('nothing is removed when nothing was counted that recently', () {
      final clock = ManualClock();
      final a = PushupAnalyzer(clock: clock.call);
      pushups(a, clock, 3);
      clock.advance(const Duration(seconds: 10));
      expect(a.retractRepsSince(clock().subtract(const Duration(seconds: 1))), 0);
      expect(a.repCount, 3);
    });

    test('never goes below zero', () {
      final a = PushupAnalyzer();
      expect(a.retractRepsSince(DateTime(2000)), 0);
      expect(a.repCount, 0);
    });

    test('interrupt keeps the count and records but drops the rep in progress', () {
      final clock = ManualClock();
      final a = PushupAnalyzer(clock: clock.call);
      pushups(a, clock, 3);
      // Half way down a fourth rep.
      for (var i = 0; i < 6; i++) {
        clock.advance(const Duration(milliseconds: 66));
        a.processPose(PoseFixtures.pushup(elbowAngle: 175 - 12.0 * i));
      }
      expect(a.phase, RepPhase.eccentric);

      a.interrupt();

      expect(a.repCount, 3);
      expect(a.repRecords, hasLength(3));
      expect(a.phase, RepPhase.neutral);
      expect(a.statusMessage, 'Paused');

      // And the set carries on afterwards.
      pushups(a, clock, 2);
      expect(a.repCount, 5);
    });

    test('a timed hold keeps its seconds through an interruption', () {
      final clock = ManualClock();
      final plank = PlankAnalyzer(clock: clock.call);
      for (var i = 0; i < 6 * 15; i++) {
        clock.advance(const Duration(milliseconds: 66));
        plank.processPose(PoseFixtures.plank(backAngle: 178));
      }
      final held = plank.repCount;
      expect(held, greaterThanOrEqualTo(3));

      expect(plank.retractRepsSince(DateTime(2000)), 0);
      plank.interrupt();
      expect(plank.repCount, held);
    });
  });

  group('DeviceGravityService', () {
    late StreamController<AccelerometerSample> feed;
    late DeviceGravityService service;
    var now = DateTime(2026);

    setUp(() {
      feed = StreamController<AccelerometerSample>();
      now = DateTime(2026);
      service = DeviceGravityService(source: () => feed.stream, clock: () => now);
    });

    tearDown(() async {
      await service.dispose();
      // Not awaited: closing a controller that never had a listener does not
      // complete.
      unawaited(feed.close());
    });

    Future<void> push(double ax, double ay, {int samples = 100}) async {
      for (var i = 0; i < samples; i++) {
        now = now.add(const Duration(milliseconds: 20));
        feed.add(AccelerometerSample(ax, ay, 0.3));
      }
      await Future<void>.delayed(Duration.zero);
    }

    test('an upright phone gives an upright frame and reports the quadrant once', () async {
      var changes = 0;
      service.onQuadrantChanged = () => changes++;
      service.start(frontCamera: false, sensorOrientation: 90);

      await push(0, 9.81);

      expect(service.estimate!.quarterTurns, 0);
      expect(service.estimate!.detectionRotation.rawValue, 90);
      expect(changes, 1);
    });

    test('turning the phone on its side changes the detection rotation', () async {
      var changes = 0;
      service.start(frontCamera: true, sensorOrientation: 270);
      service.onQuadrantChanged = () => changes++;

      await push(0, 9.81);
      expect(service.estimate!.detectionRotation.rawValue, 270);

      await push(9.81, 0, samples: 300);
      expect(service.estimate!.detectionRotation.rawValue, 0);
      expect(changes, greaterThanOrEqualTo(1));
    });

    test('a phone lying still is not moving, and being carried is', () async {
      service.start(frontCamera: true, sensorOrientation: 270);
      await push(0, 9.81, samples: 200);
      expect(service.phoneIsMoving, isFalse);

      for (var i = 0; i <= 30; i++) {
        final a = (i * 1.3) * math.pi / 180;
        await push(9.81 * math.sin(a), 9.81 * math.cos(a), samples: 1);
      }
      await push(9.81 * math.sin(40 * math.pi / 180), 9.81 * math.cos(40 * math.pi / 180), samples: 4);
      expect(service.phoneIsMoving, isTrue);
      expect(service.phoneMovingSince, isNotNull);
    });

    test('with no sensor it quietly behaves as an upright phone', () async {
      final broken = DeviceGravityService(source: () => throw StateError('no sensor'));
      broken.start(frontCamera: true, sensorOrientation: 270);
      expect(broken.estimate, isNull);
      expect(broken.phoneIsMoving, isFalse);
      await broken.dispose();
    });
  });
}
