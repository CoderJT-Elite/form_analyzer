/// Remembers when an athlete was last in the shot.
///
/// Used to notice the end of a set without being told: after the last rep the
/// athlete walks off to stop the workout, and for a few seconds the camera sees
/// nobody. Counting that gap as part of the set is how a set silently runs on.
class PresenceTracker {
  PresenceTracker({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  DateTime? _lastSeen;
  DateTime? _absentSince;

  /// Whether an athlete has ever been seen since the last [reset].
  bool get hasSeenAthlete => _lastSeen != null;

  /// Record one detection frame.
  void frame({required bool athleteVisible}) {
    final t = _now();
    if (athleteVisible) {
      _lastSeen = t;
      _absentSince = null;
    } else if (_lastSeen != null) {
      _absentSince ??= t;
    }
  }

  /// How long nobody has been in the shot, or null while someone is (or was
  /// never there to begin with).
  Duration? get absentFor {
    final since = _absentSince;
    return since == null ? null : _now().difference(since);
  }

  /// True once an athlete who was there has been gone for at least [duration].
  bool hasBeenAbsentFor(Duration duration) {
    final gone = absentFor;
    return gone != null && gone >= duration;
  }

  void reset() {
    _lastSeen = null;
    _absentSince = null;
  }
}
