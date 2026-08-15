import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutSession session(String id, {ExerciseType type = ExerciseType.squat}) {
  return WorkoutSession(
    id: id,
    date: DateTime(2026, 8, int.parse(id.substring(id.length - 1)) + 1),
    exerciseType: type,
    sets: [
      ExerciseSet(
        reps: 5,
        timestamp: DateTime(2026, 8, 13),
        rating: 4.0,
        feedback: const ['Rounded Back'],
        repRecords: const [
          RepRecord(
            index: 1,
            score: 0.8,
            issues: ['Rounded Back'],
            eccentricMs: 1300,
            concentricMs: 900,
          ),
        ],
      ),
    ],
    overallRating: 4.0,
    overallFeedback: const ['Rounded Back'],
  );
}

void main() {
  late StorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
  });

  test('saving a session keeps its per-rep detail', () async {
    await storage.saveSession(session('1'));

    final loaded = await storage.loadSessions();

    expect(loaded, hasLength(1));
    expect(
      loaded.single.sets.single.repRecords,
      hasLength(1),
      reason: 'saveSession rebuilds each set and must carry rep records over.',
    );
    expect(loaded.single.sets.single.repRecords.single.eccentricMs, 1300);
  });

  test('export produces a restorable file', () async {
    await storage.saveSession(session('1'));
    await storage.saveSession(session('2'));

    final exported = await storage.exportToJson();
    final decoded = jsonDecode(exported) as Map<String, dynamic>;

    expect(decoded['app'], 'form_analyzer');
    expect(decoded['formatVersion'], StorageService.backupFormatVersion);
    expect(decoded['sessions'], hasLength(2));
  });

  test('restores history onto a fresh install', () async {
    await storage.saveSession(session('1'));
    await storage.saveSession(session('2'));
    final backup = await storage.exportToJson();

    // Simulate a reinstall: everything gone.
    SharedPreferences.setMockInitialValues({});
    final freshInstall = StorageService();
    expect(await freshInstall.loadSessions(), isEmpty);

    final result = await freshInstall.importFromJson(backup);

    expect(result.sessionsAdded, 2);
    final restored = await freshInstall.loadSessions();
    expect(restored, hasLength(2));
    expect(restored.first.sets.single.repRecords.single.score, 0.8);
  });

  test('importing the same file twice does not duplicate history', () async {
    await storage.saveSession(session('1'));
    final backup = await storage.exportToJson();

    final first = await storage.importFromJson(backup);
    final second = await storage.importFromJson(backup);

    expect(first.sessionsAdded, 0, reason: 'Already present.');
    expect(second.sessionsAdded, 0);
    expect(await storage.loadSessions(), hasLength(1));
  });

  test('merges a backup into existing history without losing either', () async {
    await storage.saveSession(session('1'));
    final backup = await storage.exportToJson();

    SharedPreferences.setMockInitialValues({});
    final other = StorageService();
    await other.saveSession(session('9'));

    final result = await other.importFromJson(backup);

    expect(result.sessionsAdded, 1);
    final all = await other.loadSessions();
    expect(all.map((s) => s.id).toSet(), {'1', '9'});
  });

  test('rejects a file that is not a Form Analyzer backup', () async {
    expect(
      () => storage.importFromJson('{"app":"something_else"}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a file that is not JSON at all', () async {
    expect(
      () => storage.importFromJson('this is not json'),
      throwsA(isA<FormatException>()),
    );
  });

  test('skips individual malformed entries rather than failing outright',
      () async {
    final payload = jsonEncode({
      'app': 'form_analyzer',
      'formatVersion': 1,
      'sessions': [
        session('1').toJson(),
        {'id': 'broken'}, // missing required fields
        'not even a map',
      ],
      'routines': <dynamic>[],
      'routineSessions': <dynamic>[],
    });

    final result = await storage.importFromJson(payload);

    expect(result.sessionsAdded, 1);
    expect(await storage.loadSessions(), hasLength(1));
  });

  test('summary describes what happened', () async {
    await storage.saveSession(session('1'));
    final backup = await storage.exportToJson();

    SharedPreferences.setMockInitialValues({});
    final fresh = StorageService();
    final result = await fresh.importFromJson(backup);

    expect(result.summary, contains('1 workout'));
    expect(const ImportResult(
      sessionsAdded: 0,
      routinesAdded: 0,
      sessionsSkipped: 0,
    ).summary, contains('Nothing new'));
  });

  test('health disclaimer acceptance persists', () async {
    expect(await storage.hasAcceptedHealthDisclaimer(), isFalse);

    await storage.setHealthDisclaimerAccepted();

    expect(await storage.hasAcceptedHealthDisclaimer(), isTrue);
  });
}
