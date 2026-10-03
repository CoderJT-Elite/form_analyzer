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

import 'pose_orientation.dart';

/// Relative importance. Higher wins when two cues compete.
enum CuePriority {
  encouragement,
  tempo,
  range,
  setup,
  verdict,
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
  static const String raiseArms = 'range.raiseArms';
  static const String liftHigher = 'range.liftHigher';
  static const String curlHigher = 'range.curlHigher';
  static const String slideUp = 'range.slideUp';

  static const String controlDescent = 'tempo.controlDescent';

  static const String asymmetry = 'form.asymmetry';

  static const String goodRep = 'praise.goodRep';
  static const String goodDepth = 'praise.goodDepth';
  static const String streak = 'praise.streak';

  /// A rep that did not count, and why ("No rep, hips sagged").
  static const String noRep = 'verdict.noRep';

  static const String hipsSagging = 'hold.hipsSagging';
  static const String hipsPiked = 'hold.hipsPiked';
  static const String straightBody = 'hold.straightBody';
  static const String getInPlank = 'hold.getInPlank';
  static const String liftOff = 'hold.liftOff';

  static const String rushedTempo = 'tempo.rushed';
  static const String kneeValgus = 'form.kneeValgus';
  static const String kneePastToe = 'form.kneePastToe';
  static const String torsoLean = 'form.torsoLean';
  static const String straightenLegs = 'form.straightenLegs';
  static const String feetNotSpread = 'form.feetNotSpread';
  static const String elbowsOut = 'form.elbowsOut';
  static const String stackWrists = 'form.stackWrists';
  static const String legDrive = 'form.legDrive';

  /// Nudges for an athlete who keeps moving without making an attempt.
  static const String sitDown = 'start.sitDown';
  static const String lungeDeeper = 'start.lungeDeeper';
}

/// Setup guidance copy for camera orientation before exercise start.
///
/// Reuses the existing phrasings from [CueIds.turnSideOn] and [CueIds.turnFrontOn]
/// so the athlete hears and sees the same consistent guidance before their set
/// that they would hear if they drifted out of position mid-set.
class CameraSetupCopy {
  const CameraSetupCopy._();

  static const String sideOnSpoken =
      'Turn side-on to the camera so I can see your form';
  static const String sideOnHeadline = 'Turn side-on to the camera';
  static const String sideOnSubtext = 'So I can see your form';

  static const String frontOnSpoken = 'Face the camera';
  static const String frontOnHeadline = 'Face the camera';
  static const String frontOnSubtext = 'Turn to face the camera';

  /// Shown/spoken instead of the orientation copy above when the athlete
  /// isn't fully in frame yet (too close, or partially cropped out of
  /// shot) -- reuses [CueIds.getInFrame]'s phrasing for the same reason the
  /// orientation copy reuses turnSideOn/turnFrontOn.
  static const String notInFrameSpoken = 'Step back so I can see all of you';
  static const String notInFrameHeadline = 'Step back from the camera';
  static const String notInFrameSubtext = 'I need to see your whole body';

  static String spokenFor(ViewOrientation orientation) {
    return switch (orientation) {
      ViewOrientation.sideOn => sideOnSpoken,
      ViewOrientation.frontOn => frontOnSpoken,
      ViewOrientation.unknown => sideOnSpoken,
    };
  }

  static String headlineFor(ViewOrientation orientation) {
    return switch (orientation) {
      ViewOrientation.sideOn => sideOnHeadline,
      ViewOrientation.frontOn => frontOnHeadline,
      ViewOrientation.unknown => sideOnHeadline,
    };
  }

