import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/logic/cue_engine.dart';

/// A hand-cranked clock so cooldowns can be tested without real delays.
class FakeClock {
  DateTime _now = DateTime(2026, 1, 1);

  DateTime call() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

void main() {
  late FakeClock clock;
  late CueEngine engine;
  late List<Cue> emitted;

  setUp(() {
    clock = FakeClock();
    engine = CueEngine(now: clock.call);
    emitted = [];
    engine.onCue = emitted.add;
  });

  test('delivers a cue the first time it is requested', () {
    final cue = engine.request(CueIds.goDeeper);

    expect(cue, isNotNull);
    expect(emitted, hasLength(1));
    expect(emitted.single.id, CueIds.goDeeper);
  });

  test('does not repeat a cue within the same rep', () {
    engine.request(CueIds.goDeeper);
    engine.request(CueIds.goDeeper);
    engine.request(CueIds.goDeeper);

    expect(emitted, hasLength(1),
        reason: 'This is what stopped the app chanting "Lower" every 0.9s.');
  });

  test('allows the cue again on the next rep, once the cooldown has passed',
      () {
    engine.request(CueIds.goDeeper);
    clock.advance(const Duration(seconds: 5));
    engine.beginRep();
    engine.request(CueIds.goDeeper);

    expect(emitted, hasLength(2));
  });

  test('respects the per-cue cooldown even across reps', () {
    engine.request(CueIds.goDeeper);
    engine.beginRep();
    // Cooldown for goDeeper is 2.5s; only 500ms has passed.
    clock.advance(const Duration(milliseconds: 500));
    engine.request(CueIds.goDeeper);

    expect(emitted, hasLength(1));
  });

  test('varies the wording instead of repeating verbatim', () {
    final messages = <String>[];
    for (var i = 0; i < 2; i++) {
      engine.beginRep();
      final cue = engine.request(CueIds.goDeeper);
      if (cue != null) messages.add(cue.message);
      clock.advance(const Duration(seconds: 5));
    }

    expect(messages, hasLength(2));
    expect(messages[0], isNot(messages[1]));
  });

  test('escalates after the athlete has heard the gentle version', () {
    final messages = <String>[];
    for (var i = 0; i < 4; i++) {
      engine.beginRep();
      final cue = engine.request(CueIds.goDeeper);
      if (cue != null) messages.add(cue.message);
      clock.advance(const Duration(seconds: 5));
    }

    expect(messages.length, greaterThanOrEqualTo(3));
    // The escalated wording is more specific than the opening nudge.
    expect(messages.last, contains('parallel'));
  });

  test('a safety cue suppresses a lower-priority cue that follows it', () {
    engine.request(CueIds.criticalBackRounding);
    engine.beginRep();
    final depth = engine.request(CueIds.goDeeper);

    expect(depth, isNull,
        reason: 'A back-rounding warning should not be followed by a nitpick.');
  });

  test('a lower-priority cue does not suppress a safety cue', () {
    engine.request(CueIds.goDeeper);
    final safety = engine.request(CueIds.criticalBackRounding);

    expect(safety, isNotNull);
    expect(safety!.priority, CuePriority.safety);
  });

  test('safety cues may repeat within a rep, subject to their cooldown', () {
    engine.request(CueIds.criticalBackRounding);
    clock.advance(const Duration(seconds: 3));
    engine.request(CueIds.criticalBackRounding);

    expect(emitted, hasLength(2));
  });

  test('appends magnitude detail when given', () {
    final cue = engine.request(CueIds.goDeeper, detail: 'about 15 degrees short');

    expect(cue!.message, contains('about 15 degrees short'));
  });

  test('unknown cue ids are ignored rather than crashing', () {
    expect(engine.request('nope.not.a.cue'), isNull);
    expect(emitted, isEmpty);
  });

  test('reset clears cooldowns and escalation', () {
    engine.request(CueIds.goDeeper);
    engine.reset();
    final cue = engine.request(CueIds.goDeeper);

    expect(cue, isNotNull);
  });

  test('every defined cue has at least one phrasing', () {
    for (final definition in kDefaultCues) {
      expect(definition.phrasings, isNotEmpty,
          reason: '${definition.id} has no wording');
    }
  });

  test('cue ids are unique', () {
    final ids = kDefaultCues.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
