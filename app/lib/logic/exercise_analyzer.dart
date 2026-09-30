import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/app_constants.dart';
import '../utils/math_utils.dart';
import 'cue_engine.dart';
import 'hip_line.dart';
import 'pose_orientation.dart';
import 'rep_cycle_detector.dart';
import 'rep_recovery.dart';

/// Issues that cannot both be the headline of the same set.
const Map<String, String> _contradictions = {
  'Hips Sagging': 'Hips Piked',
  'Hips Piked': 'Hips Sagging',
  'Insufficient Depth': 'Too Low',
  'Too Low': 'Insufficient Depth',
};

class PerformanceMetrics {
  final double averageFormScore;
  final List<String> commonIssues;
  final int perfectReps;
  final int totalReps;

  PerformanceMetrics({
    required this.averageFormScore,
    required this.commonIssues,
    required this.perfectReps,
    required this.totalReps,
  });

  Map<String, dynamic> toJson() => {
    'averageFormScore': averageFormScore,
    'commonIssues': commonIssues,
    'perfectReps': perfectReps,
    'totalReps': totalReps,
  };

  factory PerformanceMetrics.fromJson(Map<String, dynamic> json) =>
      PerformanceMetrics(
        averageFormScore: (json['averageFormScore'] as num).toDouble(),
        commonIssues: List<String>.from(json['commonIssues']),
        perfectReps: json['perfectReps'],
        totalReps: json['totalReps'],
      );
}

/// Everything worth knowing about one completed rep.
///
/// Replaces the old pair of parallel lists (`repScores` and `allRepIssues`),
/// which could only answer "how good was it" and "what went wrong". Carrying
/// tempo and range on the same record is what lets the app say "you dropped
/// into that one" or "you were 15 degrees short" instead of just "Lower".
class RepRecord {
  final int index;
  final double score;
  final List<String> issues;

  /// Time spent lowering, in milliseconds. Zero when not measured.
  final int eccentricMs;

  /// Time spent driving back up, in milliseconds. Zero when not measured.
  final int concentricMs;

  /// Deepest joint angle reached during the rep.
  final double? peakAngle;

  /// How many degrees short of the depth target the rep finished, or 0 when
  /// the target was met.
  final double romDeficitDegrees;

  const RepRecord({
    required this.index,
    required this.score,
    required this.issues,
    this.eccentricMs = 0,
    this.concentricMs = 0,
    this.peakAngle,
    this.romDeficitDegrees = 0,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'score': score,
        'issues': issues,
        'eccentricMs': eccentricMs,
        'concentricMs': concentricMs,
        if (peakAngle != null) 'peakAngle': peakAngle,
        'romDeficitDegrees': romDeficitDegrees,
      };

  factory RepRecord.fromJson(Map<String, dynamic> json) => RepRecord(
        index: json['index'] as int? ?? 0,
        score: (json['score'] as num?)?.toDouble() ?? 0,
        issues: List<String>.from(json['issues'] as List? ?? const []),
        eccentricMs: json['eccentricMs'] as int? ?? 0,
        concentricMs: json['concentricMs'] as int? ?? 0,
        peakAngle: (json['peakAngle'] as num?)?.toDouble(),
        romDeficitDegrees:
            (json['romDeficitDegrees'] as num?)?.toDouble() ?? 0,
      );
}

abstract class ExerciseAnalyzer {
  ExerciseAnalyzer({CueEngine? cueEngine, DateTime Function()? clock})
      : now = clock ?? DateTime.now,
        cues = cueEngine ?? CueEngine(now: clock ?? DateTime.now) {
    cues.onCue = _dispatchCue;
  }

  int repCount = 0;
  RepPhase phase = RepPhase.neutral;
  String statusMessage = 'Align yourself in frame';
  double? lastProcessedAngle;
  Function(int)? onRep;
  Function(String)? onFeedback;
  Function(String)? onCorrection;
  Function(String)? onSafetyAlert;

  /// Injectable clock, so tempo and cue cooldowns are testable.
  final DateTime Function() now;

  final CueEngine cues;
  final OrientationTracker orientationTracker = OrientationTracker();

  String? _lastCueMessage;
  DateTime? _lastCueAt;
  DateTime? _wrongViewSince;

  /// How long a delivered cue stays on screen.
  static const Duration cueDisplayDuration = Duration(milliseconds: 2500);

  /// What the screen should show. The state machines overwrite
  /// [statusMessage] on every frame ("Stand tall"), which wiped out the very
  /// cue that had just been spoken -- the athlete heard "stop and reset" while
  /// reading "Stand tall". A cue now holds the display for a couple of seconds.
  String get displayMessage {
    final at = _lastCueAt;
    if (at != null &&
        _lastCueMessage != null &&
        now().difference(at) < cueDisplayDuration) {
      return _lastCueMessage!;
    }
    return statusMessage;
  }

  final List<String> currentRepIssues = [];
  final List<RepRecord> repRecords = [];

  /// When each entry of [repRecords] was completed. Kept alongside rather than
  /// inside [RepRecord] so stored sessions are unchanged; used to take back reps
  /// that turn out to be the athlete walking to the phone.
  final List<DateTime> _repTimes = [];

  DateTime? _eccentricStartedAt;
  DateTime? _concentricStartedAt;
  int _cleanRepStreak = 0;

  /// Derived views kept for the UI and for stored session summaries.
  List<double> get repScores =>
      repRecords.map((record) => record.score).toList(growable: false);

  List<List<String>> get allRepIssues =>
      repRecords.map((record) => record.issues).toList(growable: false);

  Set<PoseLandmarkType> get activeLandmarkTypes;

  /// True for exercises measured in held seconds rather than reps. The
  /// counter still flows through [repCount] (one "rep" per second held), but
  /// the UI should present it as time.
  bool get isTimedHold => false;

  /// The camera view this exercise's form checks are written for.
  ViewOrientation get requiredOrientation => ViewOrientation.sideOn;

  /// Whether [observed] is a view this exercise can be judged from. Most
  /// exercises need exactly [requiredOrientation]; push-ups can also be
  /// counted from a camera on the floor facing the athlete.
  bool acceptsOrientation(ViewOrientation observed) => observed == requiredOrientation;

  /// Whether the poses fed to this analyzer are levelled to a *known* gravity.
  /// When the accelerometer is missing (or the phone lies flat) they are not, and
  /// a plank filmed with the phone on its side looks exactly like a person
  /// standing up. Checks that ask "is the body lying flat?" only mean something
  /// when this is true.
  bool gravityKnown = true;

  /// Whether joint angles may use ML Kit's depth estimate. Exercises filmed in
  /// a plane facing the camera measure in the image plane only.
  bool get uses3dAngles => true;

  /// Joint angle at [b], honouring [uses3dAngles].
  double jointAngle(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) => uses3dAngles
      ? MathUtils.calculateJointAngle(a, b, c)
      : MathUtils.calculateJointAngle2D(a, b, c);

  void reset() {
    repCount = 0;
    phase = RepPhase.neutral;
    statusMessage = 'Get ready!';
    lastProcessedAngle = null;
    currentRepIssues.clear();
    repRecords.clear();
    _repTimes.clear();
    cues.reset();
    orientationTracker.reset();
    _lastCueMessage = null;
    _lastCueAt = null;
    _wrongViewSince = null;
    _eccentricStartedAt = null;
    _concentricStartedAt = null;
    _cleanRepStreak = 0;
  }

  /// Landmark confidence needed before a landmark is used.
  double get minLikelihood => AppConstants.visibilityThreshold;

  bool isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null && landmark.likelihood >= minLikelihood;
  }

  /// Route a cleared cue to the right callback and to the on-screen status.
  void _dispatchCue(Cue cue) {
    statusMessage = cue.message;
    _lastCueMessage = cue.message;
    _lastCueAt = now();
    switch (cue.priority) {
      case CuePriority.safety:
        if (onSafetyAlert != null) onSafetyAlert!(cue.message);
      case CuePriority.encouragement:
        if (onFeedback != null) onFeedback!(cue.message);
      case CuePriority.setup:
      case CuePriority.range:
      case CuePriority.tempo:
        if (onCorrection != null) onCorrection!(cue.message);
    }
  }

  /// Update the orientation tracker and nudge the athlete if they are clearly
  /// standing the wrong way round.
  ///
  /// Returns true only when the required view is *confirmed*. Callers use that
  /// to gate view-dependent form checks: a check that cannot see what it is
  /// measuring must stay quiet rather than silently report good form.
  bool updateOrientation(Pose pose) {
    final observed = orientationTracker.update(pose);
    if (observed == requiredOrientation) {
      _wrongViewSince = null;
      return true;
    }
    if (observed == ViewOrientation.unknown) return false;

    // "Turn side-on" belongs to the setup screen. Said mid-set it is a nag: the
    // squat, sit-up and glute-bridge replays of live test #3 each heard it while
    // reps were being counted. Only raise it when the view has stayed wrong for
    // a while *and* nothing has counted, i.e. it really is why nothing counts.
    final since = _wrongViewSince ??= now();
    if (repCount == 0 && now().difference(since) >= AppConstants.wrongViewCueDelay) {
      cues.request(
        requiredOrientation == ViewOrientation.sideOn
            ? CueIds.turnSideOn
            : CueIds.turnFrontOn,
      );
    }
    return false;
  }

  /// Called by subclasses when the lowering phase begins.
  void markEccentricStart() {
    _eccentricStartedAt = now();
    _concentricStartedAt = null;
    cues.beginRep();
  }

  /// Called by subclasses when the athlete reverses and drives back up.
  void markConcentricStart() {
    _concentricStartedAt = now();
  }

  /// Finalise a rep: store the record, check tempo, and hand out praise.
  void recordRep({
    required double score,
    double? peakAngle,
    double romDeficitDegrees = 0,
  }) {
    final timestamp = now();
    final eccentricMs = _eccentricStartedAt == null
        ? 0
        : (_concentricStartedAt ?? timestamp)
            .difference(_eccentricStartedAt!)
            .inMilliseconds;
    final concentricMs = _concentricStartedAt == null
        ? 0
        : timestamp.difference(_concentricStartedAt!).inMilliseconds;

    final clamped = score.clamp(0.0, 1.0);

    _repTimes.add(timestamp);
    repRecords.add(
      RepRecord(
        index: repCount,
        score: clamped,
        issues: List<String>.from(currentRepIssues),
        eccentricMs: eccentricMs,
        concentricMs: concentricMs,
        peakAngle: peakAngle,
        romDeficitDegrees: romDeficitDegrees,
      ),
    );

    // Deliberately a live cue only, not a scored/recorded issue: the
    // real-footage regression tests replay frames in a tight loop with no
    // simulated per-frame delay, so eccentricMs here measures how fast the
    // test executes, not how fast the athlete actually moved -- there's no
    // way to validate a scored version of this against real footage without
    // fixture timestamps and an injected clock, which the fixtures don't
    // currently carry. Tried it; several genuinely clean real reps came back
    // "rushed" purely from test-loop speed. Left as a cue, matching the
    // pre-existing (already correct, wall-clock-driven in the real app)
    // behavior.
    if (eccentricMs > 0 && eccentricMs < AppConstants.minEccentricMillis) {
      cues.request(CueIds.controlDescent);
    }

    if (clamped > AppConstants.cleanRepScore) {
      _cleanRepStreak++;
      if (_cleanRepStreak >= AppConstants.praiseStreakLength) {
        cues.request(CueIds.streak);
      } else {
        cues.request(CueIds.goodRep);
      }
    } else {
      _cleanRepStreak = 0;
    }

    currentRepIssues.clear();
    _eccentricStartedAt = null;
    _concentricStartedAt = null;
  }