  static String subtextFor(ViewOrientation orientation) {
    return switch (orientation) {
      ViewOrientation.sideOn => sideOnSubtext,
      ViewOrientation.frontOn => frontOnSubtext,
      ViewOrientation.unknown => sideOnSubtext,
    };
  }
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
      CameraSetupCopy.sideOnSpoken,
      'Stand sideways to the camera',
    ],
    escalated: ['I still need a side view to check your form'],
  ),
  CueDefinition(
    id: CueIds.turnFrontOn,
    priority: CuePriority.setup,
    cooldown: Duration(seconds: 5),
    phrasings: [CameraSetupCopy.frontOnSpoken, CameraSetupCopy.frontOnSubtext],
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
    // Shared by squat, push-up and lunge, so it must not name body parts
    // only one of them has ("thighs parallel" was said to a push-up).
    escalated: ['Go deeper before you come back up'],
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
    // Direction-neutral: this cue is used by exercises that travel in
    // opposite directions ("lower a little further" was said to a jumping
    // jack, which has nothing to lower). Exercises with a definite direction
    // have their own cues below.
    phrasings: ['Use your full range', 'A bit more range'],
  ),
  CueDefinition(
    id: CueIds.raiseArms,
    priority: CuePriority.range,
    cooldown: Duration(milliseconds: 2500),
    phrasings: ['Reach your arms higher', 'Arms all the way overhead'],
  ),
  CueDefinition(
    id: CueIds.liftHigher,
    priority: CuePriority.range,
    cooldown: Duration(milliseconds: 2500),
    phrasings: ['Lift your hips a little higher', 'Push your hips up higher'],
  ),
  CueDefinition(
    id: CueIds.curlHigher,
    priority: CuePriority.range,
    cooldown: Duration(milliseconds: 2500),
    phrasings: ['Curl up a little higher', 'Bring your chest toward your knees'],
  ),
  CueDefinition(
    id: CueIds.slideUp,
    priority: CuePriority.range,
    cooldown: Duration(milliseconds: 2500),
    phrasings: ['Slide up a little', 'Bring your thighs up to parallel'],
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
    // Deliberately says nothing about depth: this is shared by every exercise,
    // and "Good depth" was heard on jumping jacks and overhead presses (and on
    // a lunge that had just been told to go deeper). See goodDepth.
    phrasings: ['Nice rep', 'That one was clean', 'Solid'],
  ),
  // Only requested by exercises with a depth target that this rep fully met.
  CueDefinition(
    id: CueIds.goodDepth,
    priority: CuePriority.encouragement,
    cooldown: Duration(seconds: 6),
    phrasings: ['Good depth', 'Right down to depth'],
  ),
  // The athlete is told, at the moment it happens, that a rep did not count and
  // why. Always carries a detail; the bare phrasing is the short form used when
  // the fault was just spoken as a live cue.
  CueDefinition(
    id: CueIds.noRep,
    priority: CuePriority.verdict,
    cooldown: Duration(milliseconds: 1500),
    repeatableWithinRep: true,
    phrasings: ['No rep'],
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
  // Body line is broken but there is no floor to say which way (leaning on a
  // wall, a steep incline): tell them to straighten it without inventing a
  // direction. Not a safety cue -- it must not interrupt anything.
  CueDefinition(
    id: CueIds.straightBody,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 5),
    phrasings: ['Keep your body in one straight line', 'Line up your head, hips and heels'],
  ),
  CueDefinition(
    id: CueIds.getInPlank,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 8),
    phrasings: ['Get into plank position on the floor', 'Lower down into your plank'],
  ),
  CueDefinition(
    id: CueIds.liftOff,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 8),
    phrasings: ['Lift your body off the floor', 'Hold yourself up on your arms'],
  ),
  CueDefinition(
    id: CueIds.rushedTempo,
    priority: CuePriority.tempo,
    cooldown: Duration(seconds: 4),
    phrasings: ['Slow that down', 'Control the movement'],
    escalated: ['Way too fast — take your time on the way down'],
  ),
  CueDefinition(
    id: CueIds.kneeValgus,
    priority: CuePriority.safety,
    cooldown: Duration(milliseconds: 3000),
    repeatableWithinRep: true,
    phrasings: ['Push your knees out', 'Track knees over your toes'],
    escalated: ['Knees are caving in — push them out'],
  ),
  CueDefinition(
    id: CueIds.kneePastToe,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 4),
    phrasings: ['Keep your knee behind your toes', 'Shift weight back a little'],
  ),
  CueDefinition(
    id: CueIds.torsoLean,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 4),
    phrasings: ['Keep your chest up', 'Stay more upright'],
  ),
  CueDefinition(
    id: CueIds.straightenLegs,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 4),
    phrasings: ['Keep your legs straight', 'Straighten those knees'],
  ),
  CueDefinition(
    id: CueIds.feetNotSpread,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 4),
    phrasings: ['Feet wider', 'Jump your feet further out'],
  ),
  CueDefinition(
    id: CueIds.elbowsOut,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 4),
    phrasings: ['Elbows under your shoulders', 'Stack your elbows under you'],
  ),
  CueDefinition(
    id: CueIds.stackWrists,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 4),
    phrasings: ['Stack your wrists over your elbows', 'Keep the bar over your elbows'],
  ),
  CueDefinition(
    id: CueIds.sitDown,
    priority: CuePriority.setup,
    cooldown: Duration(seconds: 12),
    phrasings: [
      'Bend your knees and sit down into the squat',
      'Keep your chest up and sit your hips back and down',
    ],
  ),
  CueDefinition(
    id: CueIds.lungeDeeper,
    priority: CuePriority.setup,
    cooldown: Duration(seconds: 12),
    phrasings: [
      'Step out further and drop your back knee toward the floor',
      'Lower until your front thigh is level with the ground',
    ],
  ),
  CueDefinition(
    id: CueIds.legDrive,
    priority: CuePriority.range,
    cooldown: Duration(seconds: 5),
    phrasings: ['Keep your legs still and press with your arms', 'No leg drive — strict press'],
  ),
];

class _CueState {
  DateTime? lastEmittedAt;
  int timesEmitted = 0;
  int phrasingIndex = 0;
  bool emittedThisRep = false;
}

/// Priorities that mean "this rep had something wrong with it".
bool _isFaultPriority(CuePriority p) =>
    p == CuePriority.range || p == CuePriority.safety || p == CuePriority.verdict;

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
  bool _faultCuedThisRep = false;
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
    if (_isFaultPriority(definition.priority)) _faultCuedThisRep = true;

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

  /// Whether a range, safety or verdict cue was delivered since the current rep
  /// began. A rep that was just told to go deeper must not also be praised.
  bool get faultCuedThisRep => _faultCuedThisRep;

  /// When [id] last reached the athlete, or null.
  DateTime? lastEmittedAt(String id) => _states[id]?.lastEmittedAt;

  /// Clear per-rep suppression. Called when a new rep starts.
  void beginRep() {
    _faultCuedThisRep = false;
    for (final state in _states.values) {
      state.emittedThisRep = false;
    }
  }

  /// Full reset between sets.
  void reset() {
    _states.clear();
    _faultCuedThisRep = false;
    _lastEmitAt = null;
    _lastEmitPriority = null;
  }
}
