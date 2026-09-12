import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/ui/screens/routine_execution_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('RoutineExecutionScreen handles an empty routine without crashing',
      (WidgetTester tester) async {
    final emptyRoutine = WorkoutRoutine(
      id: 'empty_1',
      name: 'Empty Routine',
      exercises: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoutineExecutionScreen(routine: emptyRoutine),
      ),
    );
    await tester.pump();

    // Progress indicator must render at value 0.0 without NaN assertion crash
    expect(find.text('EMPTY ROUTINE'), findsOneWidget);
    expect(find.text('0 of 0 exercises'), findsOneWidget);
    expect(find.text('NO EXERCISES IN ROUTINE'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, equals(0.0));

    // Tapping close pops screen
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
  });

  testWidgets('RoutineExecutionScreen displays exercises and progress without overflow',
      (WidgetTester tester) async {
    final routine = WorkoutRoutine(
      id: 'r1',
      name: 'Morning Routine',
      exercises: [ExerciseType.squat, ExerciseType.pushup],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoutineExecutionScreen(routine: routine),
      ),
    );
    await tester.pump();

    expect(find.text('MORNING ROUTINE'), findsOneWidget);
    expect(find.text('Exercise 1 of 2'), findsOneWidget);
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('SQUAT'), findsOneWidget);
    expect(find.text('START WORKOUT'), findsOneWidget);

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, equals(0.0));
  });

  testWidgets('Close button in header dismisses the screen',
      (WidgetTester tester) async {
    final routine = WorkoutRoutine(
      id: 'r2',
      name: 'Cardio Routine',
      exercises: [ExerciseType.jumpingJack],
    );

    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (context) => RoutineExecutionScreen(routine: routine),
          ),
          observers: [
            _TestNavigatorObserver(onPopped: () => popped = true),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });
}

class _TestNavigatorObserver extends NavigatorObserver {
  final VoidCallback onPopped;
  _TestNavigatorObserver({required this.onPopped});

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onPopped();
  }
}