  void processPose(Pose pose);

  /// Take back reps counted at or after [since].
  ///
  /// When the phone is picked up the athlete is walking toward it, and the
  /// frames of a person looming at the lens plus a moving camera produce
  /// phantom reps (an extra overhead press on live test #3). Returns how many
  /// were removed. Timed holds record no rep times and are unaffected.
  int retractRepsSince(DateTime since) {
    var removed = 0;
    while (_repTimes.isNotEmpty && !_repTimes.last.isBefore(since)) {
      _repTimes.removeLast();
      if (repRecords.isNotEmpty) repRecords.removeLast();
      removed++;
    }
    if (removed > 0) {
      repCount = math.max(0, repCount - removed);
      _cleanRepStreak = 0;
      if (onRep != null) onRep!(repCount);
    }
    return removed;
  }

  /// Drop whatever movement is in progress without touching the count, for when
  /// analysis has to pause (the phone is being moved).
  void interrupt() {
    final count = repCount;
    final records = List<RepRecord>.of(repRecords);
    final times = List<DateTime>.of(_repTimes);
    final streak = _cleanRepStreak;
    reset();
    repCount = count;
    repRecords.addAll(records);
    _repTimes.addAll(times);
    _cleanRepStreak = streak;
    statusMessage = 'Paused';
  }

  PerformanceMetrics getPerformanceMetrics() {
    final Map<String, int> issueCounts = {};
    for (var record in repRecords) {
      for (var issue in record.issues) {
        issueCounts[issue] = (issueCounts[issue] ?? 0) + 1;
      }
    }

    final sortedIssues = issueCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // A summary that says the hips both sagged and piked reads as a broken
    // app. Keep whichever was more common.
    final commonIssues = <String>[];
    for (final entry in sortedIssues) {
      final rival = _contradictions[entry.key];
      if (rival != null && commonIssues.contains(rival)) continue;
      commonIssues.add(entry.key);
      if (commonIssues.length == 3) break;
    }
    final scores = repScores;
    final avgScore = scores.isEmpty
        ? 0.0
        : (scores.reduce((a, b) => a + b) / scores.length) * 5.0;

    return PerformanceMetrics(
      averageFormScore: avgScore,
      commonIssues: commonIssues,
      perfectReps: scores.where((s) => s > 0.9).length,
      totalReps: repCount,
    );
  }

  void addIssue(String issue) {
    if (!currentRepIssues.contains(issue)) {
      currentRepIssues.add(issue);
    }
  }
}

class SquatAnalyzer extends ExerciseAnalyzer {
  SquatAnalyzer({super.cueEngine, super.clock});

  SquatState squatState = SquatState.neutral;
  bool _reachedDepth = false;
  double _deepestAngle = 180;
  final RecoveryDetector _recovery = RecoveryDetector();
  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  final MovingAverageFilter _asymmetryFilter =
      MovingAverageFilter(windowSize: AppConstants.asymmetryWindow);
  final LandmarkSmoother _landmarkSmoother = LandmarkSmoother();
  double? _prevFilteredAngle;

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      };

  @override
  void reset() {
    super.reset();
    squatState = SquatState.neutral;
    _reachedDepth = false;
    _deepestAngle = 180;
    _angleFilter.reset();
    _asymmetryFilter.reset();
    _landmarkSmoother.reset();
    _prevFilteredAngle = null;
    _recovery.reset();
  }

  @override
  void processPose(Pose pose) {
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    // Either leg is enough. From a side view the far leg is routinely hidden
    // behind the near one, and demanding both meant a perfectly framed
    // athlete got "Adjust Camera" and no reps at all.
    final leftVisible = isLandmarkVisible(leftHip) &&
        isLandmarkVisible(leftKnee) &&
        isLandmarkVisible(leftAnkle);
    final rightVisible = isLandmarkVisible(rightHip) &&
        isLandmarkVisible(rightKnee) &&
        isLandmarkVisible(rightAnkle);
    if (!leftVisible && !rightVisible) {
      statusMessage = 'Adjust Camera';
      return;
    }
    final bothVisible = leftVisible && rightVisible;

    final leftHipSmooth = leftVisible ? _smooth(leftHip!, 'leftHip') : null;
    final leftKneeSmooth = leftVisible ? _smooth(leftKnee!, 'leftKnee') : null;
    final leftAnkleSmooth = leftVisible ? _smooth(leftAnkle!, 'leftAnkle') : null;
    final rightHipSmooth = rightVisible ? _smooth(rightHip!, 'rightHip') : null;
    final rightKneeSmooth = rightVisible ? _smooth(rightKnee!, 'rightKnee') : null;
    final rightAnkleSmooth =
        rightVisible ? _smooth(rightAnkle!, 'rightAnkle') : null;

    final leftAngle = leftVisible
        ? MathUtils.calculateAngleFromSmoothed(
            leftHipSmooth!, leftKneeSmooth!, leftAnkleSmooth!)
        : null;
    final rightAngle = rightVisible
        ? MathUtils.calculateAngleFromSmoothed(
            rightHipSmooth!, rightKneeSmooth!, rightAnkleSmooth!)
        : null;

    final leftConfidence = leftVisible
        ? leftKneeSmooth!.likelihood + leftAnkleSmooth!.likelihood
        : -1.0;
    final rightConfidence = rightVisible
        ? rightKneeSmooth!.likelihood + rightAnkleSmooth!.likelihood
        : -1.0;
    final useLeft = leftConfidence >= rightConfidence;
    final rawAngle = useLeft ? leftAngle! : rightAngle!;

    // A second angle used only for the depth check below, differing from
    // rawAngle/currentAngle in two ways:
    //
    // 1. Unsmoothed. Even rawAngle has been through one stage of exponential
    //    smoothing (LandmarkSmoother, alpha 0.35), which is enough lag to
    //    blunt a fast rep's true bottom (real stock footage: a squat that hit
    //    61-66 degrees only ever read 91-100 through that filter). Depth is a
    //    one-shot "did they ever get there" check, so raw landmarks are fine.
    // 2. Takes whichever leg reads deeper, not whichever ML Kit is more
    //    confident about: both legs bend together, so a disagreement is
    //    estimation error and the deeper reading is the one showing real depth.
    final unsmoothedAngle = math.min(
      leftVisible
          ? MathUtils.calculateAngle(leftHip!, leftKnee!, leftAnkle!)
          : 180.0,
      rightVisible
          ? MathUtils.calculateAngle(rightHip!, rightKnee!, rightAnkle!)
          : 180.0,
    );

    // Left/right comparisons only make sense with both legs in view, and only
    // front-on: a side view foreshortens the far leg and would report a
    // difference that isn't there.
    final isFrontOn = orientationTracker.orientation == ViewOrientation.frontOn;
    if (bothVisible) {
      final asymmetry = _asymmetryFilter.add((leftAngle! - rightAngle!).abs());
      if (isFrontOn &&
          _asymmetryFilter.isFull &&
          asymmetry > AppConstants.asymmetryDegreesThreshold &&
          squatState != SquatState.neutral) {
        addIssue('Uneven Sides');
        cues.request(CueIds.asymmetry);
      }

      // Knees drifting inward (valgus) relative to how wide the ankles are
      // planted -- front-on only, same gating as the asymmetry check.
      final kneeWidth = (leftKneeSmooth!.x - rightKneeSmooth!.x).abs();
      final ankleWidth = (leftAnkleSmooth!.x - rightAnkleSmooth!.x).abs();
      if (isFrontOn &&
          squatState == SquatState.eccentric &&
          ankleWidth > AppConstants.minMagnitude &&
          kneeWidth / ankleWidth < AppConstants.squatKneeValgusRatio) {
        addIssue('Knees Caving In');
        cues.request(CueIds.kneeValgus);
      } else if (isFrontOn) {
        currentRepIssues.remove('Knees Caving In');
      }
    }

    final currentAngle = _angleFilter.add(rawAngle);
    lastProcessedAngle = currentAngle;

    final angleDelta =
        _prevFilteredAngle == null ? 0.0 : currentAngle - _prevFilteredAngle!;
    _prevFilteredAngle = currentAngle;

    // Forward lean. This used to measure shoulder-hip-knee and call anything
    // under 145/160 degrees "back rounding" -- but that angle is hip flexion,
    // which is *supposed* to close to 60-90 degrees at the bottom of every
    // squat, so every deep squat was flagged critical (live tests 2026-09-13
    // and 2026-09-20). Spinal rounding itself is not visible from these
    // landmarks. What is visible, and does matter, is the chest collapsing
    // forward *relative to the shins*: a sound squat keeps the torso roughly
    // parallel to the shin, whatever the depth. Comparing the two directions
    // also means nothing here depends on which way the camera or the athlete
    // is facing. Needs a confirmed side view to mean anything.
    final hasSideView = updateOrientation(pose);
    final shoulder = pose.landmarks[
        useLeft ? PoseLandmarkType.leftShoulder : PoseLandmarkType.rightShoulder];
    if (hasSideView && isLandmarkVisible(shoulder)) {
      final shoulderSmooth =
          _smooth(shoulder!, useLeft ? 'leftShoulder' : 'rightShoulder');
      final hipS = useLeft ? leftHipSmooth! : rightHipSmooth!;
      final kneeS = useLeft ? leftKneeSmooth! : rightKneeSmooth!;
      final ankleS = useLeft ? leftAnkleSmooth! : rightAnkleSmooth!;
      final lean = MathUtils.angleBetweenSegments(
        hipS.x, hipS.y, shoulderSmooth.x, shoulderSmooth.y,
        ankleS.x, ankleS.y, kneeS.x, kneeS.y,
      );
      if (squatState != SquatState.neutral &&
          lean > AppConstants.squatTorsoLeanMaxDegrees) {
        addIssue('Excessive Forward Lean');
        cues.request(CueIds.torsoLean);
      }
    }

    final deadZone = AppConstants.hysteresisDeadZoneDegrees;
    final directionDelta = AppConstants.angleDirectionDeltaDegrees;

    switch (squatState) {
      case SquatState.neutral:
        phase = RepPhase.neutral;
        if (currentAngle < AppConstants.squatNeutralThreshold - deadZone) {
          squatState = SquatState.eccentric;
          phase = RepPhase.eccentric;
          // Clear on entry (as pushup/lunge/OHP do) so issues from an aborted
          // rep can't carry over and penalise the next one.
          currentRepIssues.clear();
          _reachedDepth = false;
          _deepestAngle = unsmoothedAngle;
          markEccentricStart();
          statusMessage = 'Lower with control';
        } else {
          statusMessage = 'Squat down slowly';
        }
        break;

      case SquatState.eccentric:
        phase = RepPhase.eccentric;
        // Depth is checked against unsmoothedAngle, not the smoothed
        // currentAngle used everywhere else in this method. A fast rep's true
        // bottom can last just 1-2 frames -- confirmed against real stock
        // footage where a squat that hit 61-66 degrees at its actual deepest
        // frame only ever read 91-100 degrees through the smoothing pipeline,
        // narrowly missing squatDepthThreshold despite genuinely reaching
        // depth (see stock_footage_regression_test.dart). Depth is a one-shot
        // "did they ever get there" check, not something that needs temporal
        // stability the way the direction-reversal check below does, so it
        // can safely use the unsmoothed landmarks directly.
        _deepestAngle = math.min(_deepestAngle, unsmoothedAngle);

        if (unsmoothedAngle <= AppConstants.squatDepthThreshold) {
          _reachedDepth = true;
        }

        if (_reachedDepth && angleDelta > directionDelta) {
          squatState = SquatState.concentric;
          phase = RepPhase.concentric;
          _recovery.begin(now());
          markConcentricStart();
          statusMessage = 'Drive up';
        } else if (!_reachedDepth &&
            currentAngle >= AppConstants.squatNeutralThreshold) {
          // Stood back up without ever hitting depth. Without this branch the
          // analyzer stays in eccentric forever, so the next descent never
          // clears the issue list and no further rep is ever scored cleanly.
          squatState = SquatState.neutral;
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(CueIds.goDeeper, detail: _depthShortfall(_deepestAngle));
        } else if (!_reachedDepth && angleDelta > directionDelta) {
          cues.request(CueIds.goDeeper, detail: _depthShortfall(unsmoothedAngle));
        } else {
          statusMessage = _reachedDepth ? 'Great depth, stand up' : 'Lower';
        }
        break;

      case SquatState.concentric:
        phase = RepPhase.concentric;

        final verdict = currentAngle >= AppConstants.squatNeutralThreshold
            ? RecoveryVerdict.complete
            : _recovery.update(
                progress: -currentAngle,
                extreme: -_deepestAngle,
                rest: -AppConstants.squatNeutralThreshold,
                now: now(),
              );
        if (verdict == RecoveryVerdict.abandon) {
          squatState = SquatState.neutral;
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          _reachedDepth = false;
          _deepestAngle = 180;
        } else if (verdict == RecoveryVerdict.complete) {
          squatState = SquatState.neutral;
          phase = RepPhase.neutral;

          // Every rep that reverses direction and returns to standing counts,
          // the same as push-up/lunge/overhead press -- depth is a scored
          // fault here now, not a silent non-count. (A squat that never even
          // reverses -- stands back up mid-descent -- still isn't counted;
          // see the eccentric-phase branch above, unchanged and consistent
          // with every other exercise's equivalent "abandoned rep" case.)
          repCount++;
          double score = 1.0;
          if (!_reachedDepth) {
            addIssue('Insufficient Depth');
            score -= AppConstants.squatInsufficientDepthPenalty;
          }
          if (currentRepIssues.contains('Excessive Forward Lean')) {
            score -= AppConstants.squatTorsoLeanPenalty;
          }
          if (currentRepIssues.contains('Uneven Sides')) {
            score -= AppConstants.squatUnevenSidesPenalty;
          }
          if (currentRepIssues.contains('Knees Caving In')) {
            score -= AppConstants.squatKneeValgusPenalty;
          }

          statusMessage = 'Rep $repCount';
          recordRep(
            score: score,
            peakAngle: _deepestAngle,
            romDeficitDegrees: math.max(
              0,
              _deepestAngle - AppConstants.squatDepthThreshold,
            ),
          );
          if (onRep != null) onRep!(repCount);

          _reachedDepth = false;
          _deepestAngle = 180;
        } else {
          statusMessage = 'Stand tall';
        }
        break;
    }
  }

  /// Human-readable magnitude for a depth cue, e.g. "about 15 degrees short".
  /// Returns null when the gap is small enough not to be worth quantifying.
  static String? _depthShortfall(double angle) {
    final deficit = angle - AppConstants.squatDepthThreshold;
    if (deficit < 5) return null;
    return 'about ${deficit.round()} degrees short';
  }

  SmoothedLandmark _smooth(PoseLandmark landmark, String key) {
    return _landmarkSmoother.smooth(
      key: key,
      x: landmark.x,
      y: landmark.y,
      z: landmark.z,
      likelihood: landmark.likelihood,
    );
  }
}

