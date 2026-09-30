import 'package:form_analyzer/core/app_constants.dart';
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

  /// Every cue delivered, with the second of the sequence it arrived.
  final List<(double, String)> timedCues = [];

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
  double? phoneMovedAt,
}) {
  var t = DateTime(2026);
  final analyzer = make(() => t);
  final run = ReplayRun(analyzer, []);
  final step = Duration(microseconds: (1e6 / fps).round());
  var frame = 0;
  void heard(String m) {
    run.cues.add(m);
    run.timedCues.add((frame / fps, m));
  }

  analyzer.onCorrection = heard;
  analyzer.onFeedback = heard;
  analyzer.onSafetyAlert = (m) {
    heard(m);
    run.safety.add(m);
  };
  var lastCount = 0;
  var paused = false;
  for (final pose in RecordedPoseFixtures.loadSequence(fixture)) {
    t = t.add(step);
    frame++;
    if (phoneMovedAt != null && frame / fps >= phoneMovedAt) {
      // What the exercise screen does when the phone is picked up.
      if (!paused) {
        paused = true;
        analyzer.retractRepsSince(t.subtract(AppConstants.phoneMotionRetractWindow));
        analyzer.interrupt();
      }
      continue;
    }
    analyzer.processPose(pose);
    if (analyzer.repCount != lastCount) {
      lastCount = analyzer.repCount;
      run.repTimes.add(frame / fps);
    }
  }
  return run;
}
