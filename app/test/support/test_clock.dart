/// A clock for driving analyzers from tests.
///
/// Analyzers judge reps partly by how long they take, so a test that feeds
/// frames in a tight loop on the wall clock sees every rep last zero
/// milliseconds. Each read advances a fixed [step] (about one camera frame at
/// 15 fps by default), which is what a phone delivers.
class TestClock {
  TestClock({this.step = const Duration(milliseconds: 66)});

  final Duration step;
  DateTime _now = DateTime(2026);

  DateTime call() => _now = _now.add(step);
}
