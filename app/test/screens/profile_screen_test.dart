import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/services/storage_service.dart';
import 'package:form_analyzer/ui/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('ProfileScreen renders profile header, stats, and settings',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PROFILE'), findsOneWidget);
    expect(find.text('ADD YOUR NAME'), findsOneWidget);
    expect(find.text('LIFETIME STATS'), findsOneWidget);
    expect(find.text('Voice Coaching'), findsOneWidget);
    expect(find.text('Haptic Feedback'), findsOneWidget);
    expect(find.text('Report a Problem'), findsOneWidget);
    expect(find.text('Health & Safety'), findsOneWidget);
  });

  testWidgets('Toggling Voice Coaching updates local state and StorageService',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    final storage = StorageService();
    // Default is true
    expect(await storage.isVoiceCoachingEnabled(), isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Find switches. First switch is Voice Coaching, second is Haptic Feedback.
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));

    // Toggle Voice Coaching to false
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    expect(await storage.isVoiceCoachingEnabled(), isFalse);

    // Toggle Voice Coaching back to true
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    expect(await storage.isVoiceCoachingEnabled(), isTrue);
  });

  testWidgets('Toggling Haptic Feedback updates local state and StorageService',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    final storage = StorageService();
    expect(await storage.isHapticFeedbackEnabled(), isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));

    // Toggle Haptics to false
    await tester.tap(switches.last);
    await tester.pumpAndSettle();

    expect(await storage.isHapticFeedbackEnabled(), isFalse);

    // Toggle Haptics back to true
    await tester.tap(switches.last);
    await tester.pumpAndSettle();

    expect(await storage.isHapticFeedbackEnabled(), isTrue);
  });

  testWidgets('Tapping Report a Problem with empty crash logs shows message',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report a Problem'));
    await tester.pumpAndSettle();

    expect(
      find.text('No errors have been recorded on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('Tapping Health & Safety shows disclaimer dialog and can be dismissed',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Health & Safety'));
    await tester.pumpAndSettle();

    expect(find.text('Health & Safety'), findsNWidgets(2)); // row + dialog title
    expect(find.text('GOT IT'), findsOneWidget);

    await tester.tap(find.text('GOT IT'));
    await tester.pumpAndSettle();

    expect(find.text('GOT IT'), findsNothing);
  });

  testWidgets('ProfileScreen unmounts cleanly while loading without throwing',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );
    // Do not wait for loadData to finish, unmount immediately
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
