import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/presence_tracker.dart';

import 'support/test_clock.dart';

void main() {
  late ManualClock clock;
  late PresenceTracker tracker;

  setUp(() {
    clock = ManualClock();
    tracker = PresenceTracker(clock: clock.call);
  });

  void frames(bool visible, double seconds) {
    for (var i = 0; i < seconds * 15; i++) {
      clock.advance(const Duration(milliseconds: 66));
      tracker.frame(athleteVisible: visible);
    }
  }

  test('nobody has been seen until somebody is', () {
    frames(false, 10);
    expect(tracker.hasSeenAthlete, isFalse);
    expect(tracker.absentFor, isNull);
    expect(tracker.hasBeenAbsentFor(const Duration(seconds: 3)), isFalse,
        reason: 'an empty room before the athlete arrives is not "gone"');
  });

  test('a visible athlete is never absent', () {
    frames(true, 10);
    expect(tracker.hasSeenAthlete, isTrue);
    expect(tracker.absentFor, isNull);
  });

  test('absence is measured from the last time they were there', () {
    frames(true, 2);
    frames(false, 4);
    expect(tracker.hasBeenAbsentFor(const Duration(seconds: 3)), isTrue);
    expect(tracker.hasBeenAbsentFor(const Duration(seconds: 6)), isFalse);
  });

  test('a dropped frame or two is not an absence worth acting on', () {
    frames(true, 2);
    frames(false, 0.3);
    expect(tracker.hasBeenAbsentFor(const Duration(seconds: 3)), isFalse);
    frames(true, 1);
    expect(tracker.absentFor, isNull);
  });

  test('coming back ends the absence', () {
    frames(true, 1);
    frames(false, 5);
    expect(tracker.hasBeenAbsentFor(const Duration(seconds: 3)), isTrue);
    frames(true, 0.2);
    expect(tracker.hasBeenAbsentFor(const Duration(seconds: 3)), isFalse);
  });

  test('reset forgets everything', () {
    frames(true, 1);
    frames(false, 5);
    tracker.reset();
    expect(tracker.hasSeenAthlete, isFalse);
    expect(tracker.absentFor, isNull);
  });
}
