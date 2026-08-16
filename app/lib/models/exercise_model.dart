import '../logic/exercise_analyzer.dart';

// Persisted by name in stored sessions, so existing values must keep their
// spelling. New values may be appended freely.
enum ExerciseType {
  squat,
  pushup,
  lunge,
  plank,
  overheadPress,
  gluteBridge,
  situp,
  jumpingJack,
  wallSit,
  sidePlank,
}

class Exercise {
  final String name;
  final String description;
  final String instructions;
  final String muscleGroup;
  final String difficulty;
  final String iconAsset;
  final ExerciseType type;
  final ExerciseAnalyzer analyzer;

  Exercise({
    required this.name,
    required this.description,
    required this.instructions,
    required this.muscleGroup,
    required this.difficulty,
    required this.iconAsset,
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
  final double rating; // 0.0 to 5.0
  final List<String> feedback;

  /// Per-rep detail backing the post-set report. Empty for sets recorded
  /// before this was captured, so anything reading it must tolerate that.
  final List<RepRecord> repRecords;

  ExerciseSet({
    required this.reps,
    this.duration,
    this.targetReps,
    this.isPR = false,
    required this.timestamp,
    this.rating = 1.0,
    this.feedback = const [],
    this.repRecords = const [],
  });

  /// Average lowering time across reps that measured it, or null when unknown.
  Duration? get averageEccentric {
    final measured =
        repRecords.where((record) => record.eccentricMs > 0).toList();
    if (measured.isEmpty) return null;
    final total =
        measured.fold<int>(0, (sum, record) => sum + record.eccentricMs);
    return Duration(milliseconds: total ~/ measured.length);
  }

  RepRecord? get bestRep {
    if (repRecords.isEmpty) return null;
    return repRecords.reduce((a, b) => b.score > a.score ? b : a);
  }

  RepRecord? get worstRep {
    if (repRecords.isEmpty) return null;
    return repRecords.reduce((a, b) => b.score < a.score ? b : a);
  }

  Map<String, dynamic> toJson() => {
    'reps': reps,
    'durationMs': duration?.inMilliseconds,
    'targetReps': targetReps,
    'isPR': isPR,
    'timestamp': timestamp.toIso8601String(),
    'rating': rating,
    'feedback': feedback,
    'repRecords': repRecords.map((record) => record.toJson()).toList(),
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
    repRecords: ((json['repRecords'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RepRecord.fromJson)
        .toList(),
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
