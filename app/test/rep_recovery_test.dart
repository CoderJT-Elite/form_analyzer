import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/rep_recovery.dart';

/// Progress space: larger = further into the movement. A rep whose extreme is
/// 100 and whose rest is 0 has an excursion of 100; progress falling back
/// toward 0 is recovery.
void main() {
  final t0 = DateTime(2026);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  RecoveryVerdict step(
    RecoveryDetector d,
    double progress,
    int ms, {
    double extreme = 100,
    double rest = 0,
  }) =>
      d.update(progress: progress, extreme: extreme, rest: rest, now: at(ms));

  test('a rep that is mostly recovered and has stopped improving completes', () {
    final d = RecoveryDetector()..begin(at(0));
    expect(step(d, 40, 200), RecoveryVerdict.pending);
    expect(step(d, 12, 600), RecoveryVerdict.pending); // 88% but only just got there
    expect(step(d, 12, 1100), RecoveryVerdict.complete); // stalled 500ms
  });

  test('recovery that is still improving is not called complete', () {
    final d = RecoveryDetector()..begin(at(0));
    for (var i = 0; i < 12; i++) {
      // Keeps improving by more than the epsilon each 100 ms.
      expect(step(d, 20 - i * 1.6, 400 + i * 100), RecoveryVerdict.pending);
    }
  });

  test('cannot complete before a genuine return phase has elapsed', () {
    // The premature-concentric twitch: a phantom "recovery" a few frames in.
    final d = RecoveryDetector()..begin(at(0));
    expect(step(d, 5, 100), RecoveryVerdict.pending);
    expect(step(d, 20, 200), RecoveryVerdict.pending); // turned around, too soon
  });

  test('turning around after recovering counts the rep', () {
    final d = RecoveryDetector()..begin(at(0));
    expect(step(d, 8, 500), RecoveryVerdict.pending);
    // Heads back down by more than the reversal threshold: next rep started.
    expect(step(d, 25, 700), RecoveryVerdict.complete);
  });

  test('a tiny excursion is noise, not a rep', () {
    final d = RecoveryDetector()..begin(at(0));
    expect(step(d, 2, 500, extreme: 8), RecoveryVerdict.pending);
    expect(step(d, 2, 1500, extreme: 8), RecoveryVerdict.pending);
  });

  test('watchdog completes a half-recovered rep and abandons a stuck one', () {
    final half = RecoveryDetector()..begin(at(0));
    expect(step(half, 40, 9000), RecoveryVerdict.complete); // 60% back

    final stuck = RecoveryDetector()..begin(at(0));
    expect(step(stuck, 90, 9000), RecoveryVerdict.abandon); // 10% back
  });

  group('rocking reps', () {
    test('a big reversal before full recovery is a rep boundary when allowed', () {
      final d = RecoveryDetector(allowRocking: true)..begin(at(0));
      expect(step(d, 35, 500), RecoveryVerdict.pending); // 65% back
      expect(step(d, 70, 800), RecoveryVerdict.complete); // heads down again
    });

    test('and ignored when not allowed (a press or squat must lock out)', () {
      final d = RecoveryDetector()..begin(at(0));
      expect(step(d, 35, 500), RecoveryVerdict.pending);
      expect(step(d, 70, 800), RecoveryVerdict.pending);
    });
  });
}
