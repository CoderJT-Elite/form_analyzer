import 'package:flutter/material.dart';
import '../logic/exercise_analyzer.dart';

enum ExerciseType { squat, pushup }

class Exercise {
  final String name;
  final String description;
  final IconData icon;
  final ExerciseType type;
  final ExerciseAnalyzer analyzer;

  Exercise({
    required this.name,
    required this.description,
    required this.icon,
    required this.type,
    required this.analyzer,
  });
}

class WorkoutSession {
  final DateTime date;
  final int repCount;
  final ExerciseType exerciseType;

  WorkoutSession({
    required this.date,
    required this.repCount,
    required this.exerciseType,
  });
}
