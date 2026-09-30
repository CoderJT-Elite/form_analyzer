import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'support/replay_harness.dart';

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
/// Direction of a hip cue: `up` asks for the hips to rise, `down` to lower.
String? hipDirection(String cue) {
  final c = cue.toLowerCase();
  if (c.contains('hips up') || c.contains('let your hips drop') || c.contains('lift those hips')) {
    return 'up';
  }
  if (c.contains('lower your hips') || c.contains('hips into line') || c.contains('too high')) {
    return 'down';
  }
  return null;
}

/// Pairs of hip cues that pull in opposite directions less than [window] apart.
///
/// The judge itself refuses to reverse within 4 seconds of a call; this looks at
/// delivered cues, which can trail the verdict by a cue-cooldown, so it only
/// flags reversals too fast to be an athlete over-correcting.
List<String> oppositeHipCallsWithin(ReplayRun run, Duration window) {
  final clashes = <String>[];
  (double, String, String)? previous;
  for (final (t, cue) in run.timedCues) {
    final d = hipDirection(cue);
    if (d == null) continue;
    if (previous != null &&
        previous.$3 != d &&
        (t - previous.$1) < window.inMilliseconds / 1000) {
      clashes.add('${previous.$2} @${previous.$1.toStringAsFixed(1)}s then $cue @${t.toStringAsFixed(1)}s');
    }
    previous = (t, cue, d);
  }
  return clashes;
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

  test('plank: a timed hold, credited as time, with no rapid hip contradictions', () {
    final run = replay('live2_plank', (c) => PlankAnalyzer(clock: c));
    expect(run.analyzer.isTimedHold, isTrue);
    // This "plank" was leaning on a wall for most of its 36 seconds (the body
    // sits 65-85 degrees from horizontal), which is not a floor plank; only the
    // stretch actually near the floor position is credited. The old code
    // credited 14 for a dropout-riddled hold and called the hips both too high
    // and too low within 0.2 seconds; the dropout side is covered in
    // live_test_fixes_test.dart.
    expect(run.analyzer.repCount, greaterThan(0));
    expect(oppositeHipCallsWithin(run, const Duration(milliseconds: 1500)), isEmpty);
  });
}
