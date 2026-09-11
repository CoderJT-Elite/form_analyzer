import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/services/crash_report_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty', () async {
    final reports = await CrashReportService().loadReports();
    expect(reports, isEmpty);
  });

  test('records an error and makes it loadable', () async {
    final service = CrashReportService();
    await service.recordError('Something broke', StackTrace.current);

    final reports = await service.loadReports();
    expect(reports, hasLength(1));
    expect(reports.first.message, 'Something broke');
    expect(reports.first.stackTrace, isNotEmpty);
  });

  test('keeps only the most recent maxStoredReports entries', () async {
    final service = CrashReportService();
    for (var i = 0; i < CrashReportService.maxStoredReports + 5; i++) {
      await service.recordError('error $i', null);
    }

    final reports = await service.loadReports();
    expect(reports, hasLength(CrashReportService.maxStoredReports));
    // Oldest entries should have been dropped, newest kept.
    expect(reports.first.message, 'error 5');
    expect(reports.last.message,
        'error ${CrashReportService.maxStoredReports + 4}');
  });

  test('clearReports empties the log', () async {
    final service = CrashReportService();
    await service.recordError('boom', null);
    expect(await service.loadReports(), isNotEmpty);

    await service.clearReports();
    expect(await service.loadReports(), isEmpty);
  });

  test('recording never throws, even with a null stack trace', () async {
    final service = CrashReportService();
    await expectLater(
      service.recordError('no stack here', null),
      completes,
    );
  });
}
