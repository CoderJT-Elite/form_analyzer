import 'dart:convert';
import 'dart:io';

import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/gravity_frame.dart';
import 'package:form_analyzer/logic/pose_normalizer.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'recorded_pose_fixtures.dart';
import 'replay_harness.dart';

/// Replays a workout recorded on a phone by SessionRecorder, with the timing
/// and gravity the phone actually had, the way the exercise screen would have
/// fed it: frames the validator rejected are skipped, and each pose is levelled
/// with the gravity recorded for that frame.
ReplayRun replayRecording(
  File poses,
  File meta,
  ExerciseAnalyzer Function(DateTime Function()) make,
) {
  final frames = RecordedPoseFixtures.loadFile(poses);
  final info = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
  final frameMeta = (info['frames'] as List).cast<Map<String, dynamic>>();
  assert(frames.length == frameMeta.length, 'poses and meta are index-aligned');

  var t = DateTime(2026);
  final analyzer = make(() => t);
  final run = ReplayRun(analyzer, []);
  void heard(String m, double at) {
    run.cues.add(m);
    run.timedCues.add((at, m));
  }

  var at = 0.0;
  analyzer.onCorrection = (m) => heard(m, at);
  analyzer.onFeedback = (m) => heard(m, at);
  analyzer.onSafetyAlert = (m) {
    heard(m, at);
    run.safety.add(m);
  };

  var lastCount = 0;
  for (var i = 0; i < frames.length; i++) {
    final m = frameMeta[i];
    t = DateTime(2026).add(Duration(milliseconds: m['t'] as int));
    at = (m['t'] as int) / 1000;
    if (m['accepted'] == false || m['phoneMoving'] == true) continue;
    if (m['stage'] != null && m['stage'] != 'active') continue;
    final g = m['gravity'] as List?;
    final frame = g == null ? GravityFrame.upright : GravityFrame((g[0] as num).toDouble(), (g[1] as num).toDouble());
    final Pose pose = normalizePose(frames[i], frame);
    analyzer.processPose(pose);
    if (analyzer.repCount != lastCount) {
      lastCount = analyzer.repCount;
      run.repTimes.add(at);
    }
  }
  return run;
}
