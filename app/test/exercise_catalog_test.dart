import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';

void main() {
  test('ExerciseCatalog covers every ExerciseType exactly once', () {
    final catalogTypes =
        ExerciseCatalog.all.map((exercise) => exercise.type).toList();

    expect(catalogTypes, isNotEmpty);
    expect(
      catalogTypes.toSet(),
      equals(ExerciseType.values.toSet()),
      reason: 'Every ExerciseType needs a catalog entry, and vice versa.',
    );
    expect(
      catalogTypes.length,
      catalogTypes.toSet().length,
      reason: 'A type must not appear twice in the catalog.',
    );
  });

  test('every catalog entry is presentable', () {
    for (final exercise in ExerciseCatalog.all) {
      expect(exercise.name, isNotEmpty, reason: '${exercise.type} name');
      expect(exercise.description, isNotEmpty,
          reason: '${exercise.type} description');
      expect(exercise.instructions, isNotEmpty,
          reason: '${exercise.type} instructions');
      expect(exercise.muscleGroup, isNotEmpty,
          reason: '${exercise.type} muscleGroup');
    }
  });

  test('exerciseForType returns a fresh analyzer instance', () {
    for (final type in ExerciseType.values) {
      final first = ExerciseCatalog.exerciseForType(type);
      final second = ExerciseCatalog.exerciseForType(type);

      expect(first.type, type);
      expect(
        identical(first.analyzer, second.analyzer),
        isFalse,
        reason: '$type must get a fresh analyzer per session.',
      );
    }
  });
}
