import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_theme.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/services/storage_service.dart';
import 'package:form_analyzer/services/tts_service.dart';
import 'package:form_analyzer/ui/screens/exercise_screen.dart';
import 'package:form_analyzer/ui/widgets/workout_summary_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pose_fixtures.dart';
import 'support/test_clock.dart';

class QuietTTS extends TTSService {
  @override
  Future<void> init() async {}

  @override
  Future<bool> speak(String message, {SpeechPriority priority = SpeechPriority.normal}) async => true;

  @override
  Future<void> stop() async {}
}

RepRecord rep(int i, double score) => RepRecord(index: i, score: score, issues: const []);

WorkoutSession session({
  required int reps,
  int? counted,
  double? rating = 4.0,
  ExerciseType type = ExerciseType.jumpingJack,
  List<String> feedback = const [],
}) {
  final set = ExerciseSet(
    reps: reps,
    countedReps: counted,
    timestamp: DateTime(2026, 9, 29),
    rating: rating ?? 0,
    repRecords: [for (var i = 1; i <= (counted ?? reps); i++) rep(i, 1.0)],
  );
  return WorkoutSession(
    id: 's',
    date: DateTime(2026, 9, 29),
    exerciseType: type,
    sets: [set],
    overallRating: rating,
    overallFeedback: feedback,
  );
}

Future<WorkoutSession?> pumpDialog(WidgetTester tester, WorkoutSession s) async {
  WorkoutSession? confirmed;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: WorkoutSummaryDialog(session: s, onConfirm: (f) => confirmed = f),
      ),
    ),
  );
  await tester.pump();
  return confirmed;
}

