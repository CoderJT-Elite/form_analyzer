import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_theme.dart';
import 'services/crash_report_service.dart';
import 'ui/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Logs uncaught errors on-device (Profile > Report a Problem can share
  // that log manually) and best-effort reports them automatically to a
  // private crash-report form — see CrashReportService's doc comment for
  // why this isn't a third-party crash SDK.
  CrashReportService().install();

  // Lock landscape orientation to prevent layout issues during camera stream
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const FormAnalyzerApp());
}

class FormAnalyzerApp extends StatelessWidget {
  const FormAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Form Analyzer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
