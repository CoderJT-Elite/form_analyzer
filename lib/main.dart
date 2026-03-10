import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_theme.dart';
import 'ui/screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
      title: 'Form Analyzer Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const DashboardScreen(),
    );
  }
}
