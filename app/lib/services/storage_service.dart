import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exercise_model.dart';

/// What an import actually did, so the UI can tell the user rather than just
/// claiming success.
class ImportResult {
  final int sessionsAdded;
  final int routinesAdded;
  final int sessionsSkipped;

  const ImportResult({
    required this.sessionsAdded,
    required this.routinesAdded,
    required this.sessionsSkipped,
  });

  String get summary {
    if (sessionsAdded == 0 && routinesAdded == 0) {
      return 'Nothing new to import — your history is already up to date.';
    }
    final parts = <String>[
      if (sessionsAdded > 0)
        '$sessionsAdded workout${sessionsAdded == 1 ? '' : 's'}',
      if (routinesAdded > 0)
        '$routinesAdded routine${routinesAdded == 1 ? '' : 's'}',
    ];
    return 'Restored ${parts.join(' and ')}.';
  }
}

class StorageService {
  static const String _sessionsKey = 'workout_sessions_v2';
  static const String _routinesKey = 'workout_routines_v1';
  static const String _routineSessionsKey = 'routine_sessions_v1';
  static const String _voiceCoachingEnabledKey = 'voice_coaching_enabled_v1';
  static const String _hapticFeedbackEnabledKey = 'haptic_feedback_enabled_v1';
  static const String _disclaimerAcceptedKey = 'health_disclaimer_accepted_v1';

