/// Coaching cue delivery: what gets said, when, and how often.
///
/// Analyzers run on every processed camera frame, so a fault that persists for
/// two seconds is detected dozens of times. Previously each detection went
/// straight out and the only thing standing between the athlete and a
/// once-per-900ms chant of the word "Lower" was a timer inside the speech
/// service. This engine sits in between and decides what is actually worth
/// saying: it rate-limits per cue, lets a safety warning talk over a nitpick,
/// varies the wording, escalates when a fault keeps happening, and refuses to
/// repeat itself within a single rep.
library;

/// Relative importance. Higher wins when two cues compete.
enum CuePriority {
  encouragement,
  tempo,
  range,
  setup,
  safety,
}

/// A cue that has been cleared for delivery.
class Cue {
  final String id;
  final CuePriority priority;
  final String message;

  const Cue({
    required this.id,
    required this.priority,
    required this.message,
  });

  @override
  String toString() => 'Cue($id, ${priority.name}, "$message")';
}

/// Wording for one kind of cue.
class CueDefinition {
  final String id;
  final CuePriority priority;
  final Duration cooldown;

  /// Said the first couple of times. Rotated so the same sentence doesn't come
  /// out twice in a row.
  final List<String> phrasings;

  /// Said once the athlete has heard the gentle version and kept doing it.
  final List<String> escalated;

  /// Whether this cue may be repeated within a single rep. Only safety cues
  /// should; everything else says its piece once and waits for the next rep.
  final bool repeatableWithinRep;

  const CueDefinition({
    required this.id,
    required this.priority,
    required this.phrasings,
    this.escalated = const [],
    this.cooldown = const Duration(seconds: 3),
    this.repeatableWithinRep = false,
  });
}

/// Cue identifiers. Analyzers reference these rather than raw strings.
class CueIds {
  const CueIds._();

  static const String criticalBackRounding = 'safety.back.critical';
  static const String backRounding = 'safety.back.rounding';

  static const String turnSideOn = 'setup.turnSideOn';
  static const String turnFrontOn = 'setup.turnFrontOn';
  static const String getInFrame = 'setup.getInFrame';

  static const String goDeeper = 'range.goDeeper';
  static const String lockOut = 'range.lockOut';
  static const String fullRange = 'range.full';

  static const String controlDescent = 'tempo.controlDescent';

  static const String asymmetry = 'form.asymmetry';

  static const String goodRep = 'praise.goodRep';
  static const String streak = 'praise.streak';

  static const String hipsSagging = 'hold.hipsSagging';
  static const String hipsPiked = 'hold.hipsPiked';
}

/// The default coaching vocabulary.
const List<CueDefinition> kDefaultCues = [
  CueDefinition(
    id: CueIds.criticalBackRounding,
    priority: CuePriority.safety,
    cooldown: Duration(milliseconds: 2000),
    repeatableWithinRep: true,
    phrasings: ['Straighten your back', 'Chest up, back flat'],
    escalated: ['Stop and reset — your back is rounding badly'],
  ),
  CueDefinition(
    id: CueIds.backRounding,
    priority: CuePriority.safety,
    cooldown: Duration(milliseconds: 3000),
    phrasings: ['Keep your back straight', 'Chest up'],
    escalated: ['Watch that back — chest up and brace'],
  ),
  CueDefinition(
    id: CueIds.turnSideOn,
    priority: CuePriority.setup,
    cooldown: Duration(seconds: 5),
    phrasings: [
      'Turn side-on to the camera so I can see your form',
      'Stand sideways to the camera',
    ],
    escalated: ['I still need a side view to check your form'],
  ),
  CueDefinition(
    id: CueIds.turnFrontOn,
    priority: CuePriority.setup,
    cooldown: Duration(seconds: 5),
    phrasings: ['Face the camera', 'Turn to face the camera'],
  ),
  CueDefinition(
    id: CueIds.getInFrame,
    priority: CuePriority.setup,
    cooldown: Duration(seconds: 5),
    phrasings: ['Step back so I can see all of you', 'Get your whole body in frame'],
  ),
  CueDefinition(
    id: CueIds.goDeeper,
    priority: CuePriority.range,
    cooldown: Duration(milliseconds: 2500),
    phrasings: ['A little deeper', 'Sink a bit lower'],
    escalated: ['Go deeper — aim for thighs parallel'],
  ),
  CueDefinition(
    id: CueIds.lockOut,
    priority: CuePriority.range,
    cooldown: Duration(milliseconds: 2500),
    phrasings: ['Finish at the top', 'All the way up'],
    escalated: ['Lock it out fully before coming back down'],
  ),
  CueDefinition(
    id: CueIds.fullRange,
    priority: CuePriority.range,
    cooldown: Duration(milliseconds: 2500),
    phrasings: ['Use your full range', 'Lower a little further'],
  ),
  CueDefinition(
    id: CueIds.controlDescent,
    priority: CuePriority.tempo,
    cooldown: Duration(seconds: 4),
    phrasings: ['Slow the way down', 'Control the descent'],
    escalated: ['Take about two seconds lowering — stop dropping into it'],
  ),
  // Deliberately avoids naming a side. The front camera mirrors the preview,
  // so "your left" on screen is the athlete's right — a cue that names a side
  // would be wrong half the time.
  CueDefinition(
    id: CueIds.asymmetry,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 8),
    phrasings: ['Keep both sides even', 'Balance your weight evenly'],
    escalated: ['One side is working harder — even them out'],
  ),
  CueDefinition(
    id: CueIds.goodRep,
    priority: CuePriority.encouragement,
    cooldown: Duration(seconds: 6),
    phrasings: ['Nice rep', 'That one was clean', 'Good depth'],
  ),
  CueDefinition(
    id: CueIds.streak,
    priority: CuePriority.encouragement,
    cooldown: Duration(seconds: 10),
    phrasings: ['You are dialled in', 'Great set so far', 'Keep that going'],
  ),
  CueDefinition(
    id: CueIds.hipsSagging,
    priority: CuePriority.safety,
    cooldown: Duration(milliseconds: 3000),
    repeatableWithinRep: true,
    phrasings: ['Hips up', "Don't let your hips drop"],
    escalated: ['Squeeze your glutes and lift those hips'],
  ),
  CueDefinition(
    id: CueIds.hipsPiked,
    priority: CuePriority.safety,
    cooldown: Duration(milliseconds: 3000),
    repeatableWithinRep: true,
    phrasings: ['Lower your hips', 'Drop your hips into line'],
    escalated: ['Hips are too high — flatten your body out'],
  ),
];

