import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/main.dart';
import 'package:form_analyzer/ui/screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Dashboard smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const FormAnalyzerApp());
    await tester.pump(kSplashScreenHoldDuration);
    await tester.pumpAndSettle();

    // Verify that we are on the main dashboard section.
    expect(find.text('TRAIN'), findsOneWidget);
    expect(find.text('MY ROUTINES'), findsOneWidget);
  });
}
