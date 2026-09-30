/// Counts repetitions from a single "depth" signal, judged against the
/// athlete's own range instead of fixed joint angles.
///
/// Every analyzer used to decide *whether a rep happened* by comparing a
/// smoothed angle with an absolute number (push-up: reach 90 degrees, then
/// return past 155). Real people on real phones rarely land on those numbers:
/// in live test #3 the smoothed elbow bottomed out at 110-125 degrees on reps
/// whose raw angle reached 55-80, so the push-up state machine waited on
/// "Lower" for 17 seconds straight with the count at 0. Across the stock
/// push-up clips it counted 1-4 reps where the angle signal shows 6-35.
///
/// This detector never looks at absolute angles. A rep is a genuine
/// excursion away from the athlete's resting level and back again; how *good*
/// the rep was (depth, lockout) is graded separately by the caller.
///
/// The signal must be oriented so that **larger means further into the
/// movement** (negate an angle that closes as you descend).
library;

import 'dart:math' as math;

enum CycleEvent {
  /// Nothing to report this sample.
  none,

  /// The athlete has left the resting level and is working toward the extreme.
  descentStarted,

  /// The athlete turned around at the extreme and is heading back.
  reversed,

  /// One rep finished. See [RepCycleDetector.lastPeak] and
  /// [RepCycleDetector.lastExcursion].
  completed,

  /// A movement that was not a rep (too small, too slow, or too quick) ended.
  abandoned,
}

class RepCycleDetector {
  RepCycleDetector({
    required this.minExcursion,
    this.maxExcursion = double.infinity,
    this.enterFraction = 0.35,
    this.reversalFraction = 0.2,
    this.recoveredFraction = 0.75,
    this.rockingFraction = 0.55,
    this.rockingReversal = 0.3,
    this.minCycle = const Duration(milliseconds: 400),
    this.maxCycle = const Duration(seconds: 12),
    this.restAdaptation = 0.05,
  })  : assert(minExcursion > 0),
        assert(recoveredFraction > 0 && recoveredFraction <= 1);

  /// Smallest peak-to-rest travel, in signal units, that can be a rep.
  final double minExcursion;

  /// Largest rest-to-peak travel the movement can physically produce. Anything
  /// beyond it is tracker junk (the athlete is still getting into position, a
  /// hand crosses the lens) and is discarded rather than adopted as the resting
  /// level -- a junk reading once stalled a whole set for 12 seconds.
  final double maxExcursion;

  /// Share of the athlete's typical excursion that starts a rep.
  final double enterFraction;

  /// Share of the current excursion the signal must fall back before it counts
  /// as having turned around.
  final double reversalFraction;

  /// Share of the excursion that must be regained to finish the rep.
  final double recoveredFraction;

  /// A rep that recovers this much and then heads back down by
  /// [rockingReversal] of the excursion is also finished (sit-ups and jumping
  /// jacks are often repeated without ever fully resting). Opt out with a value
  /// above 1.
  final double rockingFraction;
  final double rockingReversal;

  /// Anything quicker than this is jitter, not a rep.
  final Duration minCycle;

  /// A cycle that has not resolved after this long is abandoned.
  final Duration maxCycle;

  /// How quickly the resting level follows slow drift while idle.
  final double restAdaptation;

  double? _rest;
  double _peak = 0;
  double _valley = 0;
  bool _working = false;
  bool _reversed = false;
  DateTime? _startedAt;
  final List<double> _recentExcursions = [];

  /// Deepest value reached by the most recently completed rep.
  double lastPeak = 0;

  /// Rest-to-peak travel of the most recently completed rep.
  double lastExcursion = 0;

  /// Rest level the most recently completed rep started from.
  double lastRest = 0;

  /// How long the most recently completed rep took.
  Duration lastDuration = Duration.zero;

  bool get isWorking => _working;
  bool get hasReversed => _reversed;
  double? get restLevel => _rest;
  double get peak => _peak;

  /// The athlete's typical excursion: the median of their last few reps, or a
  /// generous guess before there is any history.
  double get typicalExcursion {
    if (_recentExcursions.isEmpty) return minExcursion * 2;
    final sorted = List<double>.of(_recentExcursions)..sort();
    return sorted[sorted.length ~/ 2];
  }

  double get _enterThreshold =>
      math.max(minExcursion * 0.5, enterFraction * typicalExcursion);

  void reset() {
    _rest = null;
    _peak = 0;
    _valley = 0;
    _working = false;
    _reversed = false;
    _startedAt = null;
    _recentExcursions.clear();
    lastPeak = 0;
    lastExcursion = 0;
    lastRest = 0;
    lastDuration = Duration.zero;
  }

  /// Abandon whatever is in progress and treat [depth] as the new resting
  /// level. Used when the athlete leaves the exercise position altogether.
  void rebase(double depth) {
    _rest = depth;
    _working = false;
    _reversed = false;
    _startedAt = null;
  }

  CycleEvent update(double depth, DateTime now) {
    if (!depth.isFinite) return CycleEvent.none;

    final rest = _rest;
    if (rest == null) {
      _rest = depth;
      return CycleEvent.none;
    }

    if (depth - rest > maxExcursion) {
      final wasWorking = _working;
      rebase(depth);
      return wasWorking ? CycleEvent.abandoned : CycleEvent.none;
    }

    if (!_working) {
      if (depth - rest >= _enterThreshold) {
        _working = true;
        _reversed = false;
        _peak = depth;
        _valley = depth;
        _startedAt = now;
        return CycleEvent.descentStarted;
      }
      // Idle: follow the resting level. A new low is taken immediately (arms
      // locking out further than before); upward drift only slowly, and only
      // within the entry band so a slow descent is never mistaken for rest.
      if (depth < rest) {
        _rest = depth;
      } else {
        _rest = rest + restAdaptation * (depth - rest);
      }
      return CycleEvent.none;
    }

    final started = _startedAt ?? now;
    final elapsed = now.difference(started);
    _peak = math.max(_peak, depth);
    final excursion = _peak - rest;

    if (elapsed > maxCycle) {
      rebase(depth);
      return CycleEvent.abandoned;
    }

    if (!_reversed) {
      final fallback = math.max(2.0, reversalFraction * excursion);
      if (excursion >= minExcursion && depth <= _peak - fallback) {
        _reversed = true;
        _valley = depth;
        return CycleEvent.reversed;
      }
      // Slid back to rest without ever travelling far enough: a twitch.
      if (excursion < minExcursion && depth - rest < _enterThreshold * 0.4) {
        rebase(depth);
        return CycleEvent.abandoned;
      }
      return CycleEvent.none;
    }

    _valley = math.min(_valley, depth);
    final recovered = _peak - depth >= recoveredFraction * excursion;
    final rocked = _peak - _valley >= rockingFraction * excursion &&
        depth - _valley >= math.max(2.0, rockingReversal * excursion);

    if (recovered || rocked) {
      if (elapsed < minCycle) {
        rebase(depth);
        return CycleEvent.abandoned;
      }
      lastPeak = _peak;
      lastExcursion = excursion;
      lastRest = rest;
      lastDuration = elapsed;
      _recentExcursions.add(excursion);
      if (_recentExcursions.length > 3) _recentExcursions.removeAt(0);
      // The lowest point reached on the way back is the truest resting level.
      _rest = _valley;
      _working = false;
      _reversed = false;
      _startedAt = null;
      return CycleEvent.completed;
    }
    return CycleEvent.none;
  }
}
