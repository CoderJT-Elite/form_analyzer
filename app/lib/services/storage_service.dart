import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exercise_model.dart';

class StorageService {
  static const String _sessionsKey = 'workout_sessions_v2';
  static const String _routinesKey = 'workout_routines_v1';
  static const String _routineSessionsKey = 'routine_sessions_v1';

  Future<void> saveSession(WorkoutSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();

    // Check for PRs in the current session
    final updatedSets = <ExerciseSet>[];
    for (var set in session.sets) {
      bool isPR = await _checkIfPR(session.exerciseType, set);
      updatedSets.add(
        ExerciseSet(
          reps: set.reps,
          duration: set.duration,
          targetReps: set.targetReps,
          isPR: isPR,
          timestamp: set.timestamp,
          rating: set.rating,
          feedback: set.feedback,
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

  Future<bool> _checkIfPR(ExerciseType type, ExerciseSet newSet) async {
    final sessions = await loadSessions();
    final exerciseSessions = sessions.where((s) => s.exerciseType == type);

    for (var session in exerciseSessions) {
      for (var set in session.sets) {
        if (type == ExerciseType.plank) {
          if (set.duration != null &&
              newSet.duration != null &&
              set.duration!.inMilliseconds >= newSet.duration!.inMilliseconds) {
            return false;
          }
        } else {
          if (set.reps >= newSet.reps) {
            return false;
          }
        }
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
      return jsonList.map((j) => WorkoutSession.fromJson(j)).toList();
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
      return jsonList.map((j) => WorkoutRoutine.fromJson(j)).toList();
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
      return jsonList.map((j) => RoutineSession.fromJson(j)).toList();
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
}
