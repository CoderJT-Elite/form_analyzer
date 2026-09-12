import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/ui/screens/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('StatsScreen shows empty state when no sessions exist',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'workout_sessions_v2': '[]'});

    await tester.pumpWidget(
      const MaterialApp(
        home: StatsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NO DATA YET'), findsOneWidget);
    expect(find.text('Complete a workout to see your stats.'), findsOneWidget);
  });

  testWidgets('StatsScreen handles unrated sessions with neutral trend and N/A rating',
      (WidgetTester tester) async {
    final unratedSession = WorkoutSession(
      id: 's1',
      exerciseType: ExerciseType.squat,
      date: DateTime.now(),
      sets: [
        ExerciseSet(
          reps: 10,
          timestamp: DateTime.now(),
          rating: 4.0,
        ),
      ],
      overallRating: null,
      overallFeedback: [],
    );

    SharedPreferences.setMockInitialValues({
      'workout_sessions_v2': jsonEncode([unratedSession.toJson()]),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: StatsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TOTAL REPS'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Need more sessions'), findsOneWidget);
    expect(find.text('N/A'), findsNWidgets(2)); // rating card and trend card

    // Neutral icon when there are insufficient rated sessions
    expect(find.byIcon(Icons.horizontal_rule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
  });

  testWidgets('StatsScreen displays trending up when form improves',
      (WidgetTester tester) async {
    final s1 = WorkoutSession(
      id: 's1',
      exerciseType: ExerciseType.squat,
      date: DateTime.now().subtract(const Duration(days: 2)),
      sets: [ExerciseSet(reps: 5, timestamp: DateTime.now(), rating: 3.0)],
      overallRating: 3.0,
    );
    final s2 = WorkoutSession(
      id: 's2',
      exerciseType: ExerciseType.squat,
      date: DateTime.now().subtract(const Duration(days: 1)),
      sets: [ExerciseSet(reps: 5, timestamp: DateTime.now(), rating: 4.5)],
      overallRating: 4.5,
    );

    SharedPreferences.setMockInitialValues({
      'workout_sessions_v2': jsonEncode([s1.toJson(), s2.toJson()]),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: StatsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trending up'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
  });

  testWidgets('StatsScreen displays trending down when form drops',
      (WidgetTester tester) async {
    final s1 = WorkoutSession(
      id: 's1',
      exerciseType: ExerciseType.pushup,
      date: DateTime.now().subtract(const Duration(days: 2)),
      sets: [ExerciseSet(reps: 5, timestamp: DateTime.now(), rating: 4.5)],
      overallRating: 4.5,
    );
    final s2 = WorkoutSession(
      id: 's2',
      exerciseType: ExerciseType.pushup,
      date: DateTime.now().subtract(const Duration(days: 1)),
      sets: [ExerciseSet(reps: 5, timestamp: DateTime.now(), rating: 2.5)],
      overallRating: 2.5,
    );

    SharedPreferences.setMockInitialValues({
      'workout_sessions_v2': jsonEncode([s1.toJson(), s2.toJson()]),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: StatsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trending down'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
  });

  testWidgets('StatsScreen displays maintaining form when score is unchanged',
      (WidgetTester tester) async {
    final s1 = WorkoutSession(
      id: 's1',
      exerciseType: ExerciseType.lunge,
      date: DateTime.now().subtract(const Duration(days: 2)),
      sets: [ExerciseSet(reps: 5, timestamp: DateTime.now(), rating: 4.0)],
      overallRating: 4.0,
    );
    final s2 = WorkoutSession(
      id: 's2',
      exerciseType: ExerciseType.lunge,
      date: DateTime.now().subtract(const Duration(days: 1)),
      sets: [ExerciseSet(reps: 5, timestamp: DateTime.now(), rating: 4.0)],
      overallRating: 4.0,
    );

    SharedPreferences.setMockInitialValues({
      'workout_sessions_v2': jsonEncode([s1.toJson(), s2.toJson()]),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: StatsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Maintaining form'), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat_rounded), findsOneWidget);
  });

  testWidgets('StatsScreen handles 200 sessions with extreme reps and durations without crashing',
      (WidgetTester tester) async {
    final sessions = List.generate(
      200,
      (i) => WorkoutSession(
        id: 's_$i',
        exerciseType: ExerciseType.values[i % ExerciseType.values.length],
        date: DateTime.now().subtract(Duration(days: i)),
        sets: [
          ExerciseSet(
            reps: i % 2 == 0 ? 0 : 50,
            timestamp: DateTime.now().subtract(Duration(days: i)),
            duration: Duration(seconds: i == 0 ? 0 : i * 100),
            rating: (i % 5 + 1).toDouble(),
          ),
        ],
        overallRating: i % 3 == 0 ? null : (i % 5 + 1).toDouble(),
        overallFeedback: [],
      ),
    );

    SharedPreferences.setMockInitialValues({
      'workout_sessions_v2': jsonEncode(sessions.map((s) => s.toJson()).toList()),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: StatsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STATS'), findsOneWidget);
    expect(find.text('200'), findsOneWidget); // SESSIONS count
    expect(find.text('TOTAL REPS'), findsOneWidget);
  });
}
