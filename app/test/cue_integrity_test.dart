import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/cue_engine.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';

import 'support/replay_harness.dart';

/// Every cue an analyzer speaks must make sense for that exercise.
///
/// Live tests produced "lower a little further" for jumping jacks (nothing to
/// lower), a squat cue during push-ups, "drive your hips up" at the top of a
/// glute bridge and "turn side-on" mid-set. Each was a cue reaching an exercise
/// it does not belong to. This replays every recorded set (stock footage and
/// the on-phone recordings) and checks the cue ids that came out against a
/// per-exercise list written down by hand, so a cue leaking across exercises
/// fails here instead of on someone's phone.
const _praise = {CueIds.goodRep, CueIds.streak};

final Map<String, Set<String>> _allowed = {
  'squat': {
    CueIds.goDeeper, CueIds.torsoLean, CueIds.asymmetry, CueIds.kneeValgus,
    CueIds.controlDescent, CueIds.turnSideOn, ..._praise,
  },
  'pushup': {
    CueIds.goDeeper, CueIds.lockOut, CueIds.hipsSagging, CueIds.hipsPiked,
    CueIds.straightBody, CueIds.controlDescent, ..._praise,
  },
  'lunge': {
    CueIds.goDeeper, CueIds.kneePastToe, CueIds.torsoLean,
    CueIds.controlDescent, ..._praise,
  },
  'overheadPress': {
    CueIds.fullRange, CueIds.lockOut, CueIds.elbowsOut,
    CueIds.controlDescent, ..._praise,
  },
  'situp': {
    CueIds.curlHigher, CueIds.asymmetry, CueIds.straightenLegs,
    CueIds.controlDescent, CueIds.turnSideOn, ..._praise,
  },
  'gluteBridge': {
    CueIds.liftHigher, CueIds.controlDescent, CueIds.turnSideOn, ..._praise,
  },
  'jumpingJack': {
    CueIds.raiseArms, CueIds.feetNotSpread, CueIds.asymmetry,
    CueIds.controlDescent, CueIds.turnFrontOn, ..._praise,
  },
  'plank': {
    CueIds.hipsSagging, CueIds.hipsPiked, CueIds.straightBody, CueIds.getInPlank,
    CueIds.elbowsOut, CueIds.asymmetry,
  },
  'sidePlank': {
    CueIds.hipsSagging, CueIds.hipsPiked, CueIds.straightBody, CueIds.getInPlank,
    CueIds.elbowsOut, CueIds.straightenLegs,
  },
  'wallSit': {
    CueIds.goDeeper, CueIds.slideUp, CueIds.kneePastToe, CueIds.asymmetry,
    CueIds.turnSideOn,
  },
};

ExerciseAnalyzer Function(DateTime Function()) _factory(String exercise, List<String> ids) {
  return (clock) {
    final analyzer = switch (exercise) {
      'squat' => SquatAnalyzer(clock: clock),
      'pushup' => PushupAnalyzer(clock: clock),
      'lunge' => LungeAnalyzer(clock: clock),
      'overheadPress' => OverheadPressAnalyzer(clock: clock),
      'situp' => SitupAnalyzer(clock: clock),
      'gluteBridge' => GluteBridgeAnalyzer(clock: clock),
      'jumpingJack' => JumpingJackAnalyzer(clock: clock),
      'plank' => PlankAnalyzer(clock: clock),
      'sidePlank' => SidePlankAnalyzer(clock: clock),
      'wallSit' => WallSitAnalyzer(clock: clock),
      _ => throw ArgumentError(exercise),
    };
    final delivered = analyzer.cues.onCue;
    analyzer.cues.onCue = (cue) {
      ids.add(cue.id);
      delivered?.call(cue);
    };
    return analyzer;
  };
}

void main() {
  final dir = Directory('test/fixtures/pose_sequences');
  final fixtures = dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
      .toList()
    ..sort();

  test('every fixture belongs to an exercise with a cue list', () {
    for (final name in fixtures) {
      final exercise = _exerciseOf(name);
      expect(_allowed.containsKey(exercise), isTrue, reason: name);
    }
  });

  for (final name in fixtures) {
    final exercise = _exerciseOf(name);
    if (!_allowed.containsKey(exercise)) continue;
    test('$name only speaks cues that belong to $exercise', () {
      final ids = <String>[];
      final live = name.startsWith('live');
      replay(name, _factory(exercise, ids), fps: live ? 15 : 30);
      final stray = ids.toSet().difference(_allowed[exercise]!);
      expect(stray, isEmpty, reason: 'unexpected cues for $exercise: $stray');
    });
  }
}

String _exerciseOf(String fixture) {
  var n = fixture;
  if (n.startsWith('live2_') || n.startsWith('live3_')) n = n.substring(6);
  n = n.split('_').first;
  if (n.startsWith('pushup')) return 'pushup';
  return n;
}