class PushupAnalyzer extends ExerciseAnalyzer {
  PushupAnalyzer({super.cueEngine, super.clock});

  // Reps are found from the athlete's own range (see RepCycleDetector), never
  // from "reach 90 degrees, return past 155": live test #3 saw reps whose raw
  // elbow reached 55-80 degrees read 110-125 after smoothing and never count.
  final RepCycleDetector _cycle =
      RepCycleDetector(minExcursion: AppConstants.pushupMinExcursionDegrees);
  final RepCycleDetector _frontCycle = RepCycleDetector(
    minExcursion: AppConstants.pushupFrontMinExcursion,
    maxExcursion: AppConstants.pushupFrontMaxExcursion,
  );
  final ExponentialSmoothingFilter _signalFilter =
      ExponentialSmoothingFilter(alpha: AppConstants.repSignalSmoothingAlpha);
  final ExponentialSmoothingFilter _frontFilter =
      ExponentialSmoothingFilter(alpha: AppConstants.repSignalSmoothingAlpha);
  final MovingAverageFilter _backAngleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  final HipLineJudge _hipLine = HipLineJudge();

  /// Smallest raw elbow angle seen during the rep in progress.
  double _minRawAngle = 180;
  bool _headOn = false;
  double? _lastFrontDepth;
  DateTime? _frontLostSince;

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
      };

  /// A push-up is filmed from the side, or from a camera on the floor facing
  /// the athlete (where the elbow angle barely changes but the shoulders visibly
  /// drop toward the hands).
  @override
  bool acceptsOrientation(ViewOrientation observed) =>
      observed == ViewOrientation.sideOn || observed == ViewOrientation.frontOn;

  // Elbow angle is measured in the image plane only; see MathUtils.calculateAngle2D.
  @override
  bool get uses3dAngles => false;

  @override
  void reset() {
    super.reset();
    _cycle.reset();
    _frontCycle.reset();
    _signalFilter.reset();
    _frontFilter.reset();
    _backAngleFilter.reset();
    _hipLine.reset();
    _minRawAngle = 180;
    _headOn = false;
    _lastFrontDepth = null;
    _frontLostSince = null;
  }

  @override
  void processPose(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    final observed = orientationTracker.update(pose);
    final headOn = observed == ViewOrientation.frontOn;
    if (headOn != _headOn && observed != ViewOrientation.unknown) {
      _headOn = headOn;
      _abandonRep();
    }

    if (_headOn) {
      _processHeadOn(leftShoulder, rightShoulder, leftWrist, rightWrist);
      return;
    }

    if (!isLandmarkVisible(leftElbow) && !isLandmarkVisible(rightElbow)) {
      statusMessage = 'Adjust Camera';
      return;
    }

    final leftAngle = jointAngle(leftShoulder, leftElbow, leftWrist);
    final rightAngle = jointAngle(rightShoulder, rightElbow, rightWrist);
    final leftConfidence = (leftElbow?.likelihood ?? 0) + (leftWrist?.likelihood ?? 0);
    final rightConfidence = (rightElbow?.likelihood ?? 0) + (rightWrist?.likelihood ?? 0);
    final useLeft = leftConfidence >= rightConfidence;
    final rawAngle = useLeft ? leftAngle : rightAngle;
    final angle = _signalFilter.add(rawAngle);
    lastProcessedAngle = angle;

    _checkHipLine(pose, useLeft: useLeft);

    final event = _cycle.update(-angle, now());
    if (_cycle.isWorking) _minRawAngle = math.min(_minRawAngle, rawAngle);

    switch (event) {
      case CycleEvent.descentStarted:
        phase = RepPhase.eccentric;
        currentRepIssues.clear();
        _minRawAngle = rawAngle;
        markEccentricStart();
        statusMessage = 'Lower your chest';
      case CycleEvent.reversed:
        phase = RepPhase.concentric;
        markConcentricStart();
        statusMessage = 'Push up';
        if (_minRawAngle > AppConstants.pushupDepthThreshold) {
          addIssue('Insufficient Depth');
          cues.request(CueIds.goDeeper);
        }
      case CycleEvent.completed:
        _completeRep(
          shortOfDepth: _minRawAngle > AppConstants.pushupDepthThreshold,
          peakAngle: _minRawAngle,
          deficit: math.max(0, _minRawAngle - AppConstants.pushupDepthThreshold),
          lockedOut: -(_cycle.restLevel ?? -angle) >= AppConstants.pushupLockoutCueAngle,
        );
      case CycleEvent.abandoned:
        _abandonRep();
      case CycleEvent.none:
        if (!_cycle.isWorking) {
          statusMessage = 'Lower with control';
        } else if (phase == RepPhase.eccentric) {
          statusMessage = 'Lower';
        }
    }
  }

  /// Camera on the floor facing the athlete. The signal is how far the
  /// shoulders sit above the wrists, in shoulder widths: about 1.6 at the top of
  /// a push-up and 0.4-0.6 at the bottom, whatever the camera distance.
  void _processHeadOn(
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftWrist,
    PoseLandmark? rightWrist,
  ) {
    // Lower bar than the side view: with the camera on the floor the athlete's
    // face and hands swing right up to the lens, and the tracker's confidence
    // dips exactly at the bottom of the rep.
    bool seen(PoseLandmark? lm) =>
        lm != null && lm.likelihood >= AppConstants.pushupFrontMinLikelihood;
    final wrists = [leftWrist, rightWrist].where(seen).cast<PoseLandmark>().toList();
    if (!seen(leftShoulder) || !seen(rightShoulder) || wrists.isEmpty) {
      // A dropout in the middle of a rep means the athlete is still down there
      // (that is when the face fills the frame), so keep feeding the last
      // reading for a short while rather than losing the bottom of the rep.
      final held = _lastFrontDepth;
      final since = _frontLostSince ??= now();
      if (held != null &&
          _frontCycle.isWorking &&
          now().difference(since) < AppConstants.pushupFrontDropoutHold) {
        _frontCycle.update(held, now());
      } else if (!_frontCycle.isWorking) {
        statusMessage = 'Adjust Camera';
      }
      return;
    }
    _frontLostSince = null;
    final shoulderWidth = (leftShoulder!.x - rightShoulder!.x).abs();
    if (shoulderWidth < AppConstants.minMagnitude) {
      statusMessage = 'Adjust Camera';
      return;
    }
    final shoulderY = (leftShoulder.y + rightShoulder.y) / 2;
    final wristY = wrists.fold<double>(0, (sum, w) => sum + w.y) / wrists.length;
    final ratio = (wristY - shoulderY) / shoulderWidth;
    lastProcessedAngle = null;

    final depth = -_frontFilter.add(ratio * 100);
    _lastFrontDepth = depth;
    final event = _frontCycle.update(depth, now());

    switch (event) {
      case CycleEvent.descentStarted:
        phase = RepPhase.eccentric;
        currentRepIssues.clear();
        markEccentricStart();
        statusMessage = 'Lower your chest';
      case CycleEvent.reversed:
        phase = RepPhase.concentric;
        markConcentricStart();
        statusMessage = 'Push up';
      case CycleEvent.completed:
        final top = -_frontCycle.lastRest / 100;
        final bottom = -_frontCycle.lastPeak / 100;
        final short = top > 0 && bottom > AppConstants.pushupFrontDepthRatio * top;
        _completeRep(shortOfDepth: short, peakAngle: null, deficit: 0, lockedOut: true);
      case CycleEvent.abandoned:
        _abandonRep();
      case CycleEvent.none:
        if (!_frontCycle.isWorking) {
          statusMessage = 'Lower with control';
        } else if (phase == RepPhase.eccentric) {
          statusMessage = 'Lower';
        }
    }
  }

  /// Straight shoulder-hip-knee line, same idea as plank. Only judged from the
  /// side, and only while a rep is under way.
  void _checkHipLine(Pose pose, {required bool useLeft}) {
    final shoulder =
        pose.landmarks[useLeft ? PoseLandmarkType.leftShoulder : PoseLandmarkType.rightShoulder];
    final hip = pose.landmarks[useLeft ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip];
    final knee = pose.landmarks[useLeft ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee];
    if (!isLandmarkVisible(shoulder) || !isLandmarkVisible(hip) || !isLandmarkVisible(knee)) {
      return;
    }
    // Keep the judge fed between reps too, so it has settled by the time one
    // starts.
    final verdict = _hipLine.update(shoulder!, hip!, knee!, now: now());
    if (phase == RepPhase.neutral) return;

    // Smoothed like every other angle here: a single noisy frame must not tag
    // a whole rep as sagging, since the flag has no recovery once raised
    // (pushup_pixabay_302251 hit a one-frame dip early in a long rep).
    final backAngle = _backAngleFilter.add(MathUtils.calculateJointAngle(shoulder, hip, knee));
    if (backAngle < AppConstants.pushupBackAngleMin) {
      switch (verdict) {
        case HipVerdict.sagging:
          // A rep has one dominant hip fault; once called, the other verdict
          // is ignored so two contradictory penalties cannot stack.
          if (!currentRepIssues.contains('Hips Piked')) {
            addIssue('Hips Sagging');
            cues.request(CueIds.hipsSagging);
          }
        case HipVerdict.piked:
          if (!currentRepIssues.contains('Hips Sagging')) {
            addIssue('Hips Piked');
            cues.request(CueIds.hipsPiked);
          }
        case HipVerdict.unjudgeable:
        case HipVerdict.undecided:
          // Leaning on a wall or a steep incline: no floor to sag toward, but
          // the line is still broken.
          addIssue('Body Not Straight');
          cues.request(CueIds.straightBody);
      }
    } else {
      currentRepIssues.remove('Hips Sagging');
      currentRepIssues.remove('Hips Piked');
      currentRepIssues.remove('Body Not Straight');
    }
  }

  void _completeRep({
    required bool shortOfDepth,
    required double? peakAngle,
    required double deficit,
    required bool lockedOut,
  }) {
    repCount++;
    var score = 1.0;
    if (shortOfDepth) {
      addIssue('Insufficient Depth');
      score -= AppConstants.pushupInsufficientDepthPenalty;
    } else {
      currentRepIssues.remove('Insufficient Depth');
    }
    // Lockout is a live cue only, not scored: it has no recovery once flagged,
    // so one early wobble would penalise an otherwise clean rep.
    if (!lockedOut) cues.request(CueIds.lockOut);
    if (currentRepIssues.contains('Hips Sagging')) {
      score -= AppConstants.pushupHipAlignmentPenalty;
    }
    if (currentRepIssues.contains('Hips Piked')) {
      score -= AppConstants.pushupHipAlignmentPenalty;
    }
    if (currentRepIssues.contains('Body Not Straight')) {
      score -= AppConstants.pushupHipAlignmentPenalty;
    }
    statusMessage = 'Rep $repCount';
    recordRep(score: score, peakAngle: peakAngle, romDeficitDegrees: deficit);
    phase = RepPhase.neutral;
    _minRawAngle = 180;
    if (onRep != null) onRep!(repCount);
  }

  void _abandonRep() {
    phase = RepPhase.neutral;
    currentRepIssues.clear();
    _minRawAngle = 180;
  }
}

