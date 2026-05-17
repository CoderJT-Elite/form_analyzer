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
      description: 'Improves balance and leg strength',
      instructions:
          'Step forward and lower your back knee until it nearly touches the ground.',
      muscleGroup: 'Hamstrings, Glutes',
      difficulty: 'Beginner',
      icon: Icons.directions_walk_rounded,
      type: ExerciseType.lunge,
      analyzer: LungeAnalyzer(),
    ),
    Exercise(
      name: 'OVERHEAD PRESS',
      description: 'Build powerful shoulders',
      instructions:
          'Press the weights directly overhead while keeping your core tight.',
      muscleGroup: 'Shoulders, Triceps',
      difficulty: 'Intermediate',
      icon: Icons.upload_rounded,
      type: ExerciseType.overheadPress,
      analyzer: OverheadPressAnalyzer(),
    ),
    Exercise(
      name: 'PLANK',
      description: 'The ultimate core endurance test',
      instructions:
          'Hold a straight body position resting on your forearms and toes.',
      muscleGroup: 'Core, Abs',
      difficulty: 'Advanced',
      icon: Icons.view_headline_rounded,
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
    return all.firstWhere((exercise) => exercise.type == type);
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