class _CueState {
  DateTime? lastEmittedAt;
  int timesEmitted = 0;
  int phrasingIndex = 0;
  bool emittedThisRep = false;
}

/// Decides which coaching cues actually reach the athlete.
class CueEngine {
  CueEngine({
    List<CueDefinition> definitions = kDefaultCues,
    this.now = _systemNow,
  }) : _definitions = {for (final d in definitions) d.id: d};

  final Map<String, CueDefinition> _definitions;

  /// Injectable clock so cooldown behaviour is testable without real delays.
  final DateTime Function() now;

  void Function(Cue cue)? onCue;

  final Map<String, _CueState> _states = {};
  DateTime? _lastEmitAt;
  CuePriority? _lastEmitPriority;

  /// How long a delivered cue keeps lower-priority cues quiet, so a safety
  /// warning isn't immediately followed by a nitpick about depth.
  static const Duration dominanceWindow = Duration(milliseconds: 1800);

  /// Number of times a cue fires before it switches to its escalated wording.
  static const int escalateAfter = 2;

  static DateTime _systemNow() => DateTime.now();

  /// Ask for a cue to be delivered. Returns the cue if it passed the gates.
  ///
  /// [detail] is appended to the message when present — used to turn a vague
  /// "a little deeper" into "a little deeper, about 15 degrees short".
  Cue? request(String id, {String? detail}) {
    final definition = _definitions[id];
    if (definition == null) return null;

    final state = _states.putIfAbsent(id, () => _CueState());
    final timestamp = now();

    if (!definition.repeatableWithinRep && state.emittedThisRep) return null;

    final lastEmitted = state.lastEmittedAt;
    if (lastEmitted != null &&
        timestamp.difference(lastEmitted) < definition.cooldown) {
      return null;
    }

    // A recent, more important cue suppresses this one.
    final lastAny = _lastEmitAt;
    final lastPriority = _lastEmitPriority;
    if (lastAny != null &&
        lastPriority != null &&
        timestamp.difference(lastAny) < dominanceWindow &&
        lastPriority.index > definition.priority.index) {
      return null;
    }

    final phrasings = state.timesEmitted >= escalateAfter &&
            definition.escalated.isNotEmpty
        ? definition.escalated
        : definition.phrasings;
    final message = phrasings[state.phrasingIndex % phrasings.length];

    state.phrasingIndex++;
    state.timesEmitted++;
    state.lastEmittedAt = timestamp;
    state.emittedThisRep = true;

    _lastEmitAt = timestamp;
    _lastEmitPriority = definition.priority;

    final cue = Cue(
      id: id,
      priority: definition.priority,
      message: detail == null ? message : '$message, $detail',
    );

    onCue?.call(cue);
    return cue;
  }

  /// Clear per-rep suppression. Called when a new rep starts.
  void beginRep() {
    for (final state in _states.values) {
      state.emittedThisRep = false;
    }
  }

  /// Full reset between sets.
  void reset() {
    _states.clear();
    _lastEmitAt = null;
    _lastEmitPriority = null;
  }
}