class LungeAnalyzer extends ExerciseAnalyzer {
  LungeAnalyzer({super.cueEngine, super.clock});

  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevAngle;
  bool _reachedDepth = false;
  double _deepestAngle = 180;
  final RecoveryDetector _recovery = RecoveryDetector();

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      };

  @override
  void reset() {
    super.reset();
    _angleFilter.reset();
    _prevAngle = null;
    _reachedDepth = false;
    _deepestAngle = 180;
    _recovery.reset();
  }

  @override
  void processPose(Pose pose) {
    final leftShoulderLandmark = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHipLandmark = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKneeLandmark = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkleLandmark = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightShoulderLandmark = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHipLandmark = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKneeLandmark = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkleLandmark = pose.landmarks[PoseLandmarkType.rightAnkle];

    final leftVisible = isLandmarkVisible(leftHipLandmark) &&
        isLandmarkVisible(leftKneeLandmark) &&
        isLandmarkVisible(leftAnkleLandmark);
    final rightVisible = isLandmarkVisible(rightHipLandmark) &&
        isLandmarkVisible(rightKneeLandmark) &&
        isLandmarkVisible(rightAnkleLandmark);

    if (!leftVisible && !rightVisible) {
      statusMessage = 'Adjust Camera';
      return;
    }

    final leftKnee = leftVisible
        ? MathUtils.calculateJointAngle(leftHipLandmark, leftKneeLandmark, leftAnkleLandmark)
        : 180.0;
    final rightKnee = rightVisible
        ? MathUtils.calculateJointAngle(rightHipLandmark, rightKneeLandmark, rightAnkleLandmark)
        : 180.0;

    // Both legs bend in a lunge. Depth is satisfied if either visible knee dips
    // below the depth threshold. For standing lockout / neutral, the athlete
    // recovers when the standing/supporting leg reaches extension.
    final frontIsLeft = leftVisible && (!rightVisible || leftKnee <= rightKnee);
    final depthAngle = (leftVisible && rightVisible)
        ? math.min(leftKnee, rightKnee)
        : (leftVisible ? leftKnee : rightKnee);
    final standingAngle = (leftVisible && rightVisible)
        ? math.max(leftKnee, rightKnee)
        : (leftVisible ? leftKnee : rightKnee);

    final currentAngle = _angleFilter.add(standingAngle);
    final delta = _prevAngle == null ? 0.0 : currentAngle - _prevAngle!;
    _prevAngle = currentAngle;
    lastProcessedAngle = currentAngle;

    // Front (more bent) knee drifting past the toe -- classic lunge fault,
    // measured as a fraction of shin length so it holds at any camera
    // distance. Only checked once genuinely working the rep.
    final frontKnee = frontIsLeft ? leftKneeLandmark : rightKneeLandmark;
    final frontAnkle = frontIsLeft ? leftAnkleLandmark : rightAnkleLandmark;
    if (phase == RepPhase.eccentric && frontKnee != null && frontAnkle != null) {
      final shinLength = math.sqrt(
        math.pow(frontKnee.x - frontAnkle.x, 2) + math.pow(frontKnee.y - frontAnkle.y, 2),
      );
      if (MathUtils.horizontalOffsetRatio(frontKnee, frontAnkle, shinLength) >
          AppConstants.lungeKneePastToeRatio) {
        addIssue('Knee Past Toe');
        cues.request(CueIds.kneePastToe);
      } else {
        currentRepIssues.remove('Knee Past Toe');
      }
    }

    // Torso should stay upright, not pitch forward or back into the lunge.
    final leanShoulder = frontIsLeft ? leftShoulderLandmark : rightShoulderLandmark;
    final leanHip = frontIsLeft ? leftHipLandmark : rightHipLandmark;
    if (phase == RepPhase.eccentric &&
        isLandmarkVisible(leanShoulder) &&
        isLandmarkVisible(leanHip)) {
      final lean = MathUtils.degreesFromVertical(leanShoulder!, leanHip!);
      if (lean > AppConstants.lungeTorsoLeanMaxDegrees) {
        addIssue('Torso Lean');
        cues.request(CueIds.torsoLean);
      } else {
        currentRepIssues.remove('Torso Lean');
      }
    }

    final deadZone = AppConstants.hysteresisDeadZoneDegrees;

    switch (phase) {
      case RepPhase.neutral:
        if (currentAngle < AppConstants.lungeNeutralThreshold - deadZone) {
          phase = RepPhase.eccentric;
          currentRepIssues.clear();
          _reachedDepth = false;
          _deepestAngle = depthAngle;
          markEccentricStart();
          statusMessage = 'Lower into lunge';
        } else {
          statusMessage = 'Step forward and lower';
        }
        break;

      case RepPhase.eccentric:
        _deepestAngle = math.min(_deepestAngle, depthAngle);

        if (depthAngle <= AppConstants.lungeDepthThreshold) {
          _reachedDepth = true;
          currentRepIssues.remove('Insufficient Depth');
        }

        if (_reachedDepth && delta > AppConstants.angleDirectionDeltaDegrees) {
          phase = RepPhase.concentric;
          _recovery.begin(now());
          markConcentricStart();
          statusMessage = 'Drive up';
        } else if (!_reachedDepth &&
            currentAngle >= AppConstants.lungeNeutralThreshold) {
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(CueIds.goDeeper);
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            depthAngle > AppConstants.lungeDepthThreshold + deadZone) {
          addIssue('Insufficient Depth');
          cues.request(CueIds.goDeeper);
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        final verdict = currentAngle >= AppConstants.lungeNeutralThreshold
            ? RecoveryVerdict.complete
            : _recovery.update(
                progress: -currentAngle,
                extreme: -_deepestAngle,
                rest: -AppConstants.lungeNeutralThreshold,
                now: now(),
              );
        if (verdict == RecoveryVerdict.abandon) {
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          _reachedDepth = false;
          _deepestAngle = 180;
        } else if (verdict == RecoveryVerdict.complete) {
          repCount++;
          double score = 1.0;
          if (!_reachedDepth || currentRepIssues.contains('Insufficient Depth')) {
            addIssue('Insufficient Depth');
            score -= AppConstants.lungeInsufficientDepthPenalty;
          }
          if (currentRepIssues.contains('Knee Past Toe')) {
            score -= AppConstants.lungeKneePastToePenalty;
          }
          if (currentRepIssues.contains('Torso Lean')) {
            score -= AppConstants.lungeTorsoLeanPenalty;
          }
          statusMessage = 'Rep $repCount';
          recordRep(
            score: score,
            peakAngle: _deepestAngle,
            romDeficitDegrees: math.max(
              0,
              _deepestAngle - AppConstants.lungeDepthThreshold,
            ),
          );
          _reachedDepth = false;
          _deepestAngle = 180;
          phase = RepPhase.neutral;
          if (onRep != null) onRep!(repCount);
        } else {
          statusMessage = 'Return to neutral standing';
        }
        break;
    }
  }
}

