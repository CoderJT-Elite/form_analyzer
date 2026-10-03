import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'live_footage_regression_test.dart' show oppositeHipCallsWithin;
import 'support/replay_harness.dart';

/// Live test #3 (2026-09-29): ten sets recorded on the phone's front camera,
/// the phone standing up, lying on its side for floor work, and once on the
/// floor facing the athlete. Fixtures come from
/// tools/extract_live_test_fixtures.py (MediaPipe as a stand-in for ML Kit).
///
/// The phone that day ran a build older than the fixes, so what it showed is
/// not what this code does. Ground truth is a manual count cross-checked with
/// joint-angle peaks: squat ~8, plank ~18 s, side push-ups ~10-11, lunge ~8,
/// jumping jacks ~24, press ~7-8 (plate lowered, then a walk back to the
/// phone), sit-ups ~14-16, glute bridge 9, head-on push-ups 4-6.
///
/// Tests that pin behaviour still wrong are `skip`ped with the reason, so CI
/// stays green while the list of what is left stays in the repo. Un-skip each
/// as its fix lands.
void main() {
  test('squat: every rep of the set is counted', () {
    final run = replay('live3_squat', (c) => SquatAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(7, 9));
    expect(run.safety, isEmpty);
  });

  test('squat: no setup nag ("turn side-on") once the set is running', () {
    final run = replay('live3_squat', (c) => SquatAnalyzer(clock: c));
    expect(run.cues.where((c) => c.toLowerCase().contains('turn side-on')), isEmpty);
  });

  test('jumping jacks: the full set is counted, not stuck at 6', () {
    final run = replay('live3_jumpingJack', (c) => JumpingJackAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(22, 27));
    expect(run.cues.where((c) => c.toLowerCase().contains('lower')), isEmpty);
  });

  test('glute bridge: all 9 reps', () {
    final run = replay('live3_gluteBridge', (c) => GluteBridgeAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(8, 10));
  });

  test('lunges: about the 8 real reps', () {
    final run = replay('live3_lunge', (c) => LungeAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(7, 9));
  });

  test('sit-ups: the ~13 real reps, not 0-1', () {
    // Thirteen distinct torso peaks (51-87 degrees off the floor) in the trace;
    // the old note said 14-16, which the old analyzer reached by counting some
    // of the lowering as reps.
    final run = replay('live3_situp', (c) => SitupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(11, 14));
  });

  test('overhead press: the three real presses, none from the walk to the phone', () {
    // Three presses to overhead lockout (7, 11 and 15 s), then the athlete sets
    // the plate down and walks back to the phone with the arms hanging. (The
    // old note here said ~7-8; the elbow and wrist-height traces show three
    // lockouts, and the old analyzer counted the lowering as extra reps.) The
    // phone is picked up at 21 s.
    final run = replay('live3_overheadPress', (c) => OverheadPressAnalyzer(clock: c),
        phoneMovedAt: 21.0);
    expect(run.analyzer.repCount, 3);
  });

  test('push-ups (side view): the ~10 real reps, not 1', () {
    final run = replay('live3_pushupSide', (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(9, 13));
  });

  test('push-ups (head-on, phone on the floor): 4-6 reps', () {
    final run = replay('live3_pushupFront', (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(4, 6));
  });

  test('push-ups (phone rotated on the floor): counted, hips not contradicted', () {
    final run = replay('live3_pushupFloor', (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(1, 3));
    expect(run.issues.containsAll({'Hips Sagging', 'Hips Piked'}), isFalse);
  });

  test('plank: a floor plank filmed with the phone on its side is credited in full', () {
    final run = replay('live3_plank', (c) => PlankAnalyzer(clock: c));
    expect(run.analyzer.isTimedHold, isTrue);
    // About 18-20 real seconds, on the floor, phone turned on its side. Levelled
    // by gravity (as the app does) the body lies flat and the hold is credited;
    // the old code credited 12 and, unlevelled, called it a body standing up.
    expect(run.analyzer.repCount, inInclusiveRange(16, 22));
    // Getting down and getting up may prompt "get into plank position"; the
    // middle of the hold must not.
    final midHold = run.timedCues.where(
        (e) => e.$1 > 4 && e.$1 < 17 && e.$2.toLowerCase().contains('plank position'));
    expect(midHold, isEmpty);
  });

  test('plank: never calls the hips both too high and too low in quick succession', () {
    final run = replay('live3_plank', (c) => PlankAnalyzer(clock: c));
    expect(oppositeHipCallsWithin(run, const Duration(milliseconds: 1500)), isEmpty);
  });
}
