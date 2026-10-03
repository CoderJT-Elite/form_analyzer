import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_theme.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/models/feedback_copy.dart';
import 'package:form_analyzer/services/tts_service.dart';
import 'package:form_analyzer/ui/screens/session_detail_screen.dart';
import 'package:form_analyzer/ui/widgets/set_report.dart';
import 'package:form_analyzer/ui/widgets/workout_summary_dialog.dart';
import 'package:path/path.dart' as path;

import 'support/recorded_pose_fixtures.dart';
import 'support/recorded_session.dart';
import 'support/replay_harness.dart';

RepRecord counted(int i, double score, {List<String> issues = const [], int eccentricMs = 0, double deficit = 0}) =>
    RepRecord(index: i, score: score, issues: issues, eccentricMs: eccentricMs, romDeficitDegrees: deficit);

RepRecord noRep(int i, String reason) =>
    RepRecord(index: i, score: 0, issues: [reason], counted: false, noRepReason: reason);

WorkoutSession sessionOf(
  ExerciseType type,
  List<RepRecord> records, {
  double rating = 3.5,
  int scoringVersion = WorkoutSession.currentScoringVersion,
}) {
  final reps = records.where((r) => r.counted).length;
  return WorkoutSession(
    id: 's',
    date: DateTime(2026, 10, 2, 18),
    exerciseType: type,
    sets: [ExerciseSet(reps: reps, timestamp: DateTime(2026, 10, 2, 18), rating: rating, repRecords: records)],
    overallRating: rating,
    overallFeedback: PerformanceMetrics.fromRecords(records).commonIssues,
    scoringVersion: scoringVersion,
  );
}

Future<void> pumpDialog(WidgetTester tester, WorkoutSession s) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: WorkoutSummaryDialog(session: s, onConfirm: (_) {})),
    ),
  );
  await tester.pump();
}

