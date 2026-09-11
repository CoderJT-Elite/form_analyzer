import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_theme.dart';
import 'services/crash_report_service.dart';
import 'ui/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On-device only: logs uncaught errors locally so Profile > Report a
  // Problem has something to share if the user chooses to. Nothing is ever
  // sent automatically — see CrashReportService's doc comment.
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
