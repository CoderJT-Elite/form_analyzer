import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/models/exercise_model.dart';

void main() {
  group('ExerciseSet persistence', () {
    test('round-trips rep records through JSON', () {
      final original = ExerciseSet(
        reps: 2,
        timestamp: DateTime(2026, 8, 13, 10, 30),
        rating: 4.5,
        feedback: const ['Rounded Back'],
        repRecords: const [
          RepRecord(
            index: 1,
            score: 1.0,
            issues: [],
            eccentricMs: 1400,
            concentricMs: 900,
            peakAngle: 84,
          ),
          RepRecord(
            index: 2,
            score: 0.7,
            issues: ['Rounded Back'],
            eccentricMs: 500,
            concentricMs: 700,
            peakAngle: 96,
            romDeficitDegrees: 6,
          ),
        ],
      );

      final restored =
          ExerciseSet.fromJson(jsonDecode(jsonEncode(original.toJson())));

      expect(restored.reps, 2);
      expect(restored.rating, 4.5);
      expect(restored.repRecords, hasLength(2));
      expect(restored.repRecords[1].issues, ['Rounded Back']);
      expect(restored.repRecords[1].eccentricMs, 500);
      expect(restored.repRecords[0].peakAngle, 84);
    });

    test('reads sets saved before rep records existed', () {
      // Exactly what an older build wrote — no repRecords key at all.
      final legacy = {
        'reps': 8,
        'durationMs': null,
        'targetReps': null,
        'isPR': false,
        'timestamp': DateTime(2026, 5, 1).toIso8601String(),
        'rating': 3.0,
        'feedback': ['Insufficient Depth'],
      };

      final restored = ExerciseSet.fromJson(legacy);

      expect(restored.reps, 8);
      expect(restored.rating, 3.0);
      expect(restored.repRecords, isEmpty);
      expect(restored.bestRep, isNull);
      expect(restored.averageEccentric, isNull);
    });

    test('derives best, worst and average tempo', () {
      final set = ExerciseSet(
        reps: 3,
        timestamp: DateTime(2026, 8, 13),
        repRecords: const [
          RepRecord(index: 1, score: 1.0, issues: [], eccentricMs: 1000),
          RepRecord(index: 2, score: 0.4, issues: ['x'], eccentricMs: 2000),
          RepRecord(index: 3, score: 0.8, issues: [], eccentricMs: 1500),
        ],
      );

      expect(set.bestRep!.index, 1);
      expect(set.worstRep!.index, 2);
      expect(set.averageEccentric, const Duration(milliseconds: 1500));
    });

    test('ignores reps with no measured tempo when averaging', () {
      final set = ExerciseSet(
        reps: 2,
        timestamp: DateTime(2026, 8, 13),
        repRecords: const [
          RepRecord(index: 1, score: 1.0, issues: []),
          RepRecord(index: 2, score: 1.0, issues: [], eccentricMs: 1200),
        ],
      );

      expect(set.averageEccentric, const Duration(milliseconds: 1200));
    });
  });

  group('WorkoutSession persistence', () {
    test('round-trips a full session', () {
      final session = WorkoutSession(
        id: '123',
        date: DateTime(2026, 8, 13, 9),
        exerciseType: ExerciseType.squat,
        sets: [
          ExerciseSet(
            reps: 5,
            timestamp: DateTime(2026, 8, 13, 9),
            rating: 4.0,
            repRecords: const [
              RepRecord(index: 1, score: 0.8, issues: ['Rounded Back']),
            ],
          ),
        ],
        overallRating: 4.0,
        overallFeedback: const ['Rounded Back'],
      );

      final restored =
          WorkoutSession.fromJson(jsonDecode(jsonEncode(session.toJson())));

      expect(restored.id, '123');
      expect(restored.exerciseType, ExerciseType.squat);
      expect(restored.sets.single.repRecords.single.score, 0.8);
      expect(restored.overallFeedback, ['Rounded Back']);
    });
  });
}
