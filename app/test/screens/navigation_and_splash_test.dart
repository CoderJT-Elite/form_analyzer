import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/services/storage_service.dart';
import 'package:form_analyzer/ui/screens/dashboard_screen.dart';
import 'package:form_analyzer/ui/screens/history_screen.dart';
import 'package:form_analyzer/ui/screens/main_navigation_wrapper.dart';
import 'package:form_analyzer/ui/screens/profile_screen.dart';
import 'package:form_analyzer/ui/screens/splash_screen.dart';
import 'package:form_analyzer/ui/screens/stats_screen.dart';
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

  group('SplashScreen', () {
    testWidgets('renders title and subtitle during initial hold',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      // Pump a single frame
      await tester.pump();

      expect(find.text('FORM ANALYZER'), findsOneWidget);
      expect(find.text('AI POWERED BIOMECHANICS'), findsOneWidget);

      // Cleanup
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('navigates to MainNavigationWrapper after hold duration',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      // Mark disclaimer as already accepted so dialog doesn't appear
      final storage = StorageService();
      await storage.setHealthDisclaimerAccepted();

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      // Advance clock past the hold timer and transition duration
      await tester.pump(kSplashScreenHoldDuration);
      await tester.pump(const Duration(milliseconds: 700));

      // MainNavigationWrapper should now be mounted
      expect(find.byType(MainNavigationWrapper), findsOneWidget);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('QUICK START'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cancels hold timer cleanly when unmounted early',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));
      // Replace with another widget before the 3200ms hold timer completes
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // Advance well past the original timer duration
      await tester.pump(const Duration(milliseconds: 4000));

      expect(tester.takeException(), isNull);
    });
  });

  group('MainNavigationWrapper', () {
    testWidgets(
        'shows health disclaimer on first run and persists acceptance upon tapping I UNDERSTAND',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      final storage = StorageService();
      expect(await storage.hasAcceptedHealthDisclaimer(), isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationWrapper(),
        ),
      );
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('Before you start'), findsOneWidget);
      expect(find.text('I UNDERSTAND'), findsOneWidget);

      // Tap "I UNDERSTAND"
      await tester.tap(find.text('I UNDERSTAND'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Before you start'), findsNothing);
      expect(await storage.hasAcceptedHealthDisclaimer(), isTrue);
    });

    testWidgets('does not show health disclaimer if already accepted',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      final storage = StorageService();
      await storage.setHealthDisclaimerAccepted();
      expect(await storage.hasAcceptedHealthDisclaimer(), isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationWrapper(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Before you start'), findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('QUICK START'), findsOneWidget);
    });

    testWidgets('switches tabs across Train, History, Stats, and Profile',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      final storage = StorageService();
      await storage.setHealthDisclaimerAccepted();

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationWrapper(),
        ),
      );
      await tester.pumpAndSettle();

      // Initial tab is Train (0)
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('QUICK START'), findsOneWidget);

      // Tap 'History' icon
      await tester.tap(find.byIcon(Icons.history_rounded).last);
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('PAST WORKOUTS'), findsOneWidget);

      // Tap 'Stats' icon
      await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
      await tester.pumpAndSettle();
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(find.text('YOUR METRICS'), findsOneWidget);

      // Tap 'Profile' icon
      await tester.tap(find.byIcon(Icons.person_outline_rounded).last);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('LIFETIME STATS'), findsOneWidget);

      // Switch back to Train
      await tester.tap(find.byIcon(Icons.dashboard_outlined).last);
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('QUICK START'), findsOneWidget);
    });

    testWidgets('tapping header avatar on Train tab switches directly to Profile tab',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      final storage = StorageService();
      await storage.setHealthDisclaimerAccepted();

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationWrapper(),
        ),
      );
      await tester.pumpAndSettle();

      // Find ProfileAvatarButton in Train screen
      final avatarButton = find.byType(GestureDetector).first;
      await tester.tap(avatarButton);
      await tester.pumpAndSettle();

      // Should be on Profile tab
      expect(find.text('LIFETIME STATS'), findsOneWidget);
    });

    testWidgets('disposes cleanly without leaking controllers',
        (WidgetTester tester) async {
      setPhoneSize(tester);
      final storage = StorageService();
      await storage.setHealthDisclaimerAccepted();

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationWrapper(),
        ),
      );
      await tester.pumpAndSettle();

      // Unmount
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
