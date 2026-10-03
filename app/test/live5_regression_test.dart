import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/cue_engine.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:path/path.dart' as path;

import 'support/recorded_session.dart';
import 'support/replay_harness.dart';

/// Live test #5 (2026-10-02): eight sets, deliberately mixing clean reps with
/// bad ones, on build a37227e. The lunge, plank and sit-up were recorded on the
/// phone by SessionRecorder (ML Kit poses, real timing and gravity); the other
/// five were extracted from the screen recording with MediaPipe at 7.5 fps, the
/// phone's own analysis rate (tools/extract_live_test_fixtures.py).
///
/// What the app did that day, and what this pins:
///   * squat: counted 19, ~8 real; toe-touches and bent-over crouches counted and
///     praised "Great depth"
///   * push-up: sagging, knees-down and half reps counted
///   * glute bridge: tiny hip pulses counted as full bridges
///   * overhead press: a plate being set down and a walk to the phone counted
///   * jumping jack: counted 14, ~28 real (arms blurred, "reach higher" while
///     they were overhead)
///   * lunge: 13 counted, 3 deep; "Good depth" at 105 degrees; "knee behind your
///     toes" five times
///   * plank: the clock ran through ~15 s of clear sag, and "hips too high" was
///     said to sagging hips
///   * sit-up: "keep both sides even" from a side-on camera
///
/// Counts are cross-checked against the joint-angle traces and the video.
ExerciseAnalyzer _make(String kind, DateTime Function() clock) => switch (kind) {
      'squat' => SquatAnalyzer(clock: clock),
      'pushup' => PushupAnalyzer(clock: clock),
      'lunge' => LungeAnalyzer(clock: clock),
      'overheadPress' => OverheadPressAnalyzer(clock: clock),
      'gluteBridge' => GluteBridgeAnalyzer(clock: clock),
      'situp' => SitupAnalyzer(clock: clock),
      'jumpingJack' => JumpingJackAnalyzer(clock: clock),
      'plank' => PlankAnalyzer(clock: clock),
      _ => throw ArgumentError(kind),
    };

ReplayRun _run(String stem, String kind) {
  final dir = path.join(Directory.current.path, 'test', 'fixtures', 'recordings');
  return replayRecording(
    File(path.join(dir, 'live5_${stem}_poses.json')),
    File(path.join(dir, 'live5_${stem}_meta.json')),
    (clock) => _make(kind, clock),
  );
}

Iterable<String> _said(ReplayRun run, {double? from, double? to}) => [
      for (final (t, m) in run.timedCues)
        if ((from == null || t >= from) && (to == null || t <= to)) m,
    ];

