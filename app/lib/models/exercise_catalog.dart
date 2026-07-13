import 'package:flutter/material.dart';
import '../logic/exercise_analyzer.dart';
import 'exercise_model.dart';

class ExerciseCatalog {
  static final List<Exercise> all = [
    Exercise(
      name: 'SQUATS',
      description: 'Perfect your depth and torso angle',
      instructions:
          'Stand with feet shoulder-width apart. Lower your hips until thighs are parallel to the floor.',
      muscleGroup: 'Quadriceps, Glutes',
      difficulty: 'Intermediate',
      icon: Icons.fitness_center_rounded,
      type: ExerciseType.squat,
      analyzer: SquatAnalyzer(),
    ),
    Exercise(
      name: 'PUSH-UPS',
      description: 'Build upper body and core strength',
      instructions:
          'Keep your body in a straight line. Lower your chest until it nearly touches the floor.',
      muscleGroup: 'Chest, Triceps, Shoulders',
      difficulty: 'Beginner',
      icon: Icons.horizontal_rule_rounded,
      type: ExerciseType.pushup,
      analyzer: PushupAnalyzer(),
    ),
    Exercise(
      name: 'LUNGES',
      description: 'Build single-leg strength and balance',
      instructions:
          'Step forward and lower your hips until both knees are bent at about 90 degrees.',
      muscleGroup: 'Quadriceps, Glutes, Hamstrings',
      difficulty: 'Intermediate',
      icon: Icons.directions_walk_rounded,
      type: ExerciseType.lunge,
      analyzer: LungeAnalyzer(),
    ),
    Exercise(
      name: 'OVERHEAD PRESS',
      description: 'Build shoulder and arm strength',
      instructions:
          'Press your arms straight overhead from shoulder height, then lower with control.',
      muscleGroup: 'Shoulders, Triceps',
      difficulty: 'Intermediate',
      icon: Icons.arrow_upward_rounded,
      type: ExerciseType.overheadPress,
      analyzer: OverheadPressAnalyzer(),
    ),
    Exercise(
      name: 'PLANK',
      description: 'Build core stability and endurance',
      instructions:
          'Hold your body in a straight line from head to heels, supported on forearms and toes.',
      muscleGroup: 'Core, Shoulders',
      difficulty: 'Beginner',
      icon: Icons.remove_rounded,
      type: ExerciseType.plank,
      analyzer: PlankAnalyzer(),
    ),
  ];

  static Exercise exerciseForType(ExerciseType type) {
    final template = templateForType(type);
    return Exercise(
      name: template.name,
      description: template.description,
      instructions: template.instructions,
      muscleGroup: template.muscleGroup,
      difficulty: template.difficulty,
      icon: template.icon,
      type: template.type,
      analyzer: _newAnalyzer(template.type),
    );
  }

  static Exercise templateForType(ExerciseType type) {
    return all.firstWhere(
      (exercise) => exercise.type == type,
      orElse: () => all.first,
    );
  }

  static ExerciseAnalyzer _newAnalyzer(ExerciseType type) {
    switch (type) {
      case ExerciseType.squat:
        return SquatAnalyzer();
      case ExerciseType.pushup:
        return PushupAnalyzer();
      case ExerciseType.lunge:
        return LungeAnalyzer();
      case ExerciseType.plank:
        return PlankAnalyzer();
      case ExerciseType.overheadPress:
        return OverheadPressAnalyzer();
    }
  }
}
