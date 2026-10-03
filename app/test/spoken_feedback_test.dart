import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_theme.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/services/session_recorder.dart';
import 'package:form_analyzer/services/tts_service.dart';
import 'package:form_analyzer/ui/screens/exercise_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pose_fixtures.dart';

/// Records what the exercise screen asked the voice to say, and how loudly.
class RecordingTTS extends TTSService {
  final List<(String, SpeechPriority)> spoken = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> speak(String message, {SpeechPriority priority = SpeechPriority.normal}) async {
    spoken.add((message, priority));
    return true;
  }

  @override
  Future<void> stop() async {}

  Iterable<String> get phrases => spoken.map((e) => e.$1);
}

/// A voice that refuses everything, as the engine does while something more
/// important is being said.
class DeafTTS extends RecordingTTS {
  @override
  Future<bool> speak(String message, {SpeechPriority priority = SpeechPriority.normal}) async {
    spoken.add((message, priority));
    return false;
  }
}

void main() {
  late RecordingTTS tts;
  late Exercise exercise;

  Future<ExerciseScreenState> openScreen(
    WidgetTester tester, {
    RecordingTTS? voice,
    SessionRecorder? recorder,
    ExerciseType type = ExerciseType.squat,
  }) async {
    tts = voice ?? RecordingTTS();
    exercise = ExerciseCatalog.exerciseForType(type);
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
                      tts: tts,
                      recorder: recorder,
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
    await tester.tap(find.text('CAMERA SETUP'));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final state = tester.state<ExerciseScreenState>(find.byType(ExerciseScreen));
    expect(state.isCalibrated, isTrue);
    return state;
  }

  /// One squat, fed straight to the analyzer the screen is listening to. (The
  /// catalog's analyzers run on the wall clock, so nothing here depends on time.)
  void squat(double bottomKnee, {double lean = 0}) {
    final a = exercise.analyzer;
    void feed(double knee) {
      a.processPose(PoseFixtures.squat(kneeAngle: knee, forwardLean: lean));
    }

    for (var i = 0; i < 6; i++) {
      feed(175);
    }
    for (var i = 0; i <= 14; i++) {
      feed(175 - (175 - bottomKnee) * i / 14);
    }
    for (var i = 0; i <= 14; i++) {
      feed(bottomKnee + (175 - bottomKnee) * i / 14);
    }
    for (var i = 0; i < 6; i++) {
      feed(175);
    }
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the rep number is said after each counted rep, quietly', (tester) async {
    await openScreen(tester);
    squat(70);
    await tester.pump();

    // (The countdown's "3, 2, 1" is urgent; the rep count is the only low-priority
    // speech, because any coaching must be able to cut it off.)
    final counts = tts.spoken.where((e) => e.$2 == SpeechPriority.low).map((e) => e.$1);
    expect(counts, ['1'], reason: 'the count must yield to coaching');
  });

  testWidgets('switching Count Reps Aloud off silences the numbers', (tester) async {
    SharedPreferences.setMockInitialValues({'speak_rep_count_v1': false});
    await openScreen(tester);

    squat(70);
    await tester.pump();

    expect(exercise.analyzer.repCount, 1);
    expect(tts.spoken.where((e) => e.$2 == SpeechPriority.low), isEmpty);
  });

  testWidgets('while counting aloud, ordinary praise is left out', (tester) async {
    await openScreen(tester);

    squat(70);
    squat(70);
    await tester.pump();

    expect(tts.phrases, isNot(contains('Nice rep')));
    expect(tts.phrases, isNot(contains('That one was clean')));
  });

  testWidgets('a rep that does not count is announced, with the reason, at once', (tester) async {
    await openScreen(tester);

    squat(120); // never gets low enough to be a squat
    await tester.pump();

    expect(exercise.analyzer.repCount, 0);
    expect(tts.phrases.any((p) => p.startsWith('No rep')), isTrue, reason: '${tts.phrases}');
    expect(exercise.analyzer.noRepRecords.single.noRepReason, 'Not Deep Enough');
  });

  testWidgets('what the voice dropped is recorded as dropped, not as spoken', (tester) async {
    final recorder = SessionRecorder(exercise: 'squat');
    await openScreen(tester, voice: DeafTTS(), recorder: recorder);

    squat(120);
    await tester.pump();
    await tester.pump();

    final events = recorder.meta()['events'] as List;
    final types = events.map((e) => (e as Map)['type']).toList();
    expect(types, contains('noRep'));
    expect(types, contains('speech_dropped'));
  });

  testWidgets('a set that ended with rejected attempts shows them on the rest screen', (tester) async {
    await openScreen(tester);

    squat(70);
    squat(120);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_task_rounded));
    await tester.pump();

    expect(find.text('RESTING'), findsOneWidget);
    expect(find.byKey(const Key('rest-last-set')), findsOneWidget);
    expect(find.textContaining('1 rep counted'), findsOneWidget);
    expect(find.textContaining("didn't count"), findsOneWidget);
    expect(find.textContaining('Next set:'), findsOneWidget);
  });
}
