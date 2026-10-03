/// Small, dependency-free helpers for judging a rep from noisy pose data.
///
/// Live test #5 showed what a single raw frame is worth: a squat "reached
/// depth" on one frame where the leg landmarks flipped, and a toe-touch was
/// counted and praised. Rep gates now ask for the *median* of a few frames, and
/// faults are judged on the share of good frames showing them, never on one.
library;

import 'dart:math' as math;

/// Median of the last [size] samples. Rejects the one-frame spikes (a flipped
/// knee landmark, a blurred wrist) that a moving average smears instead.
class MedianFilter {
  MedianFilter(this.size) : assert(size >= 1);

  final int size;
  final List<double> _samples = [];

  /// Feed a sample, get the median of the window so far.
  double add(double value) {
    _samples.add(value);
    if (_samples.length > size) _samples.removeAt(0);
    return median;
  }

  /// The current median, or NaN before the first sample.
  double get median {
    if (_samples.isEmpty) return double.nan;
    final sorted = List<double>.of(_samples)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  bool get isFull => _samples.length >= size;

  void reset() => _samples.clear();
}

/// Median of an arbitrary list (NaN when empty).
double medianOf(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return double.nan;
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Evidence gathered about one rep attempt, frame by frame.
///
/// A fault is only believed when enough *good* frames show it: at least
/// [minFrames] of them and at least [minFraction] of all good frames. A frame is
/// "good" when the landmarks it was measured from can be trusted, so tracking
/// noise cannot fail a rep on its own.
class AttemptEvidence {
  int frames = 0;
  int goodFrames = 0;
  final Map<String, int> _faultFrames = {};

  void reset() {
    frames = 0;
    goodFrames = 0;
    _faultFrames.clear();
  }

  /// Record one frame. [faults] are the fault names this frame shows.
  void note({required bool good, Iterable<String> faults = const []}) {
    frames++;
    if (!good) return;
    goodFrames++;
    for (final fault in faults) {
      _faultFrames[fault] = (_faultFrames[fault] ?? 0) + 1;
    }
  }

  int count(String fault) => _faultFrames[fault] ?? 0;

  double fraction(String fault) => goodFrames == 0 ? 0 : count(fault) / goodFrames;

  /// Share of frames that could be trusted at all.
  double get quality => frames == 0 ? 0 : goodFrames / frames;

  /// Whether [fault] is shown often enough to be believed.
  bool confirmed(String fault, {int minFrames = 2, double minFraction = 0.4}) =>
      count(fault) >= minFrames && fraction(fault) >= minFraction;

  /// Whether there is enough trustworthy data to fail a rep on.
  bool get sufficient => goodFrames >= 3 && quality >= 0.6;
}

/// Linear interpolation helper used by threshold bands.
double lerp(double a, double b, double t) => a + (b - a) * math.max(0, math.min(1, t));
