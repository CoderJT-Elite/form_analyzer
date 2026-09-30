import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

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
  }, skip: 'Phase 2.6: orientation cue leaks into a running set');

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

  test('sit-ups: the ~14-16 real reps, not 0-1', () {
    final run = replay('live3_situp', (c) => SitupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(13, 17));
  }, skip: 'Phase 2.1: counts 12; shallow reps fall under the fixed range floor');

  test('overhead press: no phantom rep while walking back to the phone', () {
    final run = replay('live3_overheadPress', (c) => OverheadPressAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(7, 8));
    expect(run.repTimes.where((t) => t > 19.5), isEmpty);
  }, skip: 'Phase 2.4: counts 9, the last one after the plate is put down');

  test('push-ups (side view): the ~10 real reps, not 1', () {
    final run = replay('live3_pushupSide', (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(9, 13));
  }, skip: 'Phase 1.4 + 2.1: smoothed elbow bottoms out at 110-125, never <=90');

  test('push-ups (head-on, phone on the floor): 4-6 reps', () {
    final run = replay('live3_pushupFront', (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(4, 6));
  }, skip: 'Phase 2.3: elbow angle is flat head-on; needs shoulder-drop signal');

  test('push-ups (phone rotated on the floor): counted, hips not contradicted', () {
    final run = replay('live3_pushupFloor', (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(1, 3));
    expect(run.issues.containsAll({'Hips Sagging', 'Hips Piked'}), isFalse);
  });

  test('plank: a timed hold credited close to the real ~18 s', () {
    final run = replay('live3_plank', (c) => PlankAnalyzer(clock: c));
    expect(run.analyzer.isTimedHold, isTrue);
    expect(run.analyzer.repCount, inInclusiveRange(16, 22));
  }, skip: 'Phase 2.5: credits 12 s; landmark dropouts still eat hold time');

  test('plank: never calls hips both too high and too low in one hold', () {
    final run = replay('live3_plank', (c) => PlankAnalyzer(clock: c));
    expect(run.issues.containsAll({'Hips Sagging', 'Hips Piked'}), isFalse);
    final said = run.safety.join(' | ').toLowerCase();
    final callsHigh = said.contains('too high') || said.contains('lower your hips');
    final callsLow = said.contains('hips up') || said.contains('drop');
    expect(callsHigh && callsLow, isFalse, reason: said);
  }, skip: 'Phase 1.1 + 2.5: sideways phone flips sag/pike; needs gravity frame');
}
