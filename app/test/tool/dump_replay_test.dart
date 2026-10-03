// Exploration helper, not a regression test: replays a live-5 recording through
// the real analyzer and prints what it counted, turned down, and said.
//
//   flutter test test/tool/dump_replay_test.dart --dart-define=DUMP=live5_squat:squat
//
// Skipped unless DUMP is set.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:path/path.dart' as path;

import '../support/recorded_session.dart';
import '../support/replay_harness.dart';

void main() {
  const spec = String.fromEnvironment('DUMP');
  test('dump replay', skip: spec.isEmpty, () {
    for (final item in spec.split(',')) {
      final parts = item.split(':');
      final stem = parts[0];
      final kind = parts[1];
      final dir = path.join(Directory.current.path, 'test', 'fixtures', 'recordings');
      final metaFile = File(path.join(dir, '${stem}_meta.json'));
      // A stem with no recording beside it is a stock/live fixture under
      // pose_sequences, replayed at the fps given as a third field (default 15).
      final run = metaFile.existsSync()
          ? replayRecording(
              File(path.join(dir, '${stem}_poses.json')),
              metaFile,
              (clock) => _make(kind, clock),
            )
          : replay(stem, (clock) => _make(kind, clock),
              fps: parts.length > 2 ? int.parse(parts[2]) : 15);
      // ignore: avoid_print
      print('=== $stem: counted ${run.analyzer.repCount}, no-rep ${run.noReps.length}, '
          'ignored ${run.ignored}');
      // ignore: avoid_print
      print('counted at: ${run.repTimes.map((t) => t.toStringAsFixed(1)).join(' ')}');
      // ignore: avoid_print
      print('no-reps:    ${run.noReps.map((e) => '${e.$1.toStringAsFixed(1)}:${e.$2}').join(' | ')}');
      // ignore: avoid_print
      print('ignored:    ${run.ignoredLog.map((e) => '${e.$1.toStringAsFixed(1)}:${e.$2}').join(' | ')}');
      for (final c in run.timedCues) {
        // ignore: avoid_print
        print('  ${c.$1.toStringAsFixed(1).padLeft(5)}  ${c.$2}');
      }
    }
  });
}

ExerciseAnalyzer _make(String kind, DateTime Function() clock) => switch (kind) {
      'squat' => SquatAnalyzer(clock: clock),
      'pushup' => PushupAnalyzer(clock: clock),
      'lunge' => LungeAnalyzer(clock: clock),
      'overheadPress' => OverheadPressAnalyzer(clock: clock),
      'gluteBridge' => GluteBridgeAnalyzer(clock: clock),
      'situp' => SitupAnalyzer(clock: clock),
      'jumpingJack' => JumpingJackAnalyzer(clock: clock),
      'plank' => PlankAnalyzer(clock: clock),
      'wallSit' => WallSitAnalyzer(clock: clock),
      'sidePlank' => SidePlankAnalyzer(clock: clock),
      _ => throw ArgumentError(kind),
    };
