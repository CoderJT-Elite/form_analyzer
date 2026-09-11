import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Where crash reports are sent: a private Google Form (owned by the
/// developer, not a third party), submitted the same way any public form
/// accepts a response — a plain POST with `entry.<id>` fields, no API key or
/// auth needed. Responses land in the form's own Responses tab. See
/// [CrashReportService]'s doc comment for why this exists instead of a
/// third-party SDK like Crashlytics or Sentry.
const String _crashReportFormUrl =
    'https://docs.google.com/forms/d/e/1FAIpQLSea1Upsp0TSICUQ6ap-bcuYVZZRYkQ9FL2AZFjzhjbndk-cgA/formResponse';
const String _errorMessageEntryId = 'entry.1538321868';
const String _fullReportEntryId = 'entry.1159895757';

/// One recorded error. Always kept on-device; also best-effort submitted to
/// the crash-report form (see [CrashReportService._submitRemote]).
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

/// Catches uncaught Flutter and platform errors, keeps a local log of them,
/// and best-effort reports them automatically to a private Google Form.
///
/// This deliberately isn't a third-party crash-reporting SDK (Crashlytics,
/// Sentry, etc.) — those bundle a native SDK with their own data-collection
/// terms and require a fresh Play Data Safety disclosure to add honestly.
/// A plain form submission is simpler, fully inspectable (it's just an HTTP
/// POST of the fields below, nothing else), and the destination is a form
/// the developer owns outright rather than a third party's platform. Sent
/// fields: the error message, and a JSON blob with timestamp + truncated
/// stack trace — no device identifiers, no user data. This is still an
/// automatic, off-device transmission on every crash, which is disclosed in
/// web/privacy.html and noted for the Play Data Safety form.
///
/// The on-device copy is kept regardless of whether the remote submission
/// succeeds (no network at crash time, etc.), and is what powers Profile >
/// Report a Problem as a manual fallback/backup.
class CrashReportService {
  CrashReportService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

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
  /// [maxStoredReports], and best-effort submits it to the crash-report
  /// form. Exposed directly (not just via [install]'s global handlers) so
  /// it's testable without mutating process-wide error hooks.
  Future<void> recordError(String message, StackTrace? stack) async {
    final rawStack = stack?.toString() ?? '';
    final report = CrashReport(
      timestamp: DateTime.now(),
      message: message,
      stackTrace: rawStack.length > _maxStackTraceChars
          ? rawStack.substring(0, _maxStackTraceChars)
          : rawStack,
    );

    try {
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

    unawaited(_submitRemote(report));
  }

  /// Best-effort only: a failed network call must never compound a crash,
  /// and the on-device copy above already covers the case where this fails
  /// (no network at crash time, form unreachable, etc.).
  Future<void> _submitRemote(CrashReport report) async {
    try {
      await _httpClient.post(
        Uri.parse(_crashReportFormUrl),
        body: {
          _errorMessageEntryId: report.message,
          _fullReportEntryId: jsonEncode(report.toJson()),
        },
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort only.
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
