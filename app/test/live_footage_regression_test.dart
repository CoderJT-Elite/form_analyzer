import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'support/recorded_pose_fixtures.dart';

/// Replays pose sequences extracted from the app's own on-phone screen
/// recording of 2026-09-20 (see tools/extract_live_test_fixtures.py): a real
/// athlete, the phone's front camera, self-filmed at awkward distances and
/// angles, and turned on its side for the floor exercises. The stock-footage
/// tests are clean, well-framed clips; this is what actually broke.
///
/// Ground truth is a manual count of the recording. What the app reported live:
/// squat 2, jumping jack 2, overhead press 1, sit-up 3, push-up 0, and a
/// plank credited as 14 "reps". Ranges rather than exact values because the
/// fixtures come from MediaPipe, a proxy for the on-device ML Kit model.
///
/// Time is simulated at the extraction rate (15 fps) so the analyzers' time
/// based logic sees realistic durations rather than a tight test loop.
class ReplayRun {
  ReplayRun(this.analyzer, this.cues);
  final ExerciseAnalyzer analyzer;
  final List<String> cues;
  final List<String> safety = [];
}

ReplayRun replay(
  String fixture,
  ExerciseAnalyzer Function(DateTime Function()) make,
) {
  var t = DateTime(2026);
  final analyzer = make(() => t);
  final run = ReplayRun(analyzer, []);
  analyzer.onCorrection = run.cues.add;
  analyzer.onFeedback = run.cues.add;
  analyzer.onSafetyAlert = (m) {
    run.cues.add(m);
    run.safety.add(m);
  };
  for (final pose in RecordedPoseFixtures.loadSequence(fixture)) {
    t = t.add(const Duration(milliseconds: 66));
    analyzer.processPose(pose);
  }
  return run;
}

void main() {
  test('squat: counts the set instead of 2 of ~9, with no false back alarm', () {
    final run = replay('live2_squat', (c) => SquatAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(6, 10));
    expect(run.safety, isEmpty, reason: 'a straight back was called critical');
    final issues = run.analyzer.allRepIssues.expand((i) => i).toSet();
    expect(issues, isNot(contains('Critical Back Rounding')));
    expect(issues, isNot(contains('Rounded Back')));
  });

  test('jumping jacks: short-but-real jacks count, and nothing says "lower"', () {
    final run = replay('live2_jumpingJack', (c) => JumpingJackAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(8, 16));
    expect(run.cues.where((c) => c.toLowerCase().contains('lower')), isEmpty);
  });

  test('overhead press: about the real number of presses, not 1', () {
    final run = replay('live2_overheadPress', (c) => OverheadPressAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(5, 10));
  });

  test('sit-ups: the ~12 real reps are counted, not 3', () {
    final run = replay('live2_situp', (c) => SitupAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(10, 14));
  });

  test('glute bridge: still counted correctly (this one always worked)', () {
    final run = replay('live2_gluteBridge', (c) => GluteBridgeAnalyzer(clock: c));
    expect(run.analyzer.repCount, inInclusiveRange(5, 8));
  });

  test('push-up: a real push-up is counted and hip cues do not contradict', () {
    final run = replay('live2_pushup', (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, greaterThanOrEqualTo(1));
    final said = run.cues.join(' | ').toLowerCase();
    expect(said.contains('thighs parallel'), isFalse);
  });

  test('plank: a timed hold, credited as time and not thrown away', () {
    final run = replay('live2_plank', (c) => PlankAnalyzer(clock: c));
    expect(run.analyzer.isTimedHold, isTrue);
    // ~36 seconds of footage with several landmark dropouts; the old code
    // paused the clock on every dropout and credited 14.
    expect(run.analyzer.repCount, greaterThanOrEqualTo(15));
  });
}