void main() {
  group('feedback copy', () {
    test('every label an analyzer produces on real footage has a tip written for it', () {
      // Replay every fixture we have, with the analyzer for its exercise, and
      // collect each issue label and no-rep reason that came out.
      final seen = <ExerciseType, Set<String>>{};
      void collect(ExerciseType type, ExerciseAnalyzer a) {
        final labels = seen.putIfAbsent(type, () => {});
        for (final r in a.attemptRecords) {
          labels.addAll(r.issues);
          if (r.noRepReason != null) labels.add(r.noRepReason!);
        }
      }

      ExerciseAnalyzer make(ExerciseType t, DateTime Function() c) => switch (t) {
            ExerciseType.squat => SquatAnalyzer(clock: c),
            ExerciseType.pushup => PushupAnalyzer(clock: c),
            ExerciseType.lunge => LungeAnalyzer(clock: c),
            ExerciseType.overheadPress => OverheadPressAnalyzer(clock: c),
            ExerciseType.gluteBridge => GluteBridgeAnalyzer(clock: c),
            ExerciseType.situp => SitupAnalyzer(clock: c),
            ExerciseType.jumpingJack => JumpingJackAnalyzer(clock: c),
            ExerciseType.plank => PlankAnalyzer(clock: c),
            ExerciseType.wallSit => WallSitAnalyzer(clock: c),
            ExerciseType.sidePlank => SidePlankAnalyzer(clock: c),
          };

      final dir = Directory('test/fixtures/pose_sequences');
      for (final file in dir.listSync().whereType<File>()) {
        final name = path.basenameWithoutExtension(file.path);
        final stem = name.replaceFirst(RegExp(r'^live\d_'), '');
        final type = ExerciseType.values.where((t) => stem.toLowerCase().startsWith(t.name.toLowerCase())).firstOrNull ??
            (stem.startsWith('pushup') ? ExerciseType.pushup : null);
        if (type == null) continue;
        final run = replay(name, (c) => make(type, c), fps: name.startsWith('live') ? 15 : 30);
        collect(type, run.analyzer);
      }
      final rec = Directory('test/fixtures/recordings');
      for (final file in rec.listSync().whereType<File>().where((f) => f.path.endsWith('_poses.json'))) {
        final stem = path.basename(file.path).replaceAll('_poses.json', '');
        final kind = stem.replaceFirst('live5_', '');
        final type = switch (kind) {
          'pushupSide' => ExerciseType.pushup,
          _ => ExerciseType.values.byName(kind),
        };
        final run = replayRecording(
          file,
          File(file.path.replaceAll('_poses.json', '_meta.json')),
          (c) => make(type, c),
        );
        collect(type, run.analyzer);
      }

      final missing = <String>[];
      seen.forEach((type, labels) {
        for (final label in labels) {
          if (!FeedbackCopy.hasTip(type, label)) missing.add('${type.name}: $label');
        }
      });
      expect(missing, isEmpty);
      expect(seen.values.expand((l) => l).length, greaterThan(15), reason: 'the replays must exercise the analyzers');
    });

    test('every label the analyzers can produce is covered, whether or not the fixtures hit it', () {
      const all = {
        ExerciseType.squat: ['Insufficient Depth', 'Excessive Forward Lean', 'Uneven Sides', 'Knees Caving In', 'Not Deep Enough', 'Chest Collapsed', 'Incomplete Stand'],
        ExerciseType.pushup: ['Insufficient Depth', 'Hips Sagging', 'Hips Piked', 'Not Deep Enough', 'Knees Down', 'No Full Lockout'],
        ExerciseType.lunge: ['Insufficient Depth', 'Torso Lean', 'Not Deep Enough', 'Incomplete Stand'],
        ExerciseType.overheadPress: ['Insufficient Range', 'Wrist Not Stacked', 'Leg Drive', 'No Full Lockout', 'Not Low Enough'],
        ExerciseType.gluteBridge: ['Hips Not Fully Extended', 'Hips Not High Enough', 'Incomplete Return'],
        ExerciseType.situp: ['Insufficient Range', 'Straight Legs', 'Not High Enough', 'Incomplete Return'],
        ExerciseType.jumpingJack: ['Feet Not Spread', 'Arms Not Fully Raised', 'Arms Not Raised'],
        ExerciseType.plank: ['Hips Sagging', 'Hips Piked', 'Body Not Straight', 'Elbows Not Under Shoulders', 'On The Floor'],
        ExerciseType.sidePlank: ['Hips Sagging', 'Hips Piked', 'Body Not Straight', 'Elbows Not Under Shoulders', 'On The Floor', 'Bent Knees'],
        ExerciseType.wallSit: ['Not Low Enough', 'Too Low', 'Knee Past Toe', 'Uneven Weight'],
      };
      for (final entry in all.entries) {
        for (final label in entry.value) {
          expect(FeedbackCopy.hasTip(entry.key, label), isTrue, reason: '${entry.key.name}: $label');
          final tip = FeedbackCopy.tip(entry.key, label);
          expect(tip.why, isNotEmpty);
          expect(tip.fix, isNotEmpty);
        }
      }
    });

    test('an unknown label still gets a sensible line, not a crash', () {
      final tip = FeedbackCopy.tip(ExerciseType.squat, 'Some New Fault');
      expect(tip.line, contains('Some New Fault'));
    });

    test('no tip tells anyone to keep their knees behind their toes', () {
      for (final type in ExerciseType.values) {
        for (final label in FeedbackCopy.labelsFor(type)) {
          expect(FeedbackCopy.tip(type, label).line.toLowerCase(), isNot(contains('behind your toes')));
        }
      }
    });
  });

  group('SetInsights', () {
    test('turns rejected attempts into a reason count and the top fixes', () {
      final insights = SetInsights.from(ExerciseType.pushup, [
        counted(0, 1.0),
        noRep(1, 'Hips Sagging'),
        noRep(2, 'Hips Sagging'),
        noRep(3, 'Knees Down'),
        counted(4, 0.65, issues: ['Insufficient Depth']),
      ]);

      expect(insights.counted, hasLength(2));
      expect(insights.rejected, hasLength(3));
      expect(insights.noReps, {'Hips Sagging': 2, 'Knees Down': 1});
      expect(insights.fixes, ['Hips Sagging', 'Knees Down']);
    });

    test('says form faded when the second half is clearly worse', () {
      final records = [
        for (var i = 0; i < 4; i++) counted(i, 1.0),
        for (var i = 4; i < 8; i++) noRep(i, 'Not Deep Enough'),
      ];
      final line = SetInsights.from(ExerciseType.squat, records).consistency!;
      expect(line, contains('rep 5'));
      expect(line, anyOf(contains('broke down'), contains('faded')));
    });

    test('says form held when it did', () {
      final records = [for (var i = 0; i < 8; i++) counted(i, 0.95)];
      expect(SetInsights.from(ExerciseType.squat, records).consistency, contains('held steady'));
    });

    test('a short set makes no claim about consistency', () {
      final records = [for (var i = 0; i < 4; i++) counted(i, 0.95)];
      expect(SetInsights.from(ExerciseType.squat, records).consistency, isNull);
    });

    test('flags lowering that was dropped rather than controlled', () {
      final records = [for (var i = 0; i < 6; i++) counted(i, 1.0, eccentricMs: 450)];
      expect(SetInsights.from(ExerciseType.squat, records).tempo, contains('about two seconds'));
    });

    test('praises controlled lowering', () {
      final records = [for (var i = 0; i < 6; i++) counted(i, 1.0, eccentricMs: 2100)];
      expect(SetInsights.from(ExerciseType.squat, records).tempo, contains('Controlled lowering'));
    });

    test('a hold reads as good seconds out of seconds in position', () {
      final records = [
        for (var i = 0; i < 12; i++) counted(i, 1.0),
        for (var i = 12; i < 20; i++) noRep(i, 'Hips Sagging'),
      ];
      final insights = SetInsights.from(ExerciseType.plank, records);
      expect(insights.holdLine, 'Good form for 12 of 20 seconds; the clock paused for 8 while form was broken.');
      expect(insights.consistency, isNull);
      expect(insights.tempo, isNull);
    });

    test('best and worst only for a set that has enough counted reps to compare', () {
      expect(SetInsights.from(ExerciseType.squat, [counted(0, 1.0), counted(1, 0.5)]).bestWorst, isNull);
      final three = SetInsights.from(ExerciseType.squat, [counted(0, 1.0), counted(1, 0.5), counted(2, 0.9)]);
      expect(three.bestWorst, 'Best rep #1, weakest rep #2.');
    });
  });

  group('the summary dialog', () {
    testWidgets('names the exercise properly', (tester) async {
      await pumpDialog(tester, sessionOf(ExerciseType.overheadPress, [counted(0, 1.0)]));
      expect(find.text('OVERHEAD PRESS'), findsOneWidget);
      expect(find.text('OVERHEADPRESS'), findsNothing);
    });

    testWidgets('lists what did not count, and why', (tester) async {
      await pumpDialog(
        tester,
        sessionOf(ExerciseType.squat, [
          counted(0, 1.0),
          counted(1, 1.0),
          noRep(2, 'Chest Collapsed'),
          noRep(3, 'Chest Collapsed'),
          noRep(4, 'Not Deep Enough'),
        ]),
      );

      expect(find.byKey(const Key('no-rep-heading')), findsOneWidget);
      expect(find.text("DIDN'T COUNT: 3"), findsOneWidget);
      expect(find.text('Chest Collapsed ×2'), findsOneWidget);
      expect(find.text('Not Deep Enough'), findsWidgets);
      // And what to do about it.
      expect(find.byKey(const Key('coach-heading')), findsOneWidget);
      expect(find.textContaining('Fix:'), findsWidgets);
      expect(find.textContaining('hip hinge'), findsOneWidget);
    });

    testWidgets('a clean set says so and has nothing to fix', (tester) async {
      await pumpDialog(tester, sessionOf(ExerciseType.squat, [for (var i = 0; i < 5; i++) counted(i, 1.0)]));
      expect(find.byKey(const Key('clean-set')), findsOneWidget);
      expect(find.byKey(const Key('no-rep-heading')), findsNothing);
    });

    testWidgets('tapping a rep bar opens that rep: score, range, tempo and the fix', (tester) async {
      await pumpDialog(
        tester,
        sessionOf(ExerciseType.squat, [
          counted(0, 1.0, eccentricMs: 1800),
          counted(1, 0.7, issues: ['Insufficient Depth'], eccentricMs: 600, deficit: 18),
          counted(2, 1.0, eccentricMs: 1700),
        ]),
      );

      await tester.ensureVisible(find.byKey(const Key('rep-bar-1')));
      await tester.tap(find.byKey(const Key('rep-bar-1')));
      await tester.pumpAndSettle();

      expect(find.text('THIS REP'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('about 18 degrees short of full'), findsOneWidget);
      expect(find.text('0.6 s'), findsOneWidget);
      expect(find.text('Insufficient Depth'), findsWidgets);
      expect(
        find.descendant(of: find.byType(RepDetailSheet), matching: find.textContaining('Fix:')),
        findsOneWidget,
      );
    });

    testWidgets('tapping a rejected attempt says it did not count and why', (tester) async {
      await pumpDialog(
        tester,
        sessionOf(ExerciseType.pushup, [counted(0, 1.0), noRep(1, 'Hips Sagging'), counted(2, 1.0)]),
      );
      await tester.ensureVisible(find.byKey(const Key('rep-bar-1')));
      await tester.tap(find.byKey(const Key('rep-bar-1')));
      await tester.pumpAndSettle();

      expect(find.text('DID NOT COUNT'), findsOneWidget);
      expect(find.text('Did not count: Hips Sagging'), findsOneWidget);
    });

    testWidgets('a plank shows good form against time in position', (tester) async {
      await pumpDialog(
        tester,
        sessionOf(ExerciseType.plank, [
          for (var i = 0; i < 15; i++) counted(i, 1.0),
          for (var i = 15; i < 25; i++) noRep(i, 'Hips Sagging'),
        ]),
      );

      expect(find.text('TIME HELD'), findsOneWidget);
      expect(find.text('0:15'), findsOneWidget);
      expect(find.byKey(const Key('in-position')), findsOneWidget);
      expect(find.text('of 0:25 in position'), findsOneWidget);
      expect(find.textContaining('Good form for 15 of 25 seconds'), findsOneWidget);
    });
  });

  group('session detail', () {
    testWidgets('shows each set with its bars and what to fix', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final session = sessionOf(ExerciseType.situp, [
        counted(0, 1.0),
        noRep(1, 'Not High Enough'),
        counted(2, 0.7, issues: ['Insufficient Range']),
      ]);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: SessionDetailScreen(session: session)));
      await tester.pump();

      expect(find.text('SIT-UPS'), findsOneWidget);
      expect(find.text('SET 1'), findsOneWidget);
      expect(find.byKey(const Key('rep-bar-1')), findsOneWidget);
      expect(find.textContaining('Not High Enough'), findsWidgets);
      expect(find.byKey(const Key('legacy-note')), findsNothing);
    });

    testWidgets('a session from before no-reps says it was scored more leniently', (tester) async {
      final session = sessionOf(ExerciseType.squat, [counted(0, 1.0)], scoringVersion: 1);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: SessionDetailScreen(session: session)));
      await tester.pump();
      expect(find.byKey(const Key('legacy-note')), findsOneWidget);
    });
  });

  group('stored data', () {
    test('records of attempts that did not count survive a round trip', () {
      final session = sessionOf(ExerciseType.squat, [counted(0, 1.0), noRep(1, 'Chest Collapsed')]);
      final back = WorkoutSession.fromJson(session.toJson());
      expect(back.scoringVersion, WorkoutSession.currentScoringVersion);
      final records = back.sets.single.repRecords;
      expect(records[0].counted, isTrue);
      expect(records[1].counted, isFalse);
      expect(records[1].noRepReason, 'Chest Collapsed');
      expect(back.sets.single.noRepCounts, {'Chest Collapsed': 1});
      expect(back.sets.single.bestRep!.index, 0, reason: 'best and worst consider counted reps only');
    });

    test('sessions saved before no-reps load as scored by the old rules', () {
      final json = sessionOf(ExerciseType.squat, [counted(0, 1.0)]).toJson()..remove('scoringVersion');
      expect(WorkoutSession.fromJson(json).scoringVersion, 1);
    });

    test('a record saved before the counted flag existed counts', () {
      final record = RepRecord.fromJson({'index': 3, 'score': 0.8, 'issues': <String>[]});
      expect(record.counted, isTrue);
      expect(record.noRepReason, isNull);
    });

    test('a set of rejected attempts cannot earn a high rating', () {
      final metrics = PerformanceMetrics.fromRecords([
        counted(0, 1.0),
        for (var i = 1; i < 5; i++) noRep(i, 'Not Deep Enough'),
      ]);
      expect(metrics.totalReps, 1);
      expect(metrics.noRepCount, 4);
      expect(metrics.averageFormScore, closeTo(1.0, 1e-9), reason: 'one clean rep out of five attempts: 1/5 of 5 stars');
    });
  });

  group('speech priority', () {
    test('rep counts yield to coaching and coaching yields to safety', () {
      final tts = TTSService();
      expect(SpeechPriority.low.index, lessThan(SpeechPriority.normal.index));
      expect(SpeechPriority.normal.index, lessThan(SpeechPriority.urgent.index));
      expect(tts.canSpeak(SpeechPriority.low), isTrue);
    });
  });

  test('the recorded squat fixture loads (sanity for the shared harness)', () {
    expect(RecordedPoseFixtures.loadSequence('live3_squat'), isNotEmpty);
  });
}
