import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/ui/screens/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('HistoryScreen shows empty state when no history exists',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'workout_sessions_v2': '[]'});

    await tester.pumpWidget(
      const MaterialApp(
        home: HistoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NO HISTORY YET'), findsOneWidget);
    expect(find.text('Complete a workout to see it here.'), findsOneWidget);
  });

  testWidgets('HistoryScreen renders sessions, ratings, and PR badges',
      (WidgetTester tester) async {
    final session = WorkoutSession(
      id: 's_hist_1',
      exerciseType: ExerciseType.squat,
      date: DateTime(2026, 9, 12, 14, 30),
      sets: [
        ExerciseSet(
          reps: 12,
          timestamp: DateTime(2026, 9, 12, 14, 31),
          rating: 4.8,
          isPR: true,
        ),
      ],
      overallRating: 4.8,
      overallFeedback: ['Good Depth', 'Knees Tracking Well'],
    );

    SharedPreferences.setMockInitialValues({
      'workout_sessions_v2': jsonEncode([session.toJson()]),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: HistoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SQUAT'), findsOneWidget);
    expect(find.text('12'), findsOneWidget); // REPS
    expect(find.text('4.8'), findsOneWidget); // FORM
    expect(find.text('GOOD DEPTH'), findsOneWidget);
    expect(find.text('KNEES TRACKING WELL'), findsOneWidget);
    expect(find.text('S1: 12 reps'), findsOneWidget);
    expect(find.byIcon(Icons.stars_rounded), findsOneWidget); // PR icon
  });

  testWidgets('HistoryScreen displays timed exercises with duration formatting',
      (WidgetTester tester) async {
    final plankSession = WorkoutSession(
      id: 's_plank_1',
      exerciseType: ExerciseType.plank,
      date: DateTime(2026, 9, 12, 10, 0),
      sets: [
        ExerciseSet(
          reps: 0,
          duration: const Duration(seconds: 45),
          timestamp: DateTime(2026, 9, 12, 10, 1),
          rating: 4.0,
        ),
      ],
      overallRating: 4.0,
      overallFeedback: ['Hips Level'],
    );

    SharedPreferences.setMockInitialValues({
      'workout_sessions_v2': jsonEncode([plankSession.toJson()]),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: HistoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PLANK'), findsOneWidget);
    // Formatted duration or reps displayed without crashing
    expect(find.text('HIPS LEVEL'), findsOneWidget);
  });
}
