import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/services/crash_report_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Records every request instead of making a real network call -- tests must
/// never actually hit the live crash-report form.
class _RecordingHttpClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
  }
}

class _ThrowingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw Exception('no network');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty', () async {
    final reports =
        await CrashReportService(httpClient: _RecordingHttpClient())
            .loadReports();
    expect(reports, isEmpty);
  });

  test('records an error locally and makes it loadable', () async {
    final service = CrashReportService(httpClient: _RecordingHttpClient());
    await service.recordError('Something broke', StackTrace.current);

    final reports = await service.loadReports();
    expect(reports, hasLength(1));
    expect(reports.first.message, 'Something broke');
    expect(reports.first.stackTrace, isNotEmpty);
  });

  test('keeps only the most recent maxStoredReports entries', () async {
    final service = CrashReportService(httpClient: _RecordingHttpClient());
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
    final service = CrashReportService(httpClient: _RecordingHttpClient());
    await service.recordError('boom', null);
    expect(await service.loadReports(), isNotEmpty);

    await service.clearReports();
    expect(await service.loadReports(), isEmpty);
  });

  test('recording never throws, even with a null stack trace', () async {
    final service = CrashReportService(httpClient: _RecordingHttpClient());
    await expectLater(
      service.recordError('no stack here', null),
      completes,
    );
  });

  group('remote submission', () {
    test('posts the error message and a JSON report to the form', () async {
      final client = _RecordingHttpClient();
      final service = CrashReportService(httpClient: client);

      await service.recordError('Something broke', StackTrace.current);

      expect(client.requests, hasLength(1));
      final request = client.requests.single as http.Request;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        contains('docs.google.com/forms/d/e/'),
      );
      expect(request.bodyFields['entry.1538321868'], 'Something broke');

      final fullReport =
          jsonDecode(request.bodyFields['entry.1159895757']!)
              as Map<String, dynamic>;
      expect(fullReport['message'], 'Something broke');
      expect(fullReport, contains('timestamp'));
      expect(fullReport, contains('stackTrace'));
    });

    test('a failed submission does not affect the local record', () async {
      final service = CrashReportService(httpClient: _ThrowingHttpClient());

      await expectLater(
        service.recordError('offline crash', null),
        completes,
      );

      final reports = await service.loadReports();
      expect(reports, hasLength(1));
      expect(reports.first.message, 'offline crash');
    });
  });
}
