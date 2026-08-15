import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/core/app_constants.dart';

/// Build a completed-rep record with just the fields a metrics test cares about.
RepRecord rep(double score, {List<String> issues = const []}) =>
    RepRecord(index: 0, score: score, issues: issues);

void main() {
  group('SquatAnalyzer Tests', () {
    late SquatAnalyzer analyzer;

    setUp(() {
      analyzer = SquatAnalyzer();
    });

    test('Initial state is correct', () {
      expect(analyzer.repCount, 0);
      expect(analyzer.phase, RepPhase.neutral);
      expect(analyzer.repRecords, isEmpty);
      expect(analyzer.repScores, isEmpty);
      expect(analyzer.allRepIssues, isEmpty);
    });

    test('Reset clears all tracking data', () {
      analyzer.repCount = 5;
      analyzer.repRecords.add(rep(0.8, issues: ['Test Issue']));

      analyzer.reset();

      expect(analyzer.repCount, 0);
      expect(analyzer.repRecords, isEmpty);
      expect(analyzer.repScores, isEmpty);
      expect(analyzer.allRepIssues, isEmpty);
    });

    test('getPerformanceMetrics calculates correct averages', () {
      analyzer.repRecords.addAll([
        rep(0.8, issues: ['Rounded Back']),
        rep(1.0),
        rep(0.6, issues: ['Rounded Back', 'Insufficient Depth']),
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

    test('repScores and allRepIssues mirror the stored rep records', () {
      analyzer.repRecords.addAll([
        rep(0.5, issues: ['A']),
        rep(1.0),
      ]);

      expect(analyzer.repScores, [0.5, 1.0]);
      expect(analyzer.allRepIssues, [
        ['A'],
        <String>[],
      ]);
    });
  });

  test('Performance metrics remain on 0-5 scale across analyzers', () {
    final analyzer = PushupAnalyzer();
    analyzer.repRecords.addAll([rep(1.0), rep(0.8), rep(0.6)]);
    analyzer.repCount = 3;

    final metrics = analyzer.getPerformanceMetrics();
    expect(metrics.averageFormScore, closeTo(4.0, 0.1));
    expect(metrics.totalReps, 3);
  });

  test('RepRecord survives a JSON round trip', () {
    const original = RepRecord(
      index: 2,
      score: 0.75,
      issues: ['Rounded Back'],
      eccentricMs: 1200,
      concentricMs: 800,
      peakAngle: 88.5,
      romDeficitDegrees: 0,
    );

    final restored = RepRecord.fromJson(original.toJson());

    expect(restored.index, original.index);
    expect(restored.score, original.score);
    expect(restored.issues, original.issues);
    expect(restored.eccentricMs, original.eccentricMs);
    expect(restored.concentricMs, original.concentricMs);
    expect(restored.peakAngle, original.peakAngle);
    expect(restored.romDeficitDegrees, original.romDeficitDegrees);
  });

  test('AppConstants thresholds stay internally consistent', () {
    expect(AppConstants.squatDepthThreshold,
        lessThan(AppConstants.squatNeutralThreshold));
    expect(AppConstants.pushupDepthThreshold,
        lessThan(AppConstants.pushupNeutralThreshold));
    expect(AppConstants.overheadPressStartThreshold,
        lessThan(AppConstants.overheadPressLockoutThreshold));
    expect(AppConstants.sideOnMaxWidthRatio,
        lessThan(AppConstants.frontOnMinWidthRatio));
  });
}
