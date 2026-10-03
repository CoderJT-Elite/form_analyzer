import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/cue_engine.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/services/tts_service.dart';

import 'support/pose_fixtures.dart';

void main() {
  group('timed holds', () {
    test('a brief landmark dropout does not stop the clock', () {
      var t = DateTime(2026);
      final plank = PlankAnalyzer(clock: () => t);
      final good = PoseFixtures.plank(backAngle: 178);
      final hidden = PoseFixtures.plank(backAngle: 178, likelihood: 0.1);

      // 10 s at 10 fps, with a 900 ms dropout in the middle.
      for (var i = 0; i < 100; i++) {
        t = t.add(const Duration(milliseconds: 100));
        plank.processPose(i >= 40 && i < 49 ? hidden : good);
      }
      // 10 s, less the 1.5 s spent settling into position, less the dropout.
      expect(plank.repCount, greaterThanOrEqualTo(7));
      expect(plank.isTimedHold, isTrue);
    });

    test('a long absence still stops it and asks for a camera adjustment', () {
      var t = DateTime(2026);
      final plank = PlankAnalyzer(clock: () => t);
      final good = PoseFixtures.plank(backAngle: 178);
      final hidden = PoseFixtures.plank(backAngle: 178, likelihood: 0.1);
      for (var i = 0; i < 30; i++) {
        t = t.add(const Duration(milliseconds: 100));
        plank.processPose(good);
      }
      final held = plank.repCount;
      for (var i = 0; i < 40; i++) {
        t = t.add(const Duration(milliseconds: 100));
        plank.processPose(hidden);
      }
      expect(plank.statusMessage, 'Adjust Camera');
      expect(plank.repCount, held);
    });

    test('only holds are timed, and they stay out of lifetime rep totals', () {
      expect(SquatAnalyzer().isTimedHold, isFalse);
      expect(ExerciseType.plank.isTimedHold, isTrue);
      expect(ExerciseType.wallSit.isTimedHold, isTrue);
      expect(ExerciseType.sidePlank.isTimedHold, isTrue);
      expect(ExerciseType.squat.isTimedHold, isFalse);

      ExerciseSet set(int reps) =>
          ExerciseSet(reps: reps, timestamp: DateTime(2026));
      final plank = WorkoutSession(
        id: 'p', date: DateTime(2026), exerciseType: ExerciseType.plank, sets: [set(35)],
      );
      final squat = WorkoutSession(
        id: 's', date: DateTime(2026), exerciseType: ExerciseType.squat, sets: [set(8)],
      );
      expect(plank.heldSeconds, 35);
      expect(plank.repsForTotals, 0);
      expect(squat.repsForTotals, 8);
      expect(squat.heldSeconds, 0);
    });
  });

  group('a delivered cue stays on screen', () {
    test('displayMessage holds the cue while statusMessage is overwritten', () {
      var t = DateTime(2026);
      final analyzer = SquatAnalyzer(clock: () => t);
      analyzer.cues.request(CueIds.goDeeper);
      final cue = analyzer.statusMessage;

      analyzer.statusMessage = 'Stand tall'; // what the state machine does
      expect(analyzer.displayMessage, cue);

      t = t.add(const Duration(seconds: 3));
      expect(analyzer.displayMessage, 'Stand tall');
    });
  });

  group('cue vocabulary', () {
    test('shared range cue never tells anyone to lower', () {
      final full = kDefaultCues.firstWhere((c) => c.id == CueIds.fullRange);
      for (final phrase in [...full.phrasings, ...full.escalated]) {
        expect(phrase.toLowerCase(), isNot(contains('lower')));
      }
    });

    test('shared depth cue does not name squat-only body parts', () {
      final deeper = kDefaultCues.firstWhere((c) => c.id == CueIds.goDeeper);
      for (final phrase in [...deeper.phrasings, ...deeper.escalated]) {
        expect(phrase.toLowerCase(), isNot(contains('thigh')));
      }
    });

    test('jumping jack, glute bridge and sit-up have direction-correct cues', () {
      expect(GluteBridgeAnalyzer().shortRangeCueId, CueIds.liftHigher);
      expect(SitupAnalyzer().shortRangeCueId, CueIds.curlHigher);
      final ids = kDefaultCues.map((c) => c.id).toSet();
      expect(ids, containsAll([CueIds.raiseArms, CueIds.liftHigher, CueIds.curlHigher]));
    });
  });

  group('range-of-motion exercises', () {
    test('a jack that clearly travels most of the range counts, scored short', () {
      var t = DateTime(2026);
      final jack = JumpingJackAnalyzer(clock: () => t);
      void hold(double angle, int frames) {
        for (var i = 0; i < frames; i++) {
          t = t.add(const Duration(milliseconds: 66));
          jack.processPose(PoseFixtures.jumpingJack(armAngle: angle));
        }
      }

      void sweep(double from, double to) {
        for (var i = 0; i <= 12; i++) {
          hold(from + (to - from) * i / 12, 1);
        }
      }

      hold(40, 10);
      for (var rep = 0; rep < 3; rep++) {
        sweep(40, 112); // never reaches the 130 degree target
        hold(112, 3);
        sweep(112, 40);
        hold(40, 6);
      }

      expect(jack.repCount, 3);
      expect(jack.allRepIssues.first, contains('Arms Not Fully Raised'));
      expect(jack.repScores.first, lessThan(1.0));
    });

    test('a barely-moved arm is not a rep', () {
      var t = DateTime(2026);
      final jack = JumpingJackAnalyzer(clock: () => t);
      for (var r = 0; r < 4; r++) {
        for (var a = 40.0; a <= 70; a += 3) {
          t = t.add(const Duration(milliseconds: 66));
          jack.processPose(PoseFixtures.jumpingJack(armAngle: a));
        }
        for (var a = 70.0; a >= 40; a -= 3) {
          t = t.add(const Duration(milliseconds: 66));
          jack.processPose(PoseFixtures.jumpingJack(armAngle: a));
        }
      }
      expect(jack.repCount, 0);
    });
  });

  group('squat that never quite locks out', () {
    test('reps still count when standing only reads ~150 degrees', () {
      var t = DateTime(2026);
      final squat = SquatAnalyzer(clock: () => t);
      void frame(double knee) {
        t = t.add(const Duration(milliseconds: 66));
        squat.processPose(PoseFixtures.squat(kneeAngle: knee));
      }

      for (var i = 0; i < 10; i++) {
        frame(150);
      }
      for (var rep = 0; rep < 4; rep++) {
        for (var i = 0; i <= 20; i++) {
          frame(150 - 70 * i / 20);
        }
        for (var i = 0; i < 4; i++) {
          frame(80);
        }
        for (var i = 0; i <= 20; i++) {
          frame(80 + 70 * i / 20);
        }
        for (var i = 0; i < 16; i++) {
          frame(150); // stands, but never reaches the old 160 degree bar
        }
      }
      expect(squat.repCount, 4);
    });
  });

  group('TTSService', () {
    late List<String> calls;
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls = [];
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async {
        calls.add(call.method);
        return 1;
      });
    });

    test('normal speech is dropped while something is being said', () async {
      final tts = TTSService();
      expect(await tts.speak('one'), isTrue);
      expect(await tts.speak('two'), isFalse);
      expect(calls.where((c) => c == 'speak').length, 1);
      expect(calls, isNot(contains('stop')));
    });

    test('urgent speech interrupts normal speech but not other urgent speech', () async {
      final tts = TTSService();
      await tts.speak('coaching');
      expect(await tts.speak('safety', priority: SpeechPriority.urgent), isTrue);
      expect(calls, contains('stop'));
      // A repeating safety cue must not chop itself to pieces.
      expect(await tts.speak('safety again', priority: SpeechPriority.urgent), isFalse);
      expect(calls.where((c) => c == 'speak').length, 2);
    });

    test('a completion callback that never arrives cannot silence the coach', () {
      final tts = TTSService();
      tts.speak('stuck');
      expect(tts.canSpeak(SpeechPriority.normal), isFalse);
      expect(
        tts.canSpeak(SpeechPriority.normal,
            now: DateTime.now().add(const Duration(seconds: 9))),
        isTrue,
      );
    });

    test('disabled speech says nothing', () async {
      final tts = TTSService()..setEnabled(false);
      expect(await tts.speak('quiet'), isFalse);
      expect(calls, isEmpty);
    });
  });
}