class OverheadPressAnalyzer extends ExerciseAnalyzer {
  OverheadPressAnalyzer({super.cueEngine, super.clock});

  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevAngle;
  bool _reachedBottom = false;
  double _concentricPeak = 0;
  double _deepestAngle = 180;
  final RecoveryDetector _recovery = RecoveryDetector();

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
      };

  @override
  void reset() {
    super.reset();
    _angleFilter.reset();
    _prevAngle = null;
    _reachedBottom = false;
    _concentricPeak = 0;
    _deepestAngle = 180;
    _recovery.reset();
  }

  @override
  void processPose(Pose pose) {
    final leftShoulderLandmark = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbowLandmark = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWristLandmark = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightShoulderLandmark = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbowLandmark = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWristLandmark = pose.landmarks[PoseLandmarkType.rightWrist];

    final leftVisible = isLandmarkVisible(leftShoulderLandmark) &&
        isLandmarkVisible(leftElbowLandmark) &&
        isLandmarkVisible(leftWristLandmark);
    final rightVisible = isLandmarkVisible(rightShoulderLandmark) &&
        isLandmarkVisible(rightElbowLandmark) &&
        isLandmarkVisible(rightWristLandmark);

    final leftElbow = MathUtils.calculateJointAngle(
      leftShoulderLandmark,
      leftElbowLandmark,
      leftWristLandmark,
    );
    final rightElbow = MathUtils.calculateJointAngle(
      rightShoulderLandmark,
      rightElbowLandmark,
      rightWristLandmark,
    );

    // Wrist should stay roughly stacked above the elbow, not flared out to
    // the side, at the top of the press -- checked per-arm (whichever is
    // visible) rather than by comparing the two sides against each other.
    // A left-vs-right comparison was tried here first and dropped: real
    // footage of a machine press with one arm's tracking confidence
    // genuinely degraded showed the *measured* asymmetry swinging from 4 to
    // 54 degrees frame to frame on the exact same rep -- a tracking-quality
    // artifact, not a real form difference, and the same failure mode the
    // bilateral-extremum lockout/depth logic above already exists to avoid.
    // A leaning-back/vertical check was also tried and dropped: on a seated
    // machine-press clip it measured a rock-steady ~27-28 degree lean for
    // every single rep -- the seat's own fixed recline, not a dynamic fault,
    // and nothing in the available landmarks distinguishes a reclined
    // machine seat from someone genuinely arching back.
    final wristElbow = leftVisible ? leftElbowLandmark : (rightVisible ? rightElbowLandmark : null);
    final wrist = leftVisible ? leftWristLandmark : (rightVisible ? rightWristLandmark : null);
    if (phase != RepPhase.neutral && isLandmarkVisible(wristElbow) && isLandmarkVisible(wrist)) {
      final forearmLength = math.sqrt(
        math.pow(wristElbow!.x - wrist!.x, 2) + math.pow(wristElbow.y - wrist.y, 2),
      );
      if (MathUtils.horizontalOffsetRatio(wrist, wristElbow, forearmLength) >
          AppConstants.overheadPressWristOffsetRatio) {
        addIssue('Wrist Not Stacked');
        cues.request(CueIds.elbowsOut);
      } else {
        currentRepIssues.remove('Wrist Not Stacked');
      }
    }

    // Both arms press together in an overhead press. When both sides are
    // visible, trust whichever shows genuine lockout (max) for the
    // lockout/neutral-threshold comparisons that drive phase transitions and
    // rep-closing, and whichever shows genuine depth (min) for tracking
    // whether the bottom was reached -- a confidence gap between the two
    // sides reflects estimation error, not anatomy, the same principle
    // already applied to Squat/Lunge/GluteBridge. Confirmed against real
    // stock footage where the higher-confidence (left) arm read up to ~141
    // degrees for an entire set while the other arm -- still comfortably
    // visible -- read 156-171 degrees for the same frames; picking a side by
    // confidence alone missed genuine lockouts for the whole clip.
    final lockoutAngle = (leftVisible && rightVisible)
        ? math.max(leftElbow, rightElbow)
        : (leftVisible ? leftElbow : rightElbow);
    final bottomAngle = (leftVisible && rightVisible)
        ? math.min(leftElbow, rightElbow)
        : (leftVisible ? leftElbow : rightElbow);

    final currentAngle = _angleFilter.add(lockoutAngle);
    final delta = _prevAngle == null ? 0.0 : currentAngle - _prevAngle!;
    _prevAngle = currentAngle;
    lastProcessedAngle = currentAngle;

    if (!leftVisible && !rightVisible) {
      statusMessage = 'Adjust Camera';
      return;
    }

    final deadZone = AppConstants.hysteresisDeadZoneDegrees;

    switch (phase) {
      case RepPhase.neutral:
        if (currentAngle < AppConstants.overheadPressLockoutThreshold - deadZone) {
          phase = RepPhase.eccentric;
          currentRepIssues.clear();
          _reachedBottom = false;
          _deepestAngle = bottomAngle;
          markEccentricStart();
          statusMessage = 'Lower to shoulder level';
        } else {
          statusMessage = 'Lower under control';
        }
        break;

      case RepPhase.eccentric:
        _deepestAngle = math.min(_deepestAngle, bottomAngle);

        if (bottomAngle <= AppConstants.overheadPressStartThreshold) {
          _reachedBottom = true;
          currentRepIssues.remove('Insufficient Range');
        }

        if (_reachedBottom && delta > AppConstants.angleDirectionDeltaDegrees) {
          phase = RepPhase.concentric;
          _concentricPeak = currentAngle;
          _recovery.begin(now());
          markConcentricStart();
          statusMessage = 'Press up';
        } else if (!_reachedBottom &&
            currentAngle >= AppConstants.overheadPressLockoutThreshold) {
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(CueIds.fullRange);
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            bottomAngle > AppConstants.overheadPressStartThreshold + deadZone) {
          addIssue('Insufficient Range');
          cues.request(CueIds.fullRange);
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        final verdict = currentAngle >= AppConstants.overheadPressLockoutThreshold
            ? RecoveryVerdict.complete
            : _recovery.update(
                progress: -currentAngle,
                extreme: -_deepestAngle,
                rest: -AppConstants.overheadPressLockoutThreshold,
                now: now(),
              );
        if (verdict == RecoveryVerdict.abandon) {
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          _reachedBottom = false;
          _concentricPeak = 0;
          _deepestAngle = 180;
        } else if (verdict == RecoveryVerdict.complete) {
          repCount++;
          double score = 1.0;
          if (!_reachedBottom || currentRepIssues.contains('Insufficient Range')) {
            addIssue('Insufficient Range');
            score -= AppConstants.overheadPressInsufficientRangePenalty;
          }
          // Not scored -- same recovery gap as push-up's 'Incomplete
          // Lockout' (see that comment); left as a live cue only.
          currentRepIssues.remove('No Full Lockout');
          if (currentRepIssues.contains('Wrist Not Stacked')) {
            score -= AppConstants.overheadPressWristOffsetPenalty;
          }
          statusMessage = 'Rep $repCount';
          recordRep(
            score: score,
            peakAngle: _deepestAngle,
            romDeficitDegrees: math.max(
              0,
              _deepestAngle - AppConstants.overheadPressStartThreshold,
            ),
          );
          _reachedBottom = false;
          _concentricPeak = 0;
          _deepestAngle = 180;
          phase = RepPhase.neutral;
          if (onRep != null) onRep!(repCount);
        } else {
          // Same as pushup: sinking back from the highest point reached without
          // ever locking out is the fault, not simply being mid-press.
          _concentricPeak = math.max(_concentricPeak, currentAngle);
          if (currentAngle < _concentricPeak - deadZone) {
            addIssue('No Full Lockout');
            cues.request(CueIds.lockOut);
          }
          statusMessage = 'Reach higher';
        }
        break;
    }
  }
}

/// A rep-counted exercise expressed as travel along a single joint angle.
///
/// The four original analyzers each hand-rolled this state machine, which is
/// how the same two bugs (sticking in the eccentric phase after a short rep,
/// and entering the concentric phase before the athlete had actually reversed)
/// ended up copied into all of them. Exercises added since share this instead.
///
/// Movement direction is expressed through [worksTowardSmallerAngle], so the
/// same machine drives a squat (angle closes as you descend) and a glute bridge
/// (angle opens as you lift).
abstract class RangeOfMotionAnalyzer extends ExerciseAnalyzer {
  RangeOfMotionAnalyzer({super.cueEngine, super.clock});

  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevProgress;
  bool _reachedTarget = false;
  double _bestProgress = double.negativeInfinity;
  final RecoveryDetector _recovery = RecoveryDetector(allowRocking: true);
  DateTime? _eccentricEnteredAt;

  /// Angle the athlete rests at between reps.
  double get restAngle;

  /// Angle that counts as having completed the working range.
  double get targetAngle;

  /// True when working through the range makes the measured angle smaller.
  bool get worksTowardSmallerAngle;

  /// Score lost when a rep finishes without reaching [targetAngle].
  double get shortRangePenalty;

  /// Issue label recorded for a rep that fell short.
  String get shortRangeIssue => 'Insufficient Depth';

  /// Cue requested when the athlete keeps falling short.
  String get shortRangeCueId => CueIds.goDeeper;

  /// Status text while travelling toward the target.
  String get workingMessage;

  /// Status text while returning to rest.
  String get returningMessage;

  /// Status text while at rest.
  String get restingMessage;

  /// Measure the driving joint angle, or return null when the landmarks
  /// needed aren't visible.
  double? measureAngle(Pose pose);

  /// Hook for exercise-specific form checks beyond the shared range-of-motion
  /// state machine above (e.g. glute bridge's knee valgus, sit-up's knee
  /// bend). Called every frame while working through the rep; implementations
  /// call [addIssue] directly, same as [measureAngle]'s caller does for
  /// [shortRangeIssue]. Default is a no-op for exercises that don't need one.
  void checkFormIssues(Pose pose) {}

  /// Score penalty for each issue label [checkFormIssues] might add, applied
  /// once per rep at completion. Exercises that don't override
  /// [checkFormIssues] don't need to override this either.
  Map<String, double> get supplementaryPenalties => const {};

  /// Share of the rest-to-target range a rep must cover to count, scored as
  /// short, rather than being discarded as an abandoned attempt.
  double get partialRepFraction => 0.6;

  /// Signed so that "further into the movement" always means "larger".
  double _progress(double angle) => worksTowardSmallerAngle ? -angle : angle;

