import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/main.dart';

void main() {
  testWidgets('Dashboard smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FormAnalyzerApp());

    // Verify that we are on the Dashboard
    expect(find.text('FORM ANALYZER'), findsOneWidget);
    expect(find.text('SQUATS'), findsOneWidget);
  });
}
