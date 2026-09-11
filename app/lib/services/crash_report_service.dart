import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recorded error, kept entirely on-device until the user chooses to
/// share it. Never sent anywhere automatically.
class CrashReport {
  final DateTime timestamp;
  final String message;
  final String stackTrace;

  const CrashReport({
    required this.timestamp,
    required this.message,
    required this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'message': message,
        'stackTrace': stackTrace,
      };

  factory CrashReport.fromJson(Map<String, dynamic> json) => CrashReport(
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        message: json['message'] as String? ?? '',
        stackTrace: json['stackTrace'] as String? ?? '',
      );
}

/// Catches uncaught Flutter and platform errors and keeps a short, local-only
/// log of them.
///
/// There is deliberately no third-party crash-reporting SDK here (Crashlytics,
/// Sentry, etc.) — that would mean automatically sending device and
/// stack-trace data off-device, which would contradict this app's stated
/// privacy position ("no crash reporting service in the app", web/privacy.html)
/// and would need a fresh Play Data Safety disclosure to add honestly.
/// Instead, errors are recorded to SharedPreferences only; the sole way a
/// report ever leaves the device is the user tapping "Report a Problem" in
/// Profile and choosing where to send it themselves — the same opt-in pattern
/// already used for workout-history backups.
class CrashReportService {
  static const String _reportsKey = 'crash_reports_v1';
  static const int maxStoredReports = 20;
  static const int _maxStackTraceChars = 4000;

  /// Installs handlers for uncaught Flutter framework errors and uncaught
  /// async/platform errors. Call once, before runApp.
  void install() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(recordError(details.exceptionAsString(), details.stack));
      previousOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(recordError(error.toString(), stack));
      return true;
    };
  }

  /// Appends one error to the on-device log, oldest-first, capped at
  /// [maxStoredReports]. Exposed directly (not just via [install]'s global
  /// handlers) so it's testable without mutating process-wide error hooks.
  Future<void> recordError(String message, StackTrace? stack) async {
    try {
      final rawStack = stack?.toString() ?? '';
      final report = CrashReport(
        timestamp: DateTime.now(),
        message: message,
        stackTrace: rawStack.length > _maxStackTraceChars
            ? rawStack.substring(0, _maxStackTraceChars)
            : rawStack,
      );

      final prefs = await SharedPreferences.getInstance();
      final reports = await _loadRaw(prefs);
      reports.add(report);
      while (reports.length > maxStoredReports) {
        reports.removeAt(0);
      }
      await prefs.setString(
        _reportsKey,
        jsonEncode(reports.map((r) => r.toJson()).toList()),
      );
    } catch (_) {
      // Recording a crash must never itself throw.
    }
  }

  Future<List<CrashReport>> loadReports() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadRaw(prefs);
  }

  Future<void> clearReports() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_reportsKey);
  }

  Future<List<CrashReport>> _loadRaw(SharedPreferences prefs) async {
    final raw = prefs.getString(_reportsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => CrashReport.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