void main() {
  group('ExerciseSet', () {
    test('a set nobody corrected keeps its old JSON shape', () {
      final set = ExerciseSet(reps: 8, timestamp: DateTime(2026));
      final json = set.toJson();
      expect(json.containsKey('countedReps'), isFalse);
      final back = ExerciseSet.fromJson(json);
      expect(back.reps, 8);
      expect(back.countedReps, isNull);
      expect(back.counted, 8);
      expect(back.wasCorrected, isFalse);
    });

    test('a corrected set remembers what the counter saw', () {
      final set = ExerciseSet(reps: 6, timestamp: DateTime(2026)).withCorrectedReps(25);
      expect(set.reps, 25);
      expect(set.counted, 6);
      expect(set.wasCorrected, isTrue);
      final back = ExerciseSet.fromJson(set.toJson());
      expect(back.reps, 25);
      expect(back.counted, 6);
    });

    test('correcting twice still remembers the counter\'s number, not the first correction', () {
      final set = ExerciseSet(reps: 6, timestamp: DateTime(2026))
          .withCorrectedReps(10)
          .withCorrectedReps(12);
      expect(set.counted, 6);
      expect(set.reps, 12);
    });

    test('old stored sets without the field still load', () {
      final set = ExerciseSet.fromJson({
        'reps': 5,
        'timestamp': DateTime(2026).toIso8601String(),
        'rating': 3.0,
      });
      expect(set.reps, 5);
      expect(set.counted, 5);
    });
  });

  group('WorkoutSession trust in the rating', () {
    test('an untouched set is trustworthy', () {
      expect(session(reps: 10).ratingTrustworthy, isTrue);
      expect(session(reps: 10).correctionFraction, 0);
    });

    test('a small correction is still trustworthy, a big one is not', () {
      expect(session(reps: 11, counted: 10).ratingTrustworthy, isTrue);
      final big = session(reps: 24, counted: 6);
      expect(big.ratingTrustworthy, isFalse);
      expect(big.wasCorrectedNotably, isTrue);
      expect(big.correctionFraction, closeTo(0.75, 1e-9));
    });
  });

  group('summary dialog', () {
    testWidgets('shows a rating for an ordinary set', (tester) async {
      await pumpDialog(tester, session(reps: 10));
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
      expect(find.textContaining('No form rating'), findsNothing);
    });

    testWidgets('the stepper corrects the total, and Done returns the corrected session',
        (tester) async {
      WorkoutSession? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: WorkoutSummaryDialog(
              session: session(reps: 6),
              onConfirm: (f) => confirmed = f,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('reps-value')), findsOneWidget);

      for (var i = 0; i < 18; i++) {
        await tester.tap(find.byKey(const Key('reps-plus')));
      }
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('reps-value'))).data, '24');
      expect(find.textContaining('Counted 6'), findsOneWidget);

      await tester.ensureVisible(find.text('DONE'));
      await tester.tap(find.text('DONE'));
      await tester.pump();

      expect(confirmed, isNotNull);
      expect(confirmed!.totalReps, 24);
      expect(confirmed!.countedTotal, 6);
    });

    testWidgets('a heavily corrected count drops the star rating', (tester) async {
      await pumpDialog(tester, session(reps: 6));
      for (var i = 0; i < 18; i++) {
        await tester.tap(find.byKey(const Key('reps-plus')));
      }
      await tester.pump();
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.textContaining('No form rating this time'), findsOneWidget);
    });

    testWidgets('a set saved by hand (nothing counted) shows no rating', (tester) async {
      await pumpDialog(tester, session(reps: 12, counted: 0, rating: null));
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
    });

    testWidgets('the total cannot go below the reps of earlier sets', (tester) async {
      final two = WorkoutSession(
        id: 's',
        date: DateTime(2026),
        exerciseType: ExerciseType.squat,
        sets: [
          ExerciseSet(reps: 5, timestamp: DateTime(2026), rating: 4),
          ExerciseSet(reps: 3, timestamp: DateTime(2026), rating: 4),
        ],
        overallRating: 4,
      );
      await pumpDialog(tester, two);
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const Key('reps-minus')));
      }
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('reps-value'))).data, '5');
    });

    testWidgets('one rep gets no best/worst commentary', (tester) async {
      await pumpDialog(tester, session(reps: 1, type: ExerciseType.squat));
      expect(find.textContaining('Every rep scored the same'), findsNothing);
      expect(find.textContaining('Best rep'), findsNothing);
    });
  });

  group('honest issue summaries', () {
    test('hips are never both sagging and piked in one summary', () {
      final analyzer = PushupAnalyzer();
      final issues = [
        ['Hips Sagging'],
        ['Hips Sagging'],
        ['Hips Piked'],
        ['Hips Sagging', 'Insufficient Depth'],
        ['Hips Piked'],
      ];
      // Drive the private list via recordRep-free path: use the public records.
      for (var i = 0; i < issues.length; i++) {
        analyzer.repRecords.add(RepRecord(index: i + 1, score: 0.7, issues: issues[i]));
      }
      analyzer.repCount = issues.length;

      final common = analyzer.getPerformanceMetrics().commonIssues;
      expect(common, contains('Hips Sagging'));
      expect(common, isNot(contains('Hips Piked')));
      expect(common, contains('Insufficient Depth'));
    });
  });

  group('ending a workout in which nothing was counted', () {
    Future<ExerciseScreenState> openScreen(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final exercise = ExerciseCatalog.exerciseForType(ExerciseType.squat);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExerciseScreen(
                        exercise: exercise,
                        tts: QuietTTS(),
                        skipCameraInitialization: true,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Tap through setup and the countdown.
      await tester.tap(find.text('CAMERA SETUP'));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final state = tester.state<ExerciseScreenState>(find.byType(ExerciseScreen));
      expect(state.isCalibrated, isTrue);
      return state;
    }

    testWidgets('the athlete is asked, not sent away with a snackbar', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      expect(find.text('NOTHING WAS COUNTED'), findsOneWidget);
      expect(find.textContaining('Complete at least one rep'), findsNothing);
    });

    testWidgets('Keep going returns to the workout', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('empty-keep-going')));
      await tester.pumpAndSettle();

      expect(find.text('NOTHING WAS COUNTED'), findsNothing);
      expect(find.byType(ExerciseScreen), findsOneWidget);
    });

    testWidgets('Discard leaves without saving', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('empty-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseScreen), findsNothing);
      expect(await StorageService().loadSessions(), isEmpty);
    });

    testWidgets('a set can be saved by hand, without a form score', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(const Key('empty-plus')));
      }
      await tester.pump();
      expect(find.text('SAVE 8 REPS'), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-save')));
      await tester.pumpAndSettle();

      // The summary appears with the reps entered and no rating.
      expect(find.text('WORKOUT COMPLETE'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('reps-value'))).data, '8');
      expect(find.byIcon(Icons.star_rounded), findsNothing);

      await tester.ensureVisible(find.text('DONE'));
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();

      final saved = await StorageService().loadSessions();
      expect(saved, hasLength(1));
      expect(saved.single.totalReps, 8);
      expect(saved.single.countedTotal, 0, reason: 'the counter saw nothing');
      expect(saved.single.overallRating, isNull);
    });
  });

  group('a rep set through the analyzer, saved and corrected', () {
    test('an analyzer-counted set that is corrected keeps both numbers', () {
      final clock = ManualClock();
      final a = PushupAnalyzer(clock: clock.call);
      for (var i = 0; i < 15; i++) {
        clock.advance(const Duration(milliseconds: 66));
        a.processPose(PoseFixtures.pushup(elbowAngle: 175));
      }
      for (var r = 0; r < 3; r++) {
        for (var i = 0; i <= 12; i++) {
          clock.advance(const Duration(milliseconds: 66));
          a.processPose(PoseFixtures.pushup(elbowAngle: 175 - 105 * i / 12));
        }
        for (var i = 0; i <= 12; i++) {
          clock.advance(const Duration(milliseconds: 66));
          a.processPose(PoseFixtures.pushup(elbowAngle: 70 + 105 * i / 12));
        }
      }
      final set = ExerciseSet(reps: a.repCount, timestamp: DateTime(2026), rating: 4);
      final corrected = set.withCorrectedReps(a.repCount + 2);
      expect(corrected.counted, a.repCount);
      expect(corrected.reps, a.repCount + 2);
    });
  });
}
