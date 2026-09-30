/// Decides when the return half of a rep is finished.
///
/// Every rep-counted analyzer used to close a rep only when a smoothed joint
/// angle crossed one fixed number (squat 160, push-up 155, ...). Real people
/// filmed by a real phone rarely land exactly on those numbers, so the state
/// machine sat in the "coming back up" phase for tens of seconds while the
/// athlete kept repping (live test 2026-09-20: 2 of ~9 squats, 3 of ~12
/// sit-ups, 0 push-ups counted).
///
/// This measures recovery relative to the rep's *own* extreme instead: a rep
/// is done once the athlete has come back most of the way and stopped
/// improving or turned around, and a watchdog frees a machine that would
/// otherwise never move again.
library;

import 'dart:math' as math;

enum RecoveryVerdict { pending, complete, abandon }

class RecoveryDetector {
  RecoveryDetector({
    this.recoveredFraction = 0.85,
    this.minExcursionDegrees = 15.0,
    this.minReturn = const Duration(milliseconds: 300),
    this.plateau = const Duration(milliseconds: 400),
    this.improvementEpsilonDegrees = 1.5,
    this.regressionDegrees = 8.0,
    this.allowRocking = false,
    this.rockingFraction = 0.55,
    this.rockingReversal = 0.3,
    this.watchdog = const Duration(seconds: 8),
  });

  /// Share of the rep's excursion that must be recovered.
  final double recoveredFraction;

  /// Excursions smaller than this are noise, not a rep.
  final double minExcursionDegrees;

  /// A genuine return phase takes at least this long; anything faster is a
  /// twitch on the way into the *next* rep, not the end of this one.
  final Duration minReturn;

  /// How long recovery may stand still before the rep is called finished.
  final Duration plateau;

  final double improvementEpsilonDegrees;
  final double regressionDegrees;

  /// Rocking reps (see [update]) are natural in sit-ups and jumping jacks but
  /// would be phantom reps in a squat or a press, so this is opt-in.
  final bool allowRocking;

  /// Minimum recovery, and size of the following reversal (as a share of the
  /// excursion), that together mark a rep boundary without full recovery.
  final double rockingFraction;
  final double rockingReversal;

  /// Longest a return phase may last before it is forced to resolve.
  final Duration watchdog;

  DateTime? _startedAt;
  DateTime? _bestAt;
  double _bestRecovery = 0;

  void begin(DateTime now) {
    _startedAt = now;
    _bestAt = now;
    _bestRecovery = 0;
  }

  void reset() {
    _startedAt = null;
    _bestAt = null;
    _bestRecovery = 0;
  }

  /// All values are in "progress" space, where larger means further into the
  /// movement (so smaller-is-deeper joint angles must be negated first).
  ///
  /// [extreme] is the furthest progress reached this rep and [rest] the
  /// progress that counts as fully recovered.
  RecoveryVerdict update({
    required double progress,
    required double extreme,
    required double rest,
    required DateTime now,
  }) {
    final started = _startedAt ?? (_startedAt = now);
    final excursion = extreme - rest;

    if (excursion >= minExcursionDegrees) {
      final recovery = extreme - progress; // degrees regained
      if (recovery > _bestRecovery + improvementEpsilonDegrees) {
        _bestRecovery = recovery;
        _bestAt = now;
      }
      final returned = now.difference(started) >= minReturn;
      // Judged on the best recovery reached: once the athlete has come back
      // most of the way, heading down again is the end of that rep however
      // far the reversal has already carried the current reading.
      if (_bestRecovery / excursion >= recoveredFraction && returned) {
        final stalled = now.difference(_bestAt ?? now) >= plateau;
        final turnedAround = recovery < _bestRecovery - regressionDegrees;
        if (stalled || turnedAround) return RecoveryVerdict.complete;
      }
      // Rocking reps: the athlete comes back more than halfway, then heads
      // down again by a big chunk of the range before ever fully recovering.
      // That reversal is a rep boundary just as surely as a plateau is.
      if (allowRocking &&
          returned &&
          _bestRecovery / excursion >= rockingFraction &&
          recovery < _bestRecovery - math.max(regressionDegrees, rockingReversal * excursion)) {
        return RecoveryVerdict.complete;
      }
    }

    if (now.difference(started) >= watchdog) {
      final fraction = excursion >= minExcursionDegrees
          ? (extreme - progress) / excursion
          : 0.0;
      return fraction >= 0.5
          ? RecoveryVerdict.complete
          : RecoveryVerdict.abandon;
    }
    return RecoveryVerdict.pending;
  }
}
