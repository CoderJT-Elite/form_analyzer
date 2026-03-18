import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/core/app_constants.dart';

void main() {
  group('SquatAnalyzer Tests', () {
    late SquatAnalyzer analyzer;

    setUp(() {
      analyzer = SquatAnalyzer();
    });

    test('Initial state is correct', () {
      expect(analyzer.repCount, 0);
      expect(analyzer.phase, RepPhase.up);
      expect(analyzer.repScores, isEmpty);
      expect(analyzer.allRepIssues, isEmpty);
    });

    test('Reset clears all tracking data', () {
      analyzer.repCount = 5;
      analyzer.repScores.add(0.8);
      analyzer.allRepIssues.add(['Test Issue']);

      analyzer.reset();

      expect(analyzer.repCount, 0);
      expect(analyzer.repScores, isEmpty);
      expect(analyzer.allRepIssues, isEmpty);
    });

    test('getPerformanceMetrics calculates correct averages', () {
      // Mock some rep data
      analyzer.repScores.addAll([0.8, 1.0, 0.6]);
      analyzer.allRepIssues.addAll([
        ['Rounded Back'],
        [],
        ['Rounded Back', 'Insufficient Depth'],
      ]);
      analyzer.repCount = 3;

      final metrics = analyzer.getPerformanceMetrics();

      expect(metrics.totalReps, 3);
      expect(
        metrics.averageFormScore,
        closeTo(4.0, 0.1),
      ); // (0.8+1.0+0.6)/3 * 5 = 4.0
      expect(metrics.commonIssues, contains('Rounded Back'));
      expect(metrics.commonIssues, contains('Insufficient Depth'));
      expect(metrics.perfectReps, 1);
    });
  });
}