void main() {
  group('squat', () {
    late ReplayRun run;
    setUpAll(() => run = _run('squat', 'squat'));

    test('counts the eight real squats, not the toe-touches that followed', () {
      expect(run.analyzer.repCount, inInclusiveRange(7, 9));
      // Every counted rep is one of the deep squats at the start of the set.
      expect(run.repTimes.where((t) => t > 20), isEmpty,
          reason: 'the bent-over crouches and hinges from 20 s on are not squats');
    });

    test('says why the crouches did not count', () {
      expect(run.noReps.map((e) => e.$2), contains('chest up, sit back instead of bending over'));
      expect(run.noReps.length, greaterThanOrEqualTo(3));
    });

    test('never praises depth after the squatting stopped', () {
      final late = _said(run, from: 20);
      expect(late.where((m) => m.contains('Good depth') || m.contains('depth')), isEmpty);
      expect(late.where((m) => m == 'Nice rep' || m == 'That one was clean'), isEmpty);
    });
  });

  group('push-up (phone on its side, against the rack)', () {
    late ReplayRun run;
    setUpAll(() => run = _run('pushupSide', 'pushup'));

    test('turns down the sagging and half reps instead of counting them', () {
      expect(run.analyzer.repCount, inInclusiveRange(5, 8));
      final reasons = run.noReps.map((e) => e.$2).toSet();
      expect(reasons, contains('hips sagged'));
      expect(reasons, contains('lock your arms out at the top'));
    });
  });

  group('glute bridge', () {
    late ReplayRun run;
    setUpAll(() => run = _run('gluteBridge', 'gluteBridge'));

    test('counts the full bridges, and not the half and incomplete ones', () {
      expect(run.analyzer.repCount, inInclusiveRange(8, 12));
      expect(run.noReps.map((e) => e.$2), contains('push your hips higher'));
    });

    test('does not tell the athlete to slow down on the way UP', () {
      // "Slow the way down" was said on the lift: the old tempo timer started on
      // the working phase. The bridge's lowering is the return.
      final said = _said(run).toList();
      final tempo = said.where((m) => m.contains('Slow') || m.contains('Control the descent'));
      // Allowed only for genuinely fast lowering, never one per rep.
      expect(tempo.length, lessThan(run.analyzer.repCount));
    });
  });

  group('overhead press', () {
    late ReplayRun run;
    setUpAll(() => run = _run('overheadPress', 'overheadPress'));

    test('counts the presses, none from setting the plate down', () {
      expect(run.analyzer.repCount, inInclusiveRange(2, 3));
    });

    test('never tells the athlete their elbows are wrong for a wrist fault', () {
      expect(_said(run).where((m) => m.contains('Elbows under your shoulders')), isEmpty);
    });
  });

  group('jumping jack', () {
    late ReplayRun run;
    setUpAll(() => run = _run('jumpingJack', 'jumpingJack'));

    test('counts the whole set (the old arm-based count read 14 of ~28)', () {
      expect(run.analyzer.repCount, inInclusiveRange(25, 31));
      expect(run.noReps.length, lessThanOrEqualTo(2));
    });

    test('no tempo coaching on a movement that is meant to be quick', () {
      expect(
        _said(run).where((m) => m.contains('Slow') || m.contains('descent') || m.contains('two seconds')),
        isEmpty,
      );
    });
  });

  group('lunge (recorded on the phone)', () {
    late ReplayRun run;
    setUpAll(() => run = _run('lunge', 'lunge'));

    test('counts the deep and near-deep lunges, turns down the small knee dips', () {
      expect(run.analyzer.repCount, inInclusiveRange(4, 8));
      expect(run.noReps.length, greaterThanOrEqualTo(7));
      expect(run.noReps.every((e) => e.$2 == 'not deep enough'), isTrue);
    });

    test('the outdated "keep your knee behind your toes" is gone', () {
      expect(_said(run).where((m) => m.contains('knee behind your toes')), isEmpty);
    });

    test('a rep told to go deeper is not also praised for depth', () {
      // Group the delivered cues into reps by the rep events themselves: any
      // window ending in a counted rep that contained a "deeper" cue must not
      // end with praise about depth.
      final cues = run.timedCues;
      for (final t in run.repTimes) {
        final window = [
          for (final (ct, m) in cues)
            if (ct > t - 1.5 && ct <= t + 0.5) m,
        ];
        final coached = window.any((m) => m.toLowerCase().contains('deeper') || m.toLowerCase().contains('lower'));
        if (coached) {
          expect(window.where((m) => m.contains('Good depth')), isEmpty, reason: 'at ${t.toStringAsFixed(1)} s: $window');
        }
      }
    });
  });

  group('plank (recorded on the phone)', () {
    late ReplayRun run;
    setUpAll(() => run = _run('plank', 'plank'));

    test('credits the good seconds, not the whole time in position', () {
      final plank = run.analyzer as PlankAnalyzer;
      expect(plank.heldSeconds, inInclusiveRange(10, 20), reason: 'about 15 good seconds');
      expect(plank.inPositionSeconds, greaterThanOrEqualTo(28));
      expect(plank.inPositionSeconds - plank.heldSeconds, greaterThanOrEqualTo(10),
          reason: 'the sag and pike are paused time');
    });

    test('the clock does not start while the hips are still piked at the start', () {
      expect(run.repTimes.where((t) => t < 27), isEmpty);
    });

    test('hips that are sagging are never told they are too high', () {
      // 42.7-54.5 s is a clear sag (hips 10-18% of body length below the line).
      final sag = _said(run, from: 43.5, to: 54);
      expect(sag.where((m) => m.contains('too high') || m == 'Lower your hips'), isEmpty,
          reason: 'said during the sag: $sag');
    });
  });

  group('sit-up (recorded on the phone)', () {
    late ReplayRun run;
    setUpAll(() => run = _run('situp', 'situp'));

    test('counts the real sit-ups; crunches are not sit-ups', () {
      expect(run.analyzer.repCount, inInclusiveRange(5, 8));
    });

    test('no left-versus-right coaching from a side-on camera', () {
      expect(_said(run).where((m) => m.contains('both sides') || m.contains('weight evenly')), isEmpty);
    });

    test('sit-ups that were counted are counted as the athlete comes back down', () {
      // The old reps were announced 2-3 s late, at the start of the next one.
      // Each counted rep must fall in a stretch where the torso is back near the
      // floor, i.e. at a local minimum: no rep within 0.8 s of the next one's
      // peak. (Cheap proxy: counted reps are at least 1.2 s apart.)
      final times = run.repTimes;
      for (var i = 1; i < times.length; i++) {
        expect(times[i] - times[i - 1], greaterThan(1.2));
      }
    });
  });

  test('every no-rep carries a reason the athlete can act on', () {
    for (final (stem, kind) in const [
      ('squat', 'squat'),
      ('pushupSide', 'pushup'),
      ('gluteBridge', 'gluteBridge'),
      ('lunge', 'lunge'),
      ('situp', 'situp'),
    ]) {
      final run = _run(stem, kind);
      for (final record in run.analyzer.noRepRecords) {
        expect(record.counted, isFalse);
        expect(record.noRepReason, isNotNull, reason: '$stem');
      }
      expect(run.analyzer.getPerformanceMetrics().noRepCount, run.analyzer.noRepRecords.length);
    }
    expect(CueIds.noRep, isNotEmpty);
  });
}
