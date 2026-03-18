import 'package:flutter/material.dart';
import '../logic/exercise_analyzer.dart';

enum ExerciseType { squat, pushup, lunge, plank, overheadPress }

class Exercise {
  final String name;
  final String description;
  final String instructions;
  final String muscleGroup;
  final String difficulty;
  final IconData icon;
  final ExerciseType type;
  final ExerciseAnalyzer analyzer;

  Exercise({
    required this.name,
    required this.description,
    required this.instructions,
    required this.muscleGroup,
    required this.difficulty,
    required this.icon,
    required this.type,
    required this.analyzer,
  });
}

class ExerciseSet {
  final int reps;
  final Duration? duration; // For time-based exercises like Plank
  final int? targetReps;
  final bool isPR;
  final DateTime timestamp;
  final double rating; // 0.0 to 1.0 or 1 to 5
  final List<String> feedback;

  ExerciseSet({
    required this.reps,
    this.duration,
    this.targetReps,
    this.isPR = false,
    required this.timestamp,
    this.rating = 1.0,
    this.feedback = const [],
  });

  Map<String, dynamic> toJson() => {
    'reps': reps,
    'durationMs': duration?.inMilliseconds,
    'targetReps': targetReps,
    'isPR': isPR,
    'timestamp': timestamp.toIso8601String(),
    'rating': rating,
    'feedback': feedback,
  };

  factory ExerciseSet.fromJson(Map<String, dynamic> json) => ExerciseSet(
    reps: json['reps'],
    duration: json['durationMs'] != null
        ? Duration(milliseconds: json['durationMs'])
        : null,
    targetReps: json['targetReps'],
    isPR: json['isPR'] ?? false,
    timestamp: DateTime.parse(json['timestamp']),
    rating: (json['rating'] ?? 1.0).toDouble(),
    feedback: List<String>.from(json['feedback'] ?? []),
  );
}

class WorkoutSession {
  final String id;
  final DateTime date;
  final ExerciseType exerciseType;
  final List<ExerciseSet> sets;
  final double? overallRating;
  final List<String> overallFeedback;

  WorkoutSession({
    required this.id,
    required this.date,
    required this.exerciseType,
    required this.sets,
    this.overallRating,
    this.overallFeedback = const [],
  });

  int get totalReps => sets.fold(0, (sum, set) => sum + set.reps);

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'exerciseType': exerciseType.name,
    'sets': sets.map((s) => s.toJson()).toList(),
    'overallRating': overallRating,
    'overallFeedback': overallFeedback,
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'],
    date: DateTime.parse(json['date']),
    exerciseType: ExerciseType.values.firstWhere(
      (e) => e.name == json['exerciseType'],
    ),
    sets: (json['sets'] as List).map((s) => ExerciseSet.fromJson(s)).toList(),
    overallRating: (json['overallRating'] as num?)?.toDouble(),
    overallFeedback: List<String>.from(json['overallFeedback'] ?? []),
  );
}

class WorkoutRoutine {
  final String id;
  final String name;
  final List<ExerciseType> exercises;
  final List<int?> targetReps; // Optional target reps for each exercise

  WorkoutRoutine({
    required this.id,
    required this.name,
    required this.exercises,
    this.targetReps = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'exercises': exercises.map((e) => e.name).toList(),
    'targetReps': targetReps,
  };

  factory WorkoutRoutine.fromJson(Map<String, dynamic> json) => WorkoutRoutine(
    id: json['id'],
    name: json['name'],
    exercises: (json['exercises'] as List)
        .map((e) => ExerciseType.values.firstWhere((v) => v.name == e))
        .toList(),
    targetReps: List<int?>.from(json['targetReps'] ?? []),
  );
}

class RoutineSession {
  final String id;
  final String routineId;
  final String routineName;
  final DateTime date;
  final List<WorkoutSession> exerciseSessions;

  RoutineSession({
    required this.id,
    required this.routineId,
    required this.routineName,
    required this.date,
    required this.exerciseSessions,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'routineId': routineId,
    'routineName': routineName,
    'date': date.toIso8601String(),
    'exerciseSessions': exerciseSessions.map((s) => s.toJson()).toList(),
  };

  factory RoutineSession.fromJson(Map<String, dynamic> json) => RoutineSession(
    id: json['id'],
    routineId: json['routineId'],
    routineName: json['routineName'],
    date: DateTime.parse(json['date']),
    exerciseSessions: (json['exerciseSessions'] as List)
        .map((s) => WorkoutSession.fromJson(s))
        .toList(),
  );
}
