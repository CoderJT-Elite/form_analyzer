import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_theme.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/services/session_recorder.dart';
import 'package:form_analyzer/services/storage_service.dart';
import 'package:form_analyzer/services/tts_service.dart';
import 'package:form_analyzer/ui/screens/exercise_screen.dart';
import 'package:form_analyzer/ui/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_clock.dart';

class FakeTTS extends TTSService {
  final List<String> spoken = [];
  bool accepts = true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> speak(String message, {SpeechPriority priority = SpeechPriority.normal}) async {
    spoken.add(message);
    return accepts;
  }

  @override
  Future<void> stop() async {}
}

Future<void> pumpProfile(WidgetTester tester, FakeTTS tts, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: ProfileScreen(tts: tts)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

void main() {
  group('voice check', () {
    testWidgets('speaks a phrase so the volume can be checked before a workout', (tester) async {
      final tts = FakeTTS();
      await pumpProfile(tester, tts);
      await scrollTo(tester, find.text('Test Voice'));
      await tester.tap(find.text('Test Voice'));
      await tester.pump();

      expect(tts.spoken, hasLength(1));
      expect(tts.spoken.single, contains('voice check'));
    });

    testWidgets('says so, rather than staying silent, when voice coaching is off', (tester) async {
      final tts = FakeTTS();
      await pumpProfile(tester, tts, {'voice_coaching_enabled_v1': false});
      await scrollTo(tester, find.text('Test Voice'));
      await tester.tap(find.text('Test Voice'));
      await tester.pump();

      expect(tts.spoken, isEmpty);
      expect(find.textContaining('Voice Coaching is switched off'), findsOneWidget);
    });

    testWidgets('tells the athlete when the voice could not start', (tester) async {
      final tts = FakeTTS()..accepts = false;
      await pumpProfile(tester, tts);
      await scrollTo(tester, find.text('Test Voice'));
      await tester.tap(find.text('Test Voice'));
      await tester.pump();

      expect(find.textContaining('could not start'), findsOneWidget);
    });
  });

  group('developer options', () {
    testWidgets('are hidden until the build line is tapped five times', (tester) async {
      await pumpProfile(tester, FakeTTS());
      expect(find.text('Record Test Sessions'), findsNothing);

      await scrollTo(tester, find.byKey(const Key('build-footer')));
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('build-footer')));
      }
      await tester.pump();
      expect(find.text('Record Test Sessions'), findsNothing);

      await tester.tap(find.byKey(const Key('build-footer')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Record Test Sessions'));
      expect(find.text('Record Test Sessions'), findsOneWidget);
      expect(find.text('Share Recordings'), findsOneWidget);
      expect(await StorageService().isDeveloperUnlocked(), isTrue);
    });

    testWidgets('stay unlocked, and recording defaults to off', (tester) async {
      await pumpProfile(tester, FakeTTS(), {'developer_options_unlocked_v1': true});
      await scrollTo(tester, find.text('Record Test Sessions'));
      final toggle = tester.widget<Switch>(
        find.descendant(
          of: find.ancestor(of: find.text('Record Test Sessions'), matching: find.byType(Row)).first,
          matching: find.byType(Switch),
        ),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets('the recording switch is remembered', (tester) async {
      await pumpProfile(tester, FakeTTS(), {'developer_options_unlocked_v1': true});
      await scrollTo(tester, find.text('Record Test Sessions'));
      await tester.tap(
        find.descendant(
          of: find.ancestor(of: find.text('Record Test Sessions'), matching: find.byType(Row)).first,
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(await StorageService().isSessionRecordingEnabled(), isTrue);
    });
  });

  group('the exercise screen feeds the recorder', () {
    testWidgets('start, countdown and what was said are all recorded', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final clock = ManualClock();
      final recorder = SessionRecorder(exercise: 'squat', clock: clock.call, buildLabel: 'test');
      final tts = FakeTTS();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ExerciseScreen(
            exercise: ExerciseCatalog.exerciseForType(ExerciseType.squat),
            tts: tts,
            recorder: recorder,
            skipCameraInitialization: true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('CAMERA SETUP'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      final events = (recorder.meta()['events'] as List).cast<Map<String, Object?>>();
      final types = events.map((e) => e['type']).toList();
      expect(types, containsAll(['start', 'countdown', 'speech', 'go']));

      // Everything spoken is also in the recording.
      final said = events.where((e) => e['type'] == 'speech').map((e) => e['text']).toList();
      for (final phrase in tts.spoken) {
        expect(said, contains(phrase));
      }
      expect(said, contains('Go!'));
    });
  });
}