  Future<void> saveSession(WorkoutSession session) async {
    final prefs = await SharedPreferences.getInstance();
    // Loaded once and reused for every PR check. This used to be re-read from
    // disk for each set in the session.
    final sessions = await loadSessions();

    final updatedSets = <ExerciseSet>[];
    for (var set in session.sets) {
      updatedSets.add(
        ExerciseSet(
          reps: set.reps,
          duration: set.duration,
          targetReps: set.targetReps,
          isPR: _isPersonalRecord(sessions, session.exerciseType, set),
          timestamp: set.timestamp,
          rating: set.rating,
          feedback: set.feedback,
          // Must be carried across: rebuilding the set without this silently
          // dropped the per-rep detail the summary report is built from.
          repRecords: set.repRecords,
        ),
      );
    }

    final updatedSession = WorkoutSession(
      id: session.id,
      date: session.date,
      exerciseType: session.exerciseType,
      sets: updatedSets,
      overallRating: session.overallRating,
      overallFeedback: session.overallFeedback,
    );

    sessions.insert(0, updatedSession);
    final jsonList = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_sessionsKey, jsonEncode(jsonList));
  }

  bool _isPersonalRecord(
    List<WorkoutSession> history,
    ExerciseType type,
    ExerciseSet newSet,
  ) {
    for (var session in history.where((s) => s.exerciseType == type)) {
      for (var set in session.sets) {
        if (set.reps >= newSet.reps) return false;
      }
    }
    return newSet.reps > 0 || (newSet.duration?.inSeconds ?? 0) > 0;
  }

  Future<List<WorkoutSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_sessionsKey);
    if (jsonString == null) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return _decodeList(jsonList, WorkoutSession.fromJson);
    } catch (e) {
      debugPrint('Error loading sessions: $e');
      return [];
    }
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionsKey);
    await prefs.remove(_routineSessionsKey);
  }

  // --- Routine Management ---

  Future<void> saveRoutine(WorkoutRoutine routine) async {
    final prefs = await SharedPreferences.getInstance();
    final routines = await loadRoutines();

    final index = routines.indexWhere((r) => r.id == routine.id);
    if (index != -1) {
      routines[index] = routine;
    } else {
      routines.add(routine);
    }

    final jsonList = routines.map((r) => r.toJson()).toList();
    await prefs.setString(_routinesKey, jsonEncode(jsonList));
  }

  Future<List<WorkoutRoutine>> loadRoutines() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_routinesKey);
    if (jsonString == null) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return _decodeList(jsonList, WorkoutRoutine.fromJson);
    } catch (e) {
      debugPrint('Error loading routines: $e');
      return [];
    }
  }

  Future<void> deleteRoutine(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final routines = await loadRoutines();
    routines.removeWhere((r) => r.id == id);
    final jsonList = routines.map((r) => r.toJson()).toList();
    await prefs.setString(_routinesKey, jsonEncode(jsonList));
  }

  // --- Routine Sessions ---

  Future<void> saveRoutineSession(RoutineSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadRoutineSessions();
    sessions.insert(0, session);

    final jsonList = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_routineSessionsKey, jsonEncode(jsonList));

    // Also save individual workout sessions to the main history
    for (var ws in session.exerciseSessions) {
      await saveSession(ws);
    }
  }

  Future<List<RoutineSession>> loadRoutineSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_routineSessionsKey);
    if (jsonString == null) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return _decodeList(jsonList, RoutineSession.fromJson);
    } catch (e) {
      debugPrint('Error loading routine sessions: $e');
      return [];
    }
  }

  // Legacy support
  Future<List<String>> loadHistory() async {
    final sessions = await loadSessions();
    return sessions
        .map(
          (s) =>
              '${s.exerciseType.name}: ${s.totalReps} total reps on ${s.date}',
        )
        .toList();
  }

  Future<void> setVoiceCoachingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceCoachingEnabledKey, enabled);
  }

  Future<bool> isVoiceCoachingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_voiceCoachingEnabledKey) ?? true;
  }

  Future<void> setHapticFeedbackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticFeedbackEnabledKey, enabled);
  }

  Future<bool> isHapticFeedbackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hapticFeedbackEnabledKey) ?? true;
  }

  Future<bool> hasAcceptedHealthDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_disclaimerAcceptedKey) ?? false;
  }

  Future<void> setHealthDisclaimerAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disclaimerAcceptedKey, true);
  }

  // ---------------------------------------------------------------------
  // Backup and restore
  //
  // There is no server, so a user who uninstalls or changes phone would
  // otherwise lose everything. Android auto-backup covers the common case;
  // this gives them a file they own and control.
  // ---------------------------------------------------------------------

  /// Bumped when the shape of an exported file changes.
  static const int backupFormatVersion = 1;

  /// Serialise all workout data to a JSON string.
  Future<String> exportToJson() async {
    final sessions = await loadSessions();
    final routines = await loadRoutines();
    final routineSessions = await loadRoutineSessions();

    return const JsonEncoder.withIndent('  ').convert({
      'formatVersion': backupFormatVersion,
      'app': 'form_analyzer',
      'exportedAt': DateTime.now().toIso8601String(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'routines': routines.map((r) => r.toJson()).toList(),
      'routineSessions': routineSessions.map((r) => r.toJson()).toList(),
    });
  }

  /// Restore from a previously exported file.
  ///
  /// Malformed individual entries are skipped rather than failing the whole
  /// import, matching how normal loading behaves. Throws [FormatException]
  /// only when the file isn't a Form Analyzer backup at all.
  Future<ImportResult> importFromJson(
    String jsonString, {
    bool replaceExisting = false,
  }) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e) {
      throw const FormatException('That file is not valid JSON.');
    }

    if (decoded is! Map<String, dynamic> || decoded['app'] != 'form_analyzer') {
      throw const FormatException(
        'That file does not look like a Form Analyzer backup.',
      );
    }

    final importedSessions = _decodeList(
      (decoded['sessions'] as List?) ?? const [],
      WorkoutSession.fromJson,
    );
    final importedRoutines = _decodeList(
      (decoded['routines'] as List?) ?? const [],
      WorkoutRoutine.fromJson,
    );
    final importedRoutineSessions = _decodeList(
      (decoded['routineSessions'] as List?) ?? const [],
      RoutineSession.fromJson,
    );

    final sessions = replaceExisting ? <WorkoutSession>[] : await loadSessions();
    final routines = replaceExisting ? <WorkoutRoutine>[] : await loadRoutines();
    final routineSessions =
        replaceExisting ? <RoutineSession>[] : await loadRoutineSessions();

    // Merge on id so importing the same file twice doesn't duplicate history.
    final existingSessionIds = sessions.map((s) => s.id).toSet();
    final newSessions = importedSessions
        .where((s) => !existingSessionIds.contains(s.id))
        .toList();

    final existingRoutineIds = routines.map((r) => r.id).toSet();
    final newRoutines =
        importedRoutines.where((r) => !existingRoutineIds.contains(r.id)).toList();

    final existingRoutineSessionIds = routineSessions.map((r) => r.id).toSet();
    final newRoutineSessions = importedRoutineSessions
        .where((r) => !existingRoutineSessionIds.contains(r.id))
        .toList();

    sessions.addAll(newSessions);
    routines.addAll(newRoutines);
    routineSessions.addAll(newRoutineSessions);

    sessions.sort((a, b) => b.date.compareTo(a.date));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionsKey,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
    await prefs.setString(
      _routinesKey,
      jsonEncode(routines.map((r) => r.toJson()).toList()),
    );
    await prefs.setString(
      _routineSessionsKey,
      jsonEncode(routineSessions.map((r) => r.toJson()).toList()),
    );

    return ImportResult(
      sessionsAdded: newSessions.length,
      routinesAdded: newRoutines.length,
      sessionsSkipped: importedSessions.length - newSessions.length,
    );
  }

  List<T> _decodeList<T>(
    List<dynamic> rawList,
    T Function(Map<String, dynamic>) factory,
  ) {
    final decoded = <T>[];
    for (final item in rawList) {
      if (item is! Map<String, dynamic>) {
        debugPrint('Skipping malformed persisted item: unexpected type.');
        continue;
      }
      try {
        decoded.add(factory(item));
      } catch (e) {
        debugPrint('Skipping malformed persisted item: $e');
      }
    }
    return decoded;
  }
}
