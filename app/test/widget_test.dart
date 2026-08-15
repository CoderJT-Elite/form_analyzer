import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/main.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/ui/screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the app and waits out the splash screen.
Future<void> pumpDashboard(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const FormAnalyzerApp());
  await tester.pump(kSplashScreenHoldDuration);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Dashboard smoke test', (WidgetTester tester) async {
    await pumpDashboard(tester);

    // Verify that we are on the main dashboard section.
    expect(find.text('TRAIN'), findsNWidgets(2));
    expect(find.text('MY ROUTINES'), findsOneWidget);
  });

  testWidgets('A first-run user can start an exercise without a routine',
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    // The whole point of Quick Start: with no routines saved, there is still a
    // one-tap path into a workout.
    expect(find.text('NO ROUTINES YET'), findsOneWidget);
    expect(find.text('QUICK START'), findsOneWidget);

    // The first card is tappable and names a real exercise. The horizontal
    // list is lazy, so only the leading cards are built.
    final firstName = ExerciseCatalog.definitions.first.name;
    expect(find.text(firstName), findsOneWidget);
  });
}
