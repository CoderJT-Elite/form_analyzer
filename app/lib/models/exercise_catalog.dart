import 'package:flutter/material.dart';
import '../logic/exercise_analyzer.dart';
import 'exercise_model.dart';

/// Static definition of one exercise, without a live analyzer attached.
///
/// The catalog used to hold a constructed `ExerciseAnalyzer` per entry. Those
/// instances are stateful and were shared process-wide, so anything reading
/// `ExerciseCatalog.all[i].analyzer` directly picked up rep counts and issues
/// left over from an earlier workout. Holding a factory instead makes that
/// mistake impossible to express.
class ExerciseDefinition {
  final String name;
  final String description;
  final String instructions;
  final String muscleGroup;
  final String difficulty;
  final IconData icon;
  final ExerciseType type;
  final ExerciseAnalyzer Function() createAnalyzer;

  const ExerciseDefinition({
    required this.name,
    required this.description,
    required this.instructions,
    required this.muscleGroup,
    required this.difficulty,
    required this.icon,
    required this.type,
    required this.createAnalyzer,
  });

  Exercise toExercise() => Exercise(
        name: name,
        description: description,
        instructions: instructions,
        muscleGroup: muscleGroup,
        difficulty: difficulty,
        icon: icon,
        type: type,
        analyzer: createAnalyzer(),
      );
}

class ExerciseCatalog {
  static const List<ExerciseDefinition> definitions = [
    ExerciseDefinition(
      name: 'SQUATS',
      description: 'Perfect your depth and torso angle',
      instructions:
          'Stand side-on to the camera with feet shoulder-width apart. Lower your hips until thighs are parallel to the floor.',
      muscleGroup: 'Quadriceps, Glutes',
      difficulty: 'Intermediate',
      icon: Icons.fitness_center_rounded,
      type: ExerciseType.squat,
      createAnalyzer: SquatAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'PUSH-UPS',
      description: 'Build upper body and core strength',
      instructions:
          'Set up side-on to the camera. Keep your body in a straight line and lower your chest until your elbows reach 90 degrees.',
      muscleGroup: 'Chest, Triceps, Shoulders',
      difficulty: 'Beginner',
      icon: Icons.horizontal_rule_rounded,
      type: ExerciseType.pushup,
      createAnalyzer: PushupAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'LUNGES',
      description: 'Build single-leg strength and balance',
      instructions:
          'Stand side-on to the camera. Step forward and lower your hips until both knees are bent at about 90 degrees.',
      muscleGroup: 'Quadriceps, Glutes, Hamstrings',
      difficulty: 'Intermediate',
      icon: Icons.directions_walk_rounded,
      type: ExerciseType.lunge,
      createAnalyzer: LungeAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'OVERHEAD PRESS',
      description: 'Build shoulder and arm strength',
      instructions:
          'Stand side-on to the camera. Press your arms straight overhead from shoulder height, then lower with control.',
      muscleGroup: 'Shoulders, Triceps',
      difficulty: 'Intermediate',
      icon: Icons.arrow_upward_rounded,
      type: ExerciseType.overheadPress,
      createAnalyzer: OverheadPressAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'PLANK',
      description: 'Build core stability and endurance',
      instructions:
          'Face side-on to the camera. Hold your body in a straight line from head to heels, supported on forearms and toes.',
      muscleGroup: 'Core, Shoulders',
      difficulty: 'Beginner',
      icon: Icons.remove_rounded,
      type: ExerciseType.plank,
      createAnalyzer: PlankAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'GLUTE BRIDGE',
      description: 'Wake up your glutes and hips',
      instructions:
          'Lie on your back side-on to the camera, knees bent. Drive your hips up until your body forms a straight line, then lower slowly.',
      muscleGroup: 'Glutes, Hamstrings',
      difficulty: 'Beginner',
      icon: Icons.arrow_drop_up_rounded,
      type: ExerciseType.gluteBridge,
      createAnalyzer: GluteBridgeAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'SIT-UPS',
      description: 'Train your abs through a full range',
      instructions:
          'Lie on your back side-on to the camera, knees bent. Curl your torso up toward your knees, then lower under control.',
      muscleGroup: 'Core, Hip Flexors',
      difficulty: 'Beginner',
      icon: Icons.self_improvement_rounded,
      type: ExerciseType.situp,
      createAnalyzer: SitupAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'JUMPING JACKS',
      description: 'Raise your heart rate and warm up',
      instructions:
          'Face the camera. Jump your feet wide and sweep your arms all the way overhead, then return to the start.',
      muscleGroup: 'Full Body, Cardio',
      difficulty: 'Beginner',
      icon: Icons.accessibility_new_rounded,
      type: ExerciseType.jumpingJack,
      createAnalyzer: JumpingJackAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'WALL SIT',
      description: 'Burn out your quads with a static hold',
      instructions:
          'Sit against a wall side-on to the camera with your knees at about 90 degrees. Hold the position.',
      muscleGroup: 'Quadriceps, Glutes',
      difficulty: 'Beginner',
      icon: Icons.chair_rounded,
      type: ExerciseType.wallSit,
      createAnalyzer: WallSitAnalyzer.new,
    ),
    ExerciseDefinition(
      name: 'SIDE PLANK',
      description: 'Strengthen your obliques and stabilisers',
      instructions:
          'Lie on one side facing the camera edge-on, propped on your forearm. Lift your hips so your body makes a straight line and hold.',
      muscleGroup: 'Core, Obliques',
      difficulty: 'Intermediate',
      icon: Icons.swap_horiz_rounded,
      type: ExerciseType.sidePlank,
      createAnalyzer: SidePlankAnalyzer.new,
    ),
  ];

  /// Every exercise, each with its own freshly built analyzer.
  static List<Exercise> get all =>
      definitions.map((definition) => definition.toExercise()).toList();

  /// An exercise with a fresh, unused analyzer — what a new workout needs.
  static Exercise exerciseForType(ExerciseType type) =>
      definitionForType(type).toExercise();

  /// Static details only — no analyzer is constructed. Use this for anything
  /// that just needs a name or an icon.
  static ExerciseDefinition definitionForType(ExerciseType type) {
    return definitions.firstWhere(
      (definition) => definition.type == type,
      orElse: () => definitions.first,
    );
  }
}