  double _angleOf(double progress) => worksTowardSmallerAngle ? -progress : progress;

  @override
  void reset() {
    super.reset();
    _angleFilter.reset();
    _prevProgress = null;
    _reachedTarget = false;
    _bestProgress = double.negativeInfinity;
    _recovery.reset();
    _eccentricEnteredAt = null;
  }

  @override
  void processPose(Pose pose) {
    final measured = measureAngle(pose);
    if (measured == null) {
      statusMessage = 'Adjust Camera';
      return;
    }

    updateOrientation(pose);

    final smoothed = _angleFilter.add(measured);
    lastProcessedAngle = smoothed;

    final progress = _progress(smoothed);
    final restProgress = _progress(restAngle);
    final targetProgress = _progress(targetAngle);
    final delta = _prevProgress == null ? 0.0 : progress - _prevProgress!;
    _prevProgress = progress;

    final deadZone = AppConstants.hysteresisDeadZoneDegrees;
    final directionDelta = AppConstants.angleDirectionDeltaDegrees;

    switch (phase) {
      case RepPhase.neutral:
        if (progress > restProgress + deadZone) {
          phase = RepPhase.eccentric;
          currentRepIssues.clear();
          _reachedTarget = false;
          _bestProgress = progress;
          _eccentricEnteredAt = now();
          markEccentricStart();
          statusMessage = workingMessage;
        } else {
          statusMessage = restingMessage;
        }

      case RepPhase.eccentric:
        _bestProgress = math.max(_bestProgress, progress);
        checkFormIssues(pose);

        if (progress >= targetProgress) {
          _reachedTarget = true;
        }

        if (_reachedTarget && delta < -directionDelta) {
          // Only once the athlete has genuinely reversed.
          phase = RepPhase.concentric;
          _recovery.begin(now());
          markConcentricStart();
          statusMessage = returningMessage;
        } else if (_eccentricEnteredAt != null &&
            now().difference(_eccentricEnteredAt!) > const Duration(seconds: 12)) {
          // Wandered off mid-rep (or the athlete simply stopped); don't wait
          // forever for a target that is not coming.
          phase = RepPhase.neutral;
          currentRepIssues.clear();
        } else if (!_reachedTarget && progress <= restProgress) {
          // Back to the start without completing the range — return to neutral
          // rather than stalling here forever.
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(shortRangeCueId);
        } else if (!_reachedTarget && delta < -directionDelta) {
          addIssue(shortRangeIssue);
          cues.request(shortRangeCueId);
          // Came most of the way and is now heading back: that is a rep, just
          // a short one. Silently discarding it made real, repeated jacks
          // (arms peaking ~110 of a 130 degree target) count as nothing at
          // all. Score the shortfall instead, as the squat does for depth.
          final partialProgress =
              restProgress + partialRepFraction * (targetProgress - restProgress);
          if (_bestProgress >= partialProgress &&
              progress < _bestProgress - deadZone) {
            phase = RepPhase.concentric;
            _recovery.begin(now());
            markConcentricStart();
            statusMessage = returningMessage;
          }
        } else {
          statusMessage = workingMessage;
        }

      case RepPhase.concentric:
        _bestProgress = math.max(_bestProgress, progress);
        final verdict = progress <= restProgress
            ? RecoveryVerdict.complete
            : _recovery.update(
                progress: progress,
                extreme: _bestProgress,
                rest: restProgress,
                now: now(),
              );
        if (verdict == RecoveryVerdict.abandon) {
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          _reachedTarget = false;
          _bestProgress = double.negativeInfinity;
          statusMessage = restingMessage;
        } else if (verdict == RecoveryVerdict.complete) {
          repCount++;

          var score = 1.0;
          if (!_reachedTarget || currentRepIssues.contains(shortRangeIssue)) {
            addIssue(shortRangeIssue);
            score -= shortRangePenalty;
          }
          for (final issue in currentRepIssues) {
            score -= supplementaryPenalties[issue] ?? 0.0;
          }

          statusMessage = 'Rep $repCount';
          recordRep(
            score: score,
            peakAngle: _angleOf(_bestProgress),
            romDeficitDegrees: math.max(0, targetProgress - _bestProgress),
          );

          phase = RepPhase.neutral;
          _reachedTarget = false;
          _bestProgress = double.negativeInfinity;
          if (onRep != null) onRep!(repCount);
        } else {
          statusMessage = returningMessage;
        }
    }
  }
}

/// The result of judging a single frame of a hold-style exercise.
class HoldEvaluation {
  final bool isCorrect;

  /// Cue to request while form is broken.
  final String cueId;

  /// Issue label recorded against the seconds held with broken form.
  final String issue;

  /// True when the athlete has gone out of the exercise position altogether
  /// (stood up, walked off) as opposed to holding it badly. The clock stops.
  final bool leftPosition;

  /// What to show while [leftPosition]; a generic prompt when null.
  final String? message;

  const HoldEvaluation.good()
      : isCorrect = true,
        cueId = '',
        issue = '',
        leftPosition = false,
        message = null;

  const HoldEvaluation.broken({
    required this.cueId,
    required this.issue,
    this.leftPosition = false,
    this.message,
  }) : isCorrect = false;
}

/// Base class for exercises measured in held seconds rather than reps
/// (plank, wall sit, side plank).
///
/// Duration is reported through [repCount] and — critically — through [onRep],
/// the same channel rep-counted exercises use. `ExerciseScreen` only saves a
/// session when its rep count is above zero, so a timed analyzer that never
/// fires [onRep] records nothing at all.
abstract class TimedExerciseAnalyzer extends ExerciseAnalyzer {
  TimedExerciseAnalyzer({super.cueEngine, super.clock});

  @override
  bool get isTimedHold => true;

  // A hold only needs approximate geometry (is the body line roughly straight?),
  // not the precision rep counting wants, and a strict bar kept pausing the
  // clock: on live test #3 the knees sat just under 0.7 for seconds at a time
  // and an 18 second plank was credited as 12.
  @override
  double get minLikelihood => AppConstants.holdVisibilityThreshold;

  /// Whether persistently broken form is read as having left the position, and
  /// stops the clock after [AppConstants.timedHoldBreakGraceSeconds]. Holds that
  /// can tell for themselves (see [HoldEvaluation.leftPosition]) turn this off,
  /// so a sagging plank is still time under tension.
  bool get stopsClockOnLongBreak => true;

  /// A hold keeps its accumulated time when interrupted; only the running
  /// clock stops until the athlete is back in position.
  @override
  void interrupt() {
    _lastFrameTime = null;
    _brokenSince = null;
    statusMessage = 'Paused';
  }

  DateTime? _lastFrameTime;
  int _accumulatedHeldMs = 0;
  DateTime? _brokenSince;
  int _lastScoredSecond = 0;

  /// Judge the current frame. Return null when the required landmarks aren't
  /// visible, which pauses the clock rather than counting bad time.
  HoldEvaluation? evaluateHold(Pose pose);

  /// Status line shown while the hold is going well.
  String holdingMessage(int seconds);

  int get heldSeconds => _accumulatedHeldMs ~/ 1000;

  @override
  void processPose(Pose pose) {
    final evaluation = evaluateHold(pose);
    final currentTime = now();

    if (evaluation == null) {
      // A dropout of a second or so (a hand crossing the camera, one noisy
      // frame) is not the athlete leaving the position. Pausing the clock on
      // every one of them meant a ~35 second plank was credited as 14.
      final last = _lastFrameTime;
      if (last != null &&
          currentTime.difference(last) < const Duration(milliseconds: 1500)) {
        return;
      }
      _lastFrameTime = null;
      _brokenSince = null;
      statusMessage = 'Adjust Camera';
      return;
    }

    if (evaluation.leftPosition) {
      _lastFrameTime = null;
      _brokenSince = null;
      statusMessage = evaluation.message ?? 'Get back into position';
      if (evaluation.cueId.isNotEmpty) cues.request(evaluation.cueId);
      return;
    }

    if (_lastFrameTime != null) {
      final deltaMs = currentTime.difference(_lastFrameTime!).inMilliseconds;
      if (deltaMs > 0 && deltaMs <= 2000) {
        _accumulatedHeldMs += deltaMs;
      }
    }
    _lastFrameTime = currentTime;

    if (evaluation.isCorrect) {
      _brokenSince = null;
      _accrue(1.0);
      statusMessage = holdingMessage(heldSeconds);
      return;
    }

    // Form is broken but the user is still in position, so the clock keeps
    // running — a sagging plank is still time under tension. If it stays broken
    // long enough we assume they've stood up and stop counting.
    _brokenSince ??= currentTime;
    final brokenForMs = currentTime.difference(_brokenSince!).inMilliseconds;
    if (stopsClockOnLongBreak &&
        brokenForMs >= AppConstants.timedHoldBreakGraceSeconds * 1000) {
      _lastFrameTime = null;
    }

    addIssue(evaluation.issue);
    _accrue(AppConstants.timedHoldBrokenFormScore);
    cues.request(evaluation.cueId);
  }

  /// Credit whole seconds that have elapsed since the last check, scoring each
  /// with the quality that applied when it ticked over.
  void _accrue(double secondScore) {
    final seconds = heldSeconds;
    if (seconds <= _lastScoredSecond) return;

    for (var s = _lastScoredSecond; s < seconds; s++) {
      repRecords.add(
        RepRecord(
          index: s + 1,
          score: secondScore,
          issues: List<String>.from(currentRepIssues),
        ),
      );
    }
    _lastScoredSecond = seconds;
    currentRepIssues.clear();

    repCount = seconds;
    // A fresh second is the timed equivalent of a new rep, so per-rep cue
    // suppression lifts and the athlete can be told again if form is still off.
    cues.beginRep();
    if (onRep != null) onRep!(repCount);
  }

  @override
  void reset() {
    super.reset();
    _lastFrameTime = null;
    _accumulatedHeldMs = 0;
    _brokenSince = null;
    _lastScoredSecond = 0;
  }
}

class PlankAnalyzer extends TimedExerciseAnalyzer {
  PlankAnalyzer({super.cueEngine, super.clock});

  final HipLineJudge _hipLine = HipLineJudge();
  final SettleGate _gate = SettleGate();

  @override
  bool get stopsClockOnLongBreak => false;

