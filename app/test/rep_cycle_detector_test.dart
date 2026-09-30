import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/rep_cycle_detector.dart';

/// Feeds [signal] at [fps] and returns the number of completed reps.
int count(
  RepCycleDetector d,
  List<double> signal, {
  int fps = 15,
  List<CycleEvent>? events,
}) {
  var t = DateTime(2026);
  final step = Duration(microseconds: (1e6 / fps).round());
  var reps = 0;
  for (final v in signal) {
    t = t.add(step);
    final e = d.update(v, t);
    if (e == CycleEvent.completed) reps++;
    if (events != null && e != CycleEvent.none) events.add(e);
  }
  return reps;
}

/// [reps] cosine cycles from [rest] down to [rest] + [depth] over
/// [secondsPerRep], with [restSeconds] of stillness before, between and after.
List<double> cycles({
  required int reps,
  required double depth,
  double rest = 0,
  double secondsPerRep = 1.5,
  double pauseSeconds = 0.0,
  int fps = 15,
  double noise = 0,
  int seed = 1,
}) {
  final rng = math.Random(seed);
  final out = <double>[];
  void hold(double s) {
    for (var i = 0; i < s * fps; i++) {
      out.add(rest + (rng.nextDouble() - 0.5) * 2 * noise);
    }
  }

  hold(1.0);
  for (var r = 0; r < reps; r++) {
    final n = (secondsPerRep * fps).round();
    for (var i = 0; i < n; i++) {
      final phase = i / n;
      final v = rest + depth * 0.5 * (1 - math.cos(2 * math.pi * phase));
      out.add(v + (rng.nextDouble() - 0.5) * 2 * noise);
    }
    hold(pauseSeconds);
  }
  hold(1.0);
  return out;
}

void main() {
  RepCycleDetector detector({double minExcursion = 30}) =>
      RepCycleDetector(minExcursion: minExcursion);

  test('counts a clean set of reps', () {
    expect(count(detector(), cycles(reps: 8, depth: 90)), 8);
  });

  test('counts reps at any pace, from fast to slow', () {
    for (final spr in [0.8, 1.5, 3.0, 5.0]) {
      expect(count(detector(), cycles(reps: 5, depth: 80, secondsPerRep: spr)), 5,
          reason: 'seconds per rep $spr');
    }
  });

  test('counts back-to-back reps with no pause between them', () {
    expect(count(detector(), cycles(reps: 10, depth: 70, secondsPerRep: 1.2)), 10);
  });

  test('is unaffected by the absolute level of the signal', () {
    for (final rest in [-170.0, -90.0, 0.0, 400.0]) {
      expect(count(detector(), cycles(reps: 6, depth: 75, rest: rest)), 6,
          reason: 'rest $rest');
    }
  });

  test('counts shallow-but-real reps (the athlete never reaches a fixed depth)', () {
    expect(count(detector(), cycles(reps: 6, depth: 45)), 6);
  });

  test('does not count movement smaller than the minimum excursion', () {
    expect(count(detector(), cycles(reps: 10, depth: 18, noise: 3)), 0);
  });

  test('survives noisy signals without double counting', () {
    for (var seed = 1; seed <= 20; seed++) {
      expect(
        count(detector(), cycles(reps: 8, depth: 80, noise: 6, seed: seed)),
        8,
        reason: 'seed $seed',
      );
    }
  });

  test('a single-sample spike is not a rep', () {
    final s = List<double>.filled(60, 0);
    s[30] = 120;
    expect(count(detector(), s), 0);
  });

  test('a movement faster than minCycle is not a rep', () {
    final s = <double>[
      ...List<double>.filled(15, 0),
      0, 60, 60, 0, 0, // 4 samples at 30 fps
      ...List<double>.filled(15, 0),
    ];
    expect(count(detector(), s, fps: 30), 0);
  });

  test('adapts as the athlete tires and reps get shallower', () {
    final s = [
      ...cycles(reps: 3, depth: 90),
      ...cycles(reps: 3, depth: 55),
    ];
    expect(count(detector(), s), 6);
  });

  test('a long hold at the bottom is still one rep', () {
    final down = [for (var i = 0; i < 20; i++) 80 * i / 19];
    final hold = List<double>.filled(60, 80);
    final up = [for (var i = 0; i < 20; i++) 80 * (1 - i / 19)];
    final s = [...List<double>.filled(15, 0), ...down, ...hold, ...up, ...List<double>.filled(15, 0)];
    expect(count(detector(), s), 1);
  });

  test('a movement that never resolves is abandoned, and counting resumes', () {
    final stuck = [
      ...List<double>.filled(15, 0),
      ...[for (var i = 0; i < 15; i++) 80.0 * i / 14],
      ...List<double>.filled(15 * 20, 80), // 20 s at the bottom, never returns
    ];
    final events = <CycleEvent>[];
    final d = detector();
    expect(count(d, stuck, events: events), 0);
    expect(events, contains(CycleEvent.abandoned));
    // After being forced back to rest, the next real reps count.
    expect(count(d, cycles(reps: 4, depth: 80)), 4);
  });

  test('rocking reps that never fully rest are still separate reps', () {
    // Comes back only ~65% of the way before heading down again.
    final s = <double>[0.0];
    for (var r = 0; r < 6; r++) {
      s.addAll([for (var i = 1; i <= 12; i++) 90.0 * i / 12]);
      s.addAll([for (var i = 1; i <= 12; i++) 90 - 60.0 * i / 12]);
    }
    s.addAll([for (var i = 1; i <= 15; i++) 30.0 - 30.0 * i / 15]);
    expect(count(detector(), s), greaterThanOrEqualTo(5));
  });

  test('exposes the extent of the last rep for grading', () {
    final d = detector();
    count(d, cycles(reps: 2, depth: 100, rest: 10));
    expect(d.lastPeak, closeTo(110, 8));
    expect(d.lastExcursion, closeTo(100, 8));
    expect(d.lastDuration, greaterThan(const Duration(milliseconds: 800)));
  });

  test('rebase forgets the movement in progress', () {
    final d = detector();
    var t = DateTime(2026);
    for (final v in [0.0, 0.0, 40.0, 60.0]) {
      d.update(v, t = t.add(const Duration(milliseconds: 66)));
    }
    expect(d.isWorking, isTrue);
    d.rebase(60);
    expect(d.isWorking, isFalse);
    expect(d.restLevel, 60);
  });

  test('ignores non-finite samples', () {
    final d = detector();
    final s = cycles(reps: 3, depth: 80);
    s[20] = double.nan;
    s[40] = double.infinity;
    expect(count(d, s), 3);
  });
}
