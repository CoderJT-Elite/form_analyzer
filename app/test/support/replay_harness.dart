import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'recorded_pose_fixtures.dart';

/// Result of replaying a recorded pose sequence through a real analyzer.
class ReplayRun {
  ReplayRun(this.analyzer, this.cues);
  final ExerciseAnalyzer analyzer;
  final List<String> cues;
  final List<String> safety = [];

  /// Seconds into the sequence at which each rep was counted.
  final List<double> repTimes = [];

  Set<String> get issues => analyzer.allRepIssues.expand((i) => i).toSet();
}

/// Replays [fixture] through an analyzer built by [make], with time simulated
/// at [fps] (15 for the on-phone screen-recording fixtures, 30 for the stock
/// clips) so time-based logic sees realistic
/// durations rather than a tight test loop.
ReplayRun replay(
  String fixture,
  ExerciseAnalyzer Function(DateTime Function()) make, {
  int fps = 15,
}) {
  var t = DateTime(2026);
  final analyzer = make(() => t);
  final run = ReplayRun(analyzer, []);
  analyzer.onCorrection = run.cues.add;
  analyzer.onFeedback = run.cues.add;
  analyzer.onSafetyAlert = (m) {
    run.cues.add(m);
    run.safety.add(m);
  };
  final step = Duration(microseconds: (1e6 / fps).round());
  var frame = 0;
  var lastCount = 0;
  for (final pose in RecordedPoseFixtures.loadSequence(fixture)) {
    t = t.add(step);
    analyzer.processPose(pose);
    frame++;
    if (analyzer.repCount != lastCount) {
      lastCount = analyzer.repCount;
      run.repTimes.add(frame / fps);
    }
  }
  return run;
}