  @override
  void reset() {
    super.reset();
    _hipLine.reset();
    _gate.reset();
  }

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
      };

  @override
  String holdingMessage(int seconds) => 'Hold tight! Core engaged: ${seconds}s';

  @override
  HoldEvaluation? evaluateHold(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

    final leftVisible = isLandmarkVisible(leftShoulder) &&
        isLandmarkVisible(leftHip) &&
        isLandmarkVisible(leftKnee);
    final rightVisible = isLandmarkVisible(rightShoulder) &&
        isLandmarkVisible(rightHip) &&
        isLandmarkVisible(rightKnee);

    if (!leftVisible && !rightVisible) {
      return null;
    }

    final leftConfidence = (leftShoulder?.likelihood ?? 0) +
        (leftHip?.likelihood ?? 0) +
        (leftKnee?.likelihood ?? 0);
    final rightConfidence = (rightShoulder?.likelihood ?? 0) +
        (rightHip?.likelihood ?? 0) +
        (rightKnee?.likelihood ?? 0);

    final useLeft = leftVisible && (!rightVisible || leftConfidence >= rightConfidence);
    final shoulder = useLeft ? leftShoulder! : rightShoulder!;
    final hip = useLeft ? leftHip! : rightHip!;
    final knee = useLeft ? leftKnee! : rightKnee!;

    final backAngle = MathUtils.calculateJointAngle(shoulder, hip, knee);
    lastProcessedAngle = backAngle;

    // A plank is on the floor, so the body lies roughly flat once the frame is
    // gravity-aligned. Upright is standing up (or leaning on a wall, which is
    // not a plank however straight the line): not in position, and no time is
    // credited. Bending the line, by contrast, is bad form, not leaving.
    final flat = !gravityKnown ||
        HipLineJudge.tiltFromHorizontal(shoulder, knee) <= AppConstants.holdMaxTiltDegrees;
    final settled = _gate.update(flat, now());
    if (!flat) return _notInPlank;
    if (!settled) return _settling;

    // Fed every frame, straight or not, so it has settled before the line breaks.
    final verdict = _hipLine.update(shoulder, hip, knee, now: now());
    if (backAngle <= AppConstants.plankBackAngleMin) {
      return _brokenLine(verdict);
    }

    // Elbow drifting out from under the shoulder, as a fraction of torso
    // length -- checked only once the hip line itself is already good, since
    // that's the more important fault.
    final elbow = pose.landmarks[useLeft ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow];
    final wrist = pose.landmarks[useLeft ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist];
    // Straight arms make a high plank, which is a legitimate plank whose
    // elbows are by definition not "under" the shoulders in the forearm sense;
    // only judge elbow position on a forearm (bent-elbow) plank.
    final highPlank = isLandmarkVisible(wrist) &&
        isLandmarkVisible(elbow) &&
        MathUtils.calculateJointAngle(shoulder, elbow, wrist) >=
            AppConstants.highPlankElbowAngleMin;
    if (isLandmarkVisible(elbow) && !highPlank) {
      final torsoLength =
          math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
      if (MathUtils.horizontalOffsetRatio(elbow!, shoulder, torsoLength) >
          AppConstants.plankElbowOffsetRatio) {
        return const HoldEvaluation.broken(
          issue: 'Elbows Not Under Shoulders',
          cueId: CueIds.elbowsOut,
        );
      }
    }

    // Hip twisted/dropped to one side rather than square to the floor.
    if (leftVisible && rightVisible) {
      final leftAngle = MathUtils.calculateJointAngle(leftShoulder, leftHip, leftKnee);
      final rightAngle = MathUtils.calculateJointAngle(rightShoulder, rightHip, rightKnee);
      if ((leftAngle - rightAngle).abs() > AppConstants.plankHipAsymmetryDegreesThreshold) {
        return const HoldEvaluation.broken(
          issue: 'Uneven Hips',
          cueId: CueIds.asymmetry,
        );
      }
    }

    return const HoldEvaluation.good();
  }
}

/// Waits for an athlete to have been in position for a moment before a hold is
/// judged, so the seconds spent lowering into a plank are not scored as a
/// broken one ("Hips up", then "Lower your hips" 0.2 seconds later).
class SettleGate {
  SettleGate({this.settle = const Duration(milliseconds: 1500), this.grace = const Duration(milliseconds: 600)});

  final Duration settle;

  /// Brief wobbles out of position (one bad frame) do not restart the wait.
  final Duration grace;

  DateTime? _inSince;
  DateTime? _outSince;

  void reset() {
    _inSince = null;
    _outSince = null;
  }

  /// Returns true once the athlete has been continuously in position for
  /// [settle].
  bool update(bool inPosition, DateTime now) {
    if (inPosition) {
      _outSince = null;
      _inSince ??= now;
    } else {
      _outSince ??= now;
      if (now.difference(_outSince!) > grace) _inSince = null;
    }
    final since = _inSince;
    return since != null && now.difference(since) >= settle;
  }
}

const HoldEvaluation _settling = HoldEvaluation.broken(
  issue: 'Settling',
  cueId: '',
  leftPosition: true,
  message: 'Hold steady...',
);

const HoldEvaluation _notInPlank = HoldEvaluation.broken(
  issue: 'Not In Position',
  cueId: CueIds.getInPlank,
  leftPosition: true,
  message: 'Get into plank position on the floor',
);

/// The hold evaluation for a body line that is not straight. A direction is
/// only given when there is one to give: sagging or piking is meaningless when
/// leaning on a wall, and "hips up" then "hips down" within seconds of each
/// other (live test #3) is worse than no direction at all.
HoldEvaluation _brokenLine(HipVerdict verdict) {
  switch (verdict) {
    case HipVerdict.sagging:
      return const HoldEvaluation.broken(issue: 'Hips Sagging', cueId: CueIds.hipsSagging);
    case HipVerdict.piked:
      return const HoldEvaluation.broken(issue: 'Hips Piked', cueId: CueIds.hipsPiked);
    case HipVerdict.unjudgeable:
    case HipVerdict.undecided:
      return const HoldEvaluation.broken(issue: 'Body Not Straight', cueId: CueIds.straightBody);
  }
}

/// Hips lifted from the floor: the shoulder-hip-knee angle opens as you rise.
class GluteBridgeAnalyzer extends RangeOfMotionAnalyzer {
  GluteBridgeAnalyzer({super.cueEngine, super.clock});

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
      };

  @override
  double get restAngle => AppConstants.gluteBridgeRestAngle;

  @override
  double get targetAngle => AppConstants.gluteBridgeTopAngle;

  @override
  bool get worksTowardSmallerAngle => false;

  @override
  double get shortRangePenalty => AppConstants.gluteBridgeShortRangePenalty;

  @override
  String get shortRangeIssue => 'Hips Not Fully Extended';

  @override
  String get shortRangeCueId => CueIds.liftHigher;

  @override
  String get workingMessage => 'Drive your hips up';

  @override
  String get returningMessage => 'Lower with control';

  @override
  String get restingMessage => 'Press through your heels and lift';

  @override
  double? measureAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

    final leftVisible = isLandmarkVisible(leftShoulder) &&
        isLandmarkVisible(leftHip) &&
        isLandmarkVisible(leftKnee);
    final rightVisible = isLandmarkVisible(rightShoulder) &&
        isLandmarkVisible(rightHip) &&
        isLandmarkVisible(rightKnee);

    if (!leftVisible && !rightVisible) return null;

    final leftAngle = leftVisible
        ? MathUtils.calculateJointAngle(leftShoulder, leftHip, leftKnee)
        : null;
    final rightAngle = rightVisible
        ? MathUtils.calculateJointAngle(rightShoulder, rightHip, rightKnee)
        : null;

    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;

    // Both hips rise together in a bridge. When both sides are visible, take
    // whichever side is more extended (larger angle) so camera perspective on
    // the far hip doesn't mask a genuine bridge.
    return math.max(leftAngle, rightAngle);
  }

  // No supplementary checks: glute bridge is filmed lying down, side-on
  // (confirmed against real footage -- left/right hip X-coordinates sat
  // ~19px apart out of a >1600px-wide frame, meaning they nearly coincide in
  // the image exactly as a true side view would produce). Every width- or
  // vertical-based check tried here (knee valgus via left/right knee
  // spacing, hip-height asymmetry, foot-placement via shin lean) depends on
  // an assumption that only holds for a front-facing or upright-standing
  // camera angle, and produced nonsensical values on real footage (a
  // shin-lean measurement of ~85 degrees, and a knee-width/hip-width ratio
  // swinging from 0.6 to 64 across one clip). Left at just the one check
  // that's actually valid from this exercise's real filming angle, rather
  // than ship checks proven unreliable.
}

/// Torso curling toward the knees: the same joint closes as you come up.
class SitupAnalyzer extends RangeOfMotionAnalyzer {
  SitupAnalyzer({super.cueEngine, super.clock});

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      };

  @override
  double get restAngle => AppConstants.situpRestAngle;

  @override
  double get targetAngle => AppConstants.situpTopAngle;

  @override
  bool get worksTowardSmallerAngle => true;

  @override
  double get shortRangePenalty => AppConstants.situpShortRangePenalty;

  @override
  String get shortRangeIssue => 'Insufficient Range';

  @override
  String get shortRangeCueId => CueIds.curlHigher;

  @override
  String get workingMessage => 'Curl up';

  @override
  String get returningMessage => 'Lower under control';

  @override
  String get restingMessage => 'Lie back and start the next rep';

  // Filmed lying down, side-on, often with the phone turned on its side: the
  // movement is in the image plane, and ML Kit's depth estimate only adds noise.
  @override
  bool get uses3dAngles => false;

  @override
  double? measureAngle(Pose pose) => bestSideAngle(
        pose,
        isLandmarkVisible,
        const [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
        ],
        const [
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee,
        ],
        angle: jointAngle,
      );

  @override
  Map<String, double> get supplementaryPenalties => const {
        'Uneven Sides': AppConstants.situpAsymmetryPenalty,
        'Straight Legs': AppConstants.situpStraightLegPenalty,
      };

  @override
  void checkFormIssues(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    final leftVisible = isLandmarkVisible(leftShoulder) &&
        isLandmarkVisible(leftHip) &&
        isLandmarkVisible(leftKnee);
    final rightVisible = isLandmarkVisible(rightShoulder) &&
        isLandmarkVisible(rightHip) &&
        isLandmarkVisible(rightKnee);

    if (leftVisible && rightVisible) {
      final leftAngle = MathUtils.calculateJointAngle(leftShoulder, leftHip, leftKnee);
      final rightAngle = MathUtils.calculateJointAngle(rightShoulder, rightHip, rightKnee);
      if ((leftAngle - rightAngle).abs() > AppConstants.situpAsymmetryDegreesThreshold) {
        addIssue('Uneven Sides');
        cues.request(CueIds.asymmetry);
      } else {
        currentRepIssues.remove('Uneven Sides');
      }
    }

    // A proper sit-up keeps the knees bent; straight legs shift the work onto
    // the hip flexors and lower back instead of the abdominals.
    if (leftVisible && isLandmarkVisible(leftAnkle)) {
      final kneeAngle = MathUtils.calculateJointAngle(leftHip, leftKnee, leftAnkle);
      if (kneeAngle > AppConstants.situpKneeStraightAngle) {
        addIssue('Straight Legs');
        cues.request(CueIds.straightenLegs);
      } else {
        currentRepIssues.remove('Straight Legs');
      }
    } else if (rightVisible && isLandmarkVisible(rightAnkle)) {
      final kneeAngle = MathUtils.calculateJointAngle(rightHip, rightKnee, rightAnkle);
      if (kneeAngle > AppConstants.situpKneeStraightAngle) {
        addIssue('Straight Legs');
        cues.request(CueIds.straightenLegs);
      } else {
        currentRepIssues.remove('Straight Legs');
      }
    }
  }
}

