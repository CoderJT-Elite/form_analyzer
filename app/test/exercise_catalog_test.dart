import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';

void main() {
  test('ExerciseCatalog includes only squat and pushup for MVP', () {
    final catalogTypes = ExerciseCatalog.all.map((exercise) => exercise.type).toSet();
    expect(catalogTypes, equals({ExerciseType.squat, ExerciseType.pushup}));
  });

  test('exerciseForType returns a fresh analyzer instance', () {
    final first = ExerciseCatalog.exerciseForType(ExerciseType.squat);
    final second = ExerciseCatalog.exerciseForType(ExerciseType.squat);
    expect(identical(first.analyzer, second.analyzer), isFalse);
  });
}