/// Arms sweeping out and overhead, measured as abduction at the shoulder.
///
/// The one exercise judged from the front, which also exercises the front-on
/// branch of the orientation check.
class JumpingJackAnalyzer extends RangeOfMotionAnalyzer {
  JumpingJackAnalyzer({super.cueEngine, super.clock});

  @override
  ViewOrientation get requiredOrientation => ViewOrientation.frontOn;

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        // Knees are drawn so the skeleton has legs; a jack is a leg movement
        // too, and floating ankle dots read as a broken overlay.
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      };

  @override
  double get restAngle => AppConstants.jumpingJackRestAngle;

  @override
  double get targetAngle => AppConstants.jumpingJackTopAngle;

  @override
  bool get worksTowardSmallerAngle => false;

  @override
  double get shortRangePenalty => AppConstants.jumpingJackShortRangePenalty;

  @override
  String get shortRangeIssue => 'Arms Not Fully Raised';

  @override
  String get shortRangeCueId => CueIds.raiseArms;

  @override
  String get workingMessage => 'Arms all the way up';

  @override
  String get returningMessage => 'And back down';

  @override
  String get restingMessage => 'Jump and raise your arms';

  @override
  double? measureAngle(Pose pose) => bestSideAngle(
        pose,
        isLandmarkVisible,
        const [
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow,
        ],
        const [
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightElbow,
        ],
      );

  @override
  Map<String, double> get supplementaryPenalties => const {
        'Feet Not Spread': AppConstants.jumpingJackFeetSpreadPenalty,
        'Uneven Arms': AppConstants.jumpingJackAsymmetryPenalty,
      };

  @override
  void checkFormIssues(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    // The analyzer only ever measured arm abduction -- a "jack" that just
    // waves its arms with feet together would still pass. Ankle spread
    // relative to shoulder width catches the half of the movement that was
    // never checked at all. Tracked continuously and retracted once wide
    // enough, same pattern as the depth checks elsewhere: it only needs to
    // happen once during the rep, not be true on every single frame.
    if (isLandmarkVisible(leftShoulder) &&
        isLandmarkVisible(rightShoulder) &&
        isLandmarkVisible(leftAnkle) &&
        isLandmarkVisible(rightAnkle)) {
      final shoulderWidth = (leftShoulder!.x - rightShoulder!.x).abs();
      final ankleWidth = (leftAnkle!.x - rightAnkle!.x).abs();
      if (shoulderWidth > AppConstants.minMagnitude &&
          ankleWidth / shoulderWidth >= AppConstants.jumpingJackFeetSpreadRatio) {
        currentRepIssues.remove('Feet Not Spread');
      } else {
        addIssue('Feet Not Spread');
        cues.request(CueIds.feetNotSpread);
      }
    }

    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftVisible = isLandmarkVisible(leftHip) &&
        isLandmarkVisible(leftShoulder) &&
        isLandmarkVisible(leftElbow);
    final rightVisible = isLandmarkVisible(rightHip) &&
        isLandmarkVisible(rightShoulder) &&
        isLandmarkVisible(rightElbow);
    if (leftVisible && rightVisible) {
      final leftAngle = MathUtils.calculateJointAngle(leftHip, leftShoulder, leftElbow);
      final rightAngle = MathUtils.calculateJointAngle(rightHip, rightShoulder, rightElbow);
      if ((leftAngle - rightAngle).abs() > AppConstants.jumpingJackAsymmetryDegreesThreshold) {
        addIssue('Uneven Arms');
        cues.request(CueIds.asymmetry);
      } else {
        currentRepIssues.remove('Uneven Arms');
      }
    }
  }
}

/// Seated against a wall, holding roughly a right angle at the knee.
class WallSitAnalyzer extends TimedExerciseAnalyzer {
  WallSitAnalyzer({super.cueEngine, super.clock});

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      };

  @override
  String holdingMessage(int seconds) => 'Hold it: ${seconds}s';

  @override
  HoldEvaluation? evaluateHold(Pose pose) {
    final kneeAngle = bestSideAngle(
      pose,
      isLandmarkVisible,
      const [
        PoseLandmarkType.leftHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.leftAnkle,
      ],
      const [
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.rightAnkle,
      ],
    );
    if (kneeAngle == null) return null;

    lastProcessedAngle = kneeAngle;
    updateOrientation(pose);

    if (kneeAngle > AppConstants.wallSitKneeAngleMax) {
      return const HoldEvaluation.broken(issue: 'Not Low Enough', cueId: CueIds.goDeeper);
    }
    if (kneeAngle < AppConstants.wallSitKneeAngleMin) {
      return const HoldEvaluation.broken(issue: 'Too Low', cueId: CueIds.slideUp);
    }

    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
    final leftVisible = isLandmarkVisible(leftHip) &&
        isLandmarkVisible(leftKnee) &&
        isLandmarkVisible(leftAnkle);
    final rightVisible = isLandmarkVisible(rightHip) &&
        isLandmarkVisible(rightKnee) &&
        isLandmarkVisible(rightAnkle);

    // Knee drifting past the toe, same idea and scale-invariant ratio as the
    // lunge check.
    if (leftVisible || rightVisible) {
      final knee = leftVisible ? leftKnee! : rightKnee!;
      final ankle = leftVisible ? leftAnkle! : rightAnkle!;
      final shinLength =
          math.sqrt(math.pow(knee.x - ankle.x, 2) + math.pow(knee.y - ankle.y, 2));
      if (MathUtils.horizontalOffsetRatio(knee, ankle, shinLength) >
          AppConstants.wallSitKneePastToeRatio) {
        return const HoldEvaluation.broken(issue: 'Knee Past Toe', cueId: CueIds.kneePastToe);
      }
    }

    // Leaning more on one leg than the other -- only meaningful front-on,
    // where both knees are genuinely comparable.
    if (leftVisible &&
        rightVisible &&
        orientationTracker.orientation == ViewOrientation.frontOn) {
      final leftAngle = MathUtils.calculateJointAngle(leftHip, leftKnee, leftAnkle);
      final rightAngle = MathUtils.calculateJointAngle(rightHip, rightKnee, rightAnkle);
      if ((leftAngle - rightAngle).abs() > AppConstants.wallSitAsymmetryDegreesThreshold) {
        return const HoldEvaluation.broken(issue: 'Uneven Weight', cueId: CueIds.asymmetry);
      }
    }

    return const HoldEvaluation.good();
  }
}

/// Supported on one forearm, body held in a straight line.
class SidePlankAnalyzer extends TimedExerciseAnalyzer {
  SidePlankAnalyzer({super.cueEngine, super.clock});

  final HipLineJudge _hipLine = HipLineJudge();
  final SettleGate _gate = SettleGate();

  @override
  bool get stopsClockOnLongBreak => false;

  @override
  void reset() {
    super.reset();
    _hipLine.reset();
    _gate.reset();
  }

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      };

  @override
  String holdingMessage(int seconds) => 'Strong line: ${seconds}s';

  @override
  HoldEvaluation? evaluateHold(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    final leftVisible = isLandmarkVisible(leftShoulder) &&
        isLandmarkVisible(leftHip) &&
        isLandmarkVisible(leftAnkle);
    final rightVisible = isLandmarkVisible(rightShoulder) &&
        isLandmarkVisible(rightHip) &&
        isLandmarkVisible(rightAnkle);
    if (!leftVisible && !rightVisible) return null;

    final leftConfidence =
        (leftShoulder?.likelihood ?? 0) + (leftHip?.likelihood ?? 0) + (leftAnkle?.likelihood ?? 0);
    final rightConfidence = (rightShoulder?.likelihood ?? 0) +
        (rightHip?.likelihood ?? 0) +
        (rightAnkle?.likelihood ?? 0);
    final useLeft = leftVisible && (!rightVisible || leftConfidence >= rightConfidence);
    final shoulder = useLeft ? leftShoulder! : rightShoulder!;
    final hip = useLeft ? leftHip! : rightHip!;
    final ankle = useLeft ? leftAnkle! : rightAnkle!;

    final bodyAngle = MathUtils.calculateJointAngle(shoulder, hip, ankle);
    lastProcessedAngle = bodyAngle;

    final flat = !gravityKnown ||
        HipLineJudge.tiltFromHorizontal(shoulder, ankle) <= AppConstants.holdMaxTiltDegrees;
    final settled = _gate.update(flat, now());
    if (!flat) return _notInPlank;
    if (!settled) return _settling;

    final verdict = _hipLine.update(shoulder, hip, ankle, now: now());
    if (bodyAngle <= AppConstants.sidePlankBodyAngleMin) {
      // Same direction logic as Plank: a hip below the shoulder-ankle line is
      // sagging toward the floor, above it is piking upward.
      return _brokenLine(verdict);
    }

    // Supporting elbow drifting out from under the shoulder.
    final elbow = pose.landmarks[useLeft ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow];
    if (isLandmarkVisible(elbow)) {
      final torsoLength =
          math.sqrt(math.pow(shoulder.x - hip.x, 2) + math.pow(shoulder.y - hip.y, 2));
      if (MathUtils.horizontalOffsetRatio(elbow!, shoulder, torsoLength) >
          AppConstants.sidePlankElbowOffsetRatio) {
        return const HoldEvaluation.broken(issue: 'Elbows Not Under Shoulders', cueId: CueIds.elbowsOut);
      }
    }

    // Legs should stay straight and stacked, not bend at the knee.
    final knee = pose.landmarks[useLeft ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee];
    if (isLandmarkVisible(knee)) {
      final legAngle = MathUtils.calculateJointAngle(hip, knee, ankle);
      if (legAngle < AppConstants.sidePlankStraightLegAngleMin) {
        return const HoldEvaluation.broken(issue: 'Bent Knees', cueId: CueIds.straightenLegs);
      }
    }

    return const HoldEvaluation.good();
  }
}

/// Measure a three-point joint angle on whichever side the detector is more
/// confident about, or return null when neither side is usable.
double? bestSideAngle(
  Pose pose,
  bool Function(PoseLandmark?) isVisible,
  List<PoseLandmarkType> left,
  List<PoseLandmarkType> right, {
  double Function(PoseLandmark?, PoseLandmark?, PoseLandmark?) angle =
      MathUtils.calculateJointAngle,
}) {
  double? angleFor(List<PoseLandmarkType> side) {
    final landmarks = side.map((type) => pose.landmarks[type]).toList();
    if (landmarks.any((lm) => !isVisible(lm))) return null;
    return angle(
      landmarks[0],
      landmarks[1],
      landmarks[2],
    );
  }

  double confidenceFor(List<PoseLandmarkType> side) {
    return side.fold<double>(
      0,
      (sum, type) => sum + (pose.landmarks[type]?.likelihood ?? 0),
    );
  }

  final leftAngle = angleFor(left);
  final rightAngle = angleFor(right);

  if (leftAngle == null) return rightAngle;
  if (rightAngle == null) return leftAngle;

  return confidenceFor(left) >= confidenceFor(right) ? leftAngle : rightAngle;
}
