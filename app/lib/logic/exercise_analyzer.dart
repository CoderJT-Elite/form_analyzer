import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/app_constants.dart';
import '../utils/math_utils.dart';
import 'cue_engine.dart';
import 'pose_orientation.dart';

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

  final List<String> currentRepIssues = [];
  final List<RepRecord> repRecords = [];

  DateTime? _eccentricStartedAt;
  DateTime? _concentricStartedAt;
  int _cleanRepStreak = 0;

  /// Derived views kept for the UI and for stored session summaries.
  List<double> get repScores =>
      repRecords.map((record) => record.score).toList(growable: false);

  List<List<String>> get allRepIssues =>
      repRecords.map((record) => record.issues).toList(growable: false);

  Set<PoseLandmarkType> get activeLandmarkTypes;

  /// The camera view this exercise's form checks are written for.
  ViewOrientation get requiredOrientation => ViewOrientation.sideOn;

  void reset() {
    repCount = 0;
    phase = RepPhase.neutral;
    statusMessage = 'Get ready!';
    lastProcessedAngle = null;
    currentRepIssues.clear();
    repRecords.clear();
    cues.reset();
    orientationTracker.reset();
    _eccentricStartedAt = null;
    _concentricStartedAt = null;
    _cleanRepStreak = 0;
  }

  bool isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null && landmark.likelihood >= AppConstants.visibilityThreshold;
  }

  /// Route a cleared cue to the right callback and to the on-screen status.
  void _dispatchCue(Cue cue) {
    statusMessage = cue.message;
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
    if (observed == requiredOrientation) return true;
    if (observed == ViewOrientation.unknown) return false;

    cues.request(
      requiredOrientation == ViewOrientation.sideOn
          ? CueIds.turnSideOn
          : CueIds.turnFrontOn,
    );
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

  PerformanceMetrics getPerformanceMetrics() {
    final Map<String, int> issueCounts = {};
    for (var record in repRecords) {
      for (var issue in record.issues) {
        issueCounts[issue] = (issueCounts[issue] ?? 0) + 1;
      }
    }

    final sortedIssues = issueCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final commonIssues = sortedIssues.take(3).map((e) => e.key).toList();
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
  }

  @override
  void processPose(Pose pose) {
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    final required = [leftHip, leftKnee, leftAnkle, rightHip, rightKnee, rightAnkle];
    if (required.any((lm) => !isLandmarkVisible(lm))) {
      statusMessage = 'Adjust Camera';
      return;
    }

    final leftHipSmooth = _smooth(leftHip!, 'leftHip');
    final leftKneeSmooth = _smooth(leftKnee!, 'leftKnee');
    final leftAnkleSmooth = _smooth(leftAnkle!, 'leftAnkle');

    final rightHipSmooth = _smooth(rightHip!, 'rightHip');
    final rightKneeSmooth = _smooth(rightKnee!, 'rightKnee');
    final rightAnkleSmooth = _smooth(rightAnkle!, 'rightAnkle');

    final leftAngle = MathUtils.calculateAngleFromSmoothed(
      leftHipSmooth,
      leftKneeSmooth,
      leftAnkleSmooth,
    );
    final rightAngle = MathUtils.calculateAngleFromSmoothed(
      rightHipSmooth,
      rightKneeSmooth,
      rightAnkleSmooth,
    );

    final leftConfidence = leftKneeSmooth.likelihood + leftAnkleSmooth.likelihood;
    final rightConfidence = rightKneeSmooth.likelihood + rightAnkleSmooth.likelihood;
    final rawAngle = leftConfidence >= rightConfidence ? leftAngle : rightAngle;

    // Both sides are computed anyway; comparing them is free and catches an
    // athlete loading one leg harder than the other. Only trusted when the
    // view is front-on, since a side view foreshortens the far leg and would
    // report a difference that isn't there.
    final asymmetry = _asymmetryFilter.add((leftAngle - rightAngle).abs());
    if (orientationTracker.orientation == ViewOrientation.frontOn &&
        _asymmetryFilter.isFull &&
        asymmetry > AppConstants.asymmetryDegreesThreshold &&
        squatState != SquatState.neutral) {
      addIssue('Uneven Sides');
      cues.request(CueIds.asymmetry);
    }

    final currentAngle = _angleFilter.add(rawAngle);
    lastProcessedAngle = currentAngle;

    final angleDelta = _prevFilteredAngle == null ? 0.0 : currentAngle - _prevFilteredAngle!;
    _prevFilteredAngle = currentAngle;

    // The back-angle check measures shoulder-hip-knee on one side of the body.
    // That is only meaningful from a side view: head-on, those three points are
    // near-collinear in the image whatever the spine is doing, so the check
    // would report a healthy angle and never warn. Gate it on a confirmed side
    // view and ask the athlete to turn instead of quietly passing them.
    final hasSideView = updateOrientation(pose);

    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    if (hasSideView && isLandmarkVisible(leftShoulder)) {
      final shoulderSmooth = _smooth(leftShoulder!, 'leftShoulder');
      final backAngle = MathUtils.calculateAngleFromSmoothed(
        shoulderSmooth,
        leftHipSmooth,
        leftKneeSmooth,
      );

      if (backAngle < AppConstants.squatBackAngleCritical) {
        addIssue('Critical Back Rounding');
        cues.request(CueIds.criticalBackRounding);
      } else if (backAngle < AppConstants.squatBackAngleMin) {
        addIssue('Rounded Back');
        cues.request(CueIds.backRounding);
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
          _deepestAngle = currentAngle;
          markEccentricStart();
          statusMessage = 'Lower with control';
        } else {
          statusMessage = 'Squat down slowly';
        }
        break;

      case SquatState.eccentric:
        phase = RepPhase.eccentric;
        _deepestAngle = math.min(_deepestAngle, currentAngle);

        if (currentAngle <= AppConstants.squatDepthThreshold) {
          _reachedDepth = true;
        }

        if (_reachedDepth && angleDelta > directionDelta) {
          squatState = SquatState.concentric;
          phase = RepPhase.concentric;
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
          cues.request(CueIds.goDeeper, detail: _depthShortfall(currentAngle));
        } else {
          statusMessage = _reachedDepth ? 'Great depth, stand up' : 'Lower';
        }
        break;

      case SquatState.concentric:
        phase = RepPhase.concentric;

        if (currentAngle >= AppConstants.squatNeutralThreshold) {
          squatState = SquatState.neutral;
          phase = RepPhase.neutral;

          if (_reachedDepth) {
            repCount++;
            double score = 1.0;
            if (currentRepIssues.contains('Rounded Back')) {
              score -= AppConstants.squatRoundedBackPenalty;
            }
            if (currentRepIssues.contains('Critical Back Rounding')) {
              score -= AppConstants.squatCriticalBackRoundingPenalty;
            }

            statusMessage = 'Rep $repCount';
            recordRep(score: score, peakAngle: _deepestAngle);
            if (onRep != null) onRep!(repCount);
          }

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

  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevAngle;
  bool _reachedDepth = false;
  double _concentricPeak = 0;
  double _deepestAngle = 180;

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
    _reachedDepth = false;
    _concentricPeak = 0;
    _deepestAngle = 180;
  }

  @override
  void processPose(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    if (!isLandmarkVisible(leftElbow) && !isLandmarkVisible(rightElbow)) {
      statusMessage = 'Adjust Camera';
      return;
    }

    final leftAngle = MathUtils.calculateJointAngle(leftShoulder, leftElbow, leftWrist);
    final rightAngle =
        MathUtils.calculateJointAngle(rightShoulder, rightElbow, rightWrist);

    final leftConfidence = (leftElbow?.likelihood ?? 0) + (leftWrist?.likelihood ?? 0);
    final rightConfidence = (rightElbow?.likelihood ?? 0) + (rightWrist?.likelihood ?? 0);

    final rawAngle = leftConfidence >= rightConfidence ? leftAngle : rightAngle;
    final currentAngle = _angleFilter.add(rawAngle);
    final delta = _prevAngle == null ? 0.0 : currentAngle - _prevAngle!;
    _prevAngle = currentAngle;
    lastProcessedAngle = currentAngle;

    final deadZone = AppConstants.hysteresisDeadZoneDegrees;

    switch (phase) {
      case RepPhase.neutral:
        if (currentAngle < AppConstants.pushupNeutralThreshold - deadZone) {
          phase = RepPhase.eccentric;
          currentRepIssues.clear();
          _reachedDepth = false;
          _deepestAngle = currentAngle;
          markEccentricStart();
          statusMessage = 'Lower your chest';
        } else {
          statusMessage = 'Lower with control';
        }
        break;

      case RepPhase.eccentric:
        _deepestAngle = math.min(_deepestAngle, currentAngle);

        if (currentAngle <= AppConstants.pushupDepthThreshold) {
          _reachedDepth = true;
        }

        if (_reachedDepth && delta > AppConstants.angleDirectionDeltaDegrees) {
          // Wait for an actual upward reversal, not merely touching depth —
          // otherwise the remainder of the descent is read as a failed ascent.
          phase = RepPhase.concentric;
          _concentricPeak = currentAngle;
          markConcentricStart();
          statusMessage = 'Push up';
        } else if (!_reachedDepth &&
            currentAngle >= AppConstants.pushupNeutralThreshold) {
          // Came back up without reaching depth; return to neutral instead of
          // staying stuck in eccentric forever.
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(CueIds.goDeeper);
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            currentAngle > AppConstants.pushupDepthThreshold + deadZone) {
          addIssue('Insufficient Depth');
          cues.request(CueIds.goDeeper);
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        if (currentAngle >= AppConstants.pushupNeutralThreshold) {
          repCount++;
          double score = 1.0;
          if (!_reachedDepth || currentRepIssues.contains('Insufficient Depth')) {
            addIssue('Insufficient Depth');
            score -= AppConstants.pushupInsufficientDepthPenalty;
          }
          if (currentRepIssues.contains('Incomplete Lockout')) {
            score -= AppConstants.incompleteLockoutPenalty;
          }
          statusMessage = 'Rep $repCount';
          recordRep(
            score: score,
            peakAngle: _deepestAngle,
            romDeficitDegrees: math.max(
              0,
              _deepestAngle - AppConstants.pushupDepthThreshold,
            ),
          );
          _reachedDepth = false;
          _concentricPeak = 0;
          _deepestAngle = 180;
          phase = RepPhase.neutral;
          if (onRep != null) onRep!(repCount);
        } else {
          // Being mid-ascent is not a fault. An incomplete lockout is sinking
          // back down from the highest point reached without ever locking out.
          _concentricPeak = math.max(_concentricPeak, currentAngle);
          if (currentAngle < _concentricPeak - deadZone) {
            addIssue('Incomplete Lockout');
            cues.request(CueIds.lockOut);
          }
          statusMessage = 'Lock elbows at top';
        }
        break;
    }
  }
}

class LungeAnalyzer extends ExerciseAnalyzer {
  LungeAnalyzer({super.cueEngine, super.clock});

  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevAngle;
  bool _reachedDepth = false;
  double _deepestAngle = 180;

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
  void reset() {
    super.reset();
    _angleFilter.reset();
    _prevAngle = null;
    _reachedDepth = false;
    _deepestAngle = 180;
  }

  @override
  void processPose(Pose pose) {
    final leftKnee = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.leftKnee],
      pose.landmarks[PoseLandmarkType.leftAnkle],
    );
    final rightKnee = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.rightHip],
      pose.landmarks[PoseLandmarkType.rightKnee],
      pose.landmarks[PoseLandmarkType.rightAnkle],
    );

    final currentAngle = _angleFilter.add(math.min(leftKnee, rightKnee));
    final delta = _prevAngle == null ? 0.0 : currentAngle - _prevAngle!;
    _prevAngle = currentAngle;
    lastProcessedAngle = currentAngle;

    final hipsVisible =
        isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftHip]) ||
            isLandmarkVisible(pose.landmarks[PoseLandmarkType.rightHip]);

    if (!hipsVisible) {
      statusMessage = 'Adjust Camera';
      return;
    }

    final deadZone = AppConstants.hysteresisDeadZoneDegrees;

    switch (phase) {
      case RepPhase.neutral:
        if (currentAngle < AppConstants.lungeNeutralThreshold - deadZone) {
          phase = RepPhase.eccentric;
          currentRepIssues.clear();
          _reachedDepth = false;
          _deepestAngle = currentAngle;
          markEccentricStart();
          statusMessage = 'Lower into lunge';
        } else {
          statusMessage = 'Step forward and lower';
        }
        break;

      case RepPhase.eccentric:
        _deepestAngle = math.min(_deepestAngle, currentAngle);

        if (currentAngle <= AppConstants.lungeDepthThreshold) {
          _reachedDepth = true;
        }

        if (_reachedDepth && delta > AppConstants.angleDirectionDeltaDegrees) {
          phase = RepPhase.concentric;
          markConcentricStart();
          statusMessage = 'Drive up';
        } else if (!_reachedDepth &&
            currentAngle >= AppConstants.lungeNeutralThreshold) {
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(CueIds.goDeeper);
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            currentAngle > AppConstants.lungeDepthThreshold + deadZone) {
          addIssue('Insufficient Depth');
          cues.request(CueIds.goDeeper);
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        if (currentAngle >= AppConstants.lungeNeutralThreshold) {
          repCount++;
          double score = 1.0;
          if (!_reachedDepth || currentRepIssues.contains('Insufficient Depth')) {
            addIssue('Insufficient Depth');
            score -= AppConstants.lungeInsufficientDepthPenalty;
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
  }

  @override
  void processPose(Pose pose) {
    final leftElbowLandmark = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWristLandmark = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightElbowLandmark = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWristLandmark = pose.landmarks[PoseLandmarkType.rightWrist];

    final leftElbow = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      leftElbowLandmark,
      leftWristLandmark,
    );
    final rightElbow = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.rightShoulder],
      rightElbowLandmark,
      rightWristLandmark,
    );

    final leftConfidence = (leftElbowLandmark?.likelihood ?? 0) + (leftWristLandmark?.likelihood ?? 0);
    final rightConfidence = (rightElbowLandmark?.likelihood ?? 0) + (rightWristLandmark?.likelihood ?? 0);
    final rawAngle = leftConfidence >= rightConfidence ? leftElbow : rightElbow;

    final currentAngle = _angleFilter.add(rawAngle);
    final delta = _prevAngle == null ? 0.0 : currentAngle - _prevAngle!;
    _prevAngle = currentAngle;
    lastProcessedAngle = currentAngle;

    final shouldersVisible =
        isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftShoulder]) ||
            isLandmarkVisible(pose.landmarks[PoseLandmarkType.rightShoulder]);

    if (!shouldersVisible) {
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
          _deepestAngle = currentAngle;
          markEccentricStart();
          statusMessage = 'Lower to shoulder level';
        } else {
          statusMessage = 'Lower under control';
        }
        break;

      case RepPhase.eccentric:
        _deepestAngle = math.min(_deepestAngle, currentAngle);

        if (currentAngle <= AppConstants.overheadPressStartThreshold) {
          _reachedBottom = true;
        }

        if (_reachedBottom && delta > AppConstants.angleDirectionDeltaDegrees) {
          phase = RepPhase.concentric;
          _concentricPeak = currentAngle;
          markConcentricStart();
          statusMessage = 'Press up';
        } else if (!_reachedBottom &&
            currentAngle >= AppConstants.overheadPressLockoutThreshold) {
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(CueIds.fullRange);
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            currentAngle > AppConstants.overheadPressStartThreshold + deadZone) {
          addIssue('Insufficient Range');
          cues.request(CueIds.fullRange);
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        if (currentAngle >= AppConstants.overheadPressLockoutThreshold) {
          repCount++;
          double score = 1.0;
          if (!_reachedBottom || currentRepIssues.contains('Insufficient Range')) {
            addIssue('Insufficient Range');
            score -= AppConstants.overheadPressInsufficientRangePenalty;
          }
          if (currentRepIssues.contains('No Full Lockout')) {
            score -= AppConstants.incompleteLockoutPenalty;
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
          markEccentricStart();
          statusMessage = workingMessage;
        } else {
          statusMessage = restingMessage;
        }

      case RepPhase.eccentric:
        _bestProgress = math.max(_bestProgress, progress);

        if (progress >= targetProgress) {
          _reachedTarget = true;
        }

        if (_reachedTarget && delta < -directionDelta) {
          // Only once the athlete has genuinely reversed.
          phase = RepPhase.concentric;
          markConcentricStart();
          statusMessage = returningMessage;
        } else if (!_reachedTarget && progress <= restProgress) {
          // Back to the start without completing the range — return to neutral
          // rather than stalling here forever.
          phase = RepPhase.neutral;
          currentRepIssues.clear();
          cues.request(shortRangeCueId);
        } else if (!_reachedTarget && delta < -directionDelta) {
          addIssue(shortRangeIssue);
          cues.request(shortRangeCueId);
        } else {
          statusMessage = workingMessage;
        }

      case RepPhase.concentric:
        if (progress <= restProgress) {
          repCount++;

          var score = 1.0;
          if (!_reachedTarget || currentRepIssues.contains(shortRangeIssue)) {
            addIssue(shortRangeIssue);
            score -= shortRangePenalty;
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

  const HoldEvaluation.good()
      : isCorrect = true,
        cueId = '',
        issue = '';

  const HoldEvaluation.broken({required this.cueId, required this.issue})
      : isCorrect = false;
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

  final Stopwatch _timer = Stopwatch();
  int _lastScoredSecond = 0;
  int? _brokenSinceMs;

  /// Judge the current frame. Return null when the required landmarks aren't
  /// visible, which pauses the clock rather than counting bad time.
  HoldEvaluation? evaluateHold(Pose pose);

  /// Status line shown while the hold is going well.
  String holdingMessage(int seconds);

  int get heldSeconds => _timer.elapsed.inSeconds;

  @override
  void processPose(Pose pose) {
    final evaluation = evaluateHold(pose);

    if (evaluation == null) {
      _timer.stop();
      _brokenSinceMs = null;
      statusMessage = 'Adjust Camera';
      return;
    }

    if (evaluation.isCorrect) {
      _brokenSinceMs = null;
      if (!_timer.isRunning) _timer.start();
      _accrue(1.0);
      statusMessage = holdingMessage(heldSeconds);
      return;
    }

    // Form is broken but the user is still in position, so the clock keeps
    // running — a sagging plank is still time under tension. If it stays broken
    // long enough we assume they've stood up and stop counting.
    final elapsedMs = _timer.elapsed.inMilliseconds;
    _brokenSinceMs ??= elapsedMs;
    final brokenForMs = elapsedMs - _brokenSinceMs!;
    if (brokenForMs >= AppConstants.timedHoldBreakGraceSeconds * 1000) {
      _timer.stop();
    }

    addIssue(evaluation.issue);
    _accrue(AppConstants.timedHoldBrokenFormScore);
    cues.request(evaluation.cueId);
  }

  /// Credit whole seconds that have elapsed since the last check, scoring each
  /// with the quality that applied when it ticked over.
  void _accrue(double secondScore) {
    final seconds = _timer.elapsed.inSeconds;
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
    _timer
      ..stop()
      ..reset();
    _lastScoredSecond = 0;
    _brokenSinceMs = null;
  }
}

class PlankAnalyzer extends TimedExerciseAnalyzer {
  PlankAnalyzer({super.cueEngine, super.clock});

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
  String holdingMessage(int seconds) => 'Hold tight! Core engaged: ${seconds}s';

  @override
  HoldEvaluation? evaluateHold(Pose pose) {
    final shoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final hip = pose.landmarks[PoseLandmarkType.leftHip];
    final knee = pose.landmarks[PoseLandmarkType.leftKnee];

    if (!isLandmarkVisible(shoulder) ||
        !isLandmarkVisible(hip) ||
        !isLandmarkVisible(knee)) {
      return null;
    }

    final backAngle = MathUtils.calculateJointAngle(shoulder, hip, knee);
    lastProcessedAngle = backAngle;

    if (backAngle > AppConstants.plankBackAngleMin) {
      return const HoldEvaluation.good();
    }

    // Image y grows downward, so a hip below the shoulder-knee midline is a
    // sag and a hip above it is a pike. This works regardless of which way the
    // athlete is facing.
    final midlineY = (shoulder!.y + knee!.y) / 2;
    final isSagging = hip!.y > midlineY;

    return HoldEvaluation.broken(
      issue: isSagging ? 'Hips Sagging' : 'Hips Piked',
      cueId: isSagging ? CueIds.hipsSagging : CueIds.hipsPiked,
    );
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
  String get shortRangeCueId => CueIds.fullRange;

  @override
  String get workingMessage => 'Drive your hips up';

  @override
  String get returningMessage => 'Lower with control';

  @override
  String get restingMessage => 'Press through your heels and lift';

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
      );
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
  String get workingMessage => 'Curl up';

  @override
  String get returningMessage => 'Lower under control';

  @override
  String get restingMessage => 'Lie back and start the next rep';

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
      );
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
  String get shortRangeCueId => CueIds.fullRange;

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

    if (kneeAngle >= AppConstants.wallSitKneeAngleMin &&
        kneeAngle <= AppConstants.wallSitKneeAngleMax) {
      return const HoldEvaluation.good();
    }

    // Above the window they are standing too tall; below it they have slid
    // down past a right angle.
    return kneeAngle > AppConstants.wallSitKneeAngleMax
        ? const HoldEvaluation.broken(
            issue: 'Not Low Enough',
            cueId: CueIds.goDeeper,
          )
        : const HoldEvaluation.broken(
            issue: 'Too Low',
            cueId: CueIds.fullRange,
          );
  }
}

/// Supported on one forearm, body held in a straight line.
class SidePlankAnalyzer extends TimedExerciseAnalyzer {
  SidePlankAnalyzer({super.cueEngine, super.clock});

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      };

  @override
  String holdingMessage(int seconds) => 'Strong line: ${seconds}s';

  @override
  HoldEvaluation? evaluateHold(Pose pose) {
    final bodyAngle = bestSideAngle(
      pose,
      isLandmarkVisible,
      const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.leftAnkle,
      ],
      const [
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightAnkle,
      ],
    );
    if (bodyAngle == null) return null;

    lastProcessedAngle = bodyAngle;

    if (bodyAngle >= AppConstants.sidePlankBodyAngleMin) {
      return const HoldEvaluation.good();
    }

    return const HoldEvaluation.broken(
      issue: 'Hips Sagging',
      cueId: CueIds.hipsSagging,
    );
  }
}

/// Measure a three-point joint angle on whichever side the detector is more
/// confident about, or return null when neither side is usable.
double? bestSideAngle(
  Pose pose,
  bool Function(PoseLandmark?) isVisible,
  List<PoseLandmarkType> left,
  List<PoseLandmarkType> right,
) {
  double? angleFor(List<PoseLandmarkType> side) {
    final landmarks = side.map((type) => pose.landmarks[type]).toList();
    if (landmarks.any((lm) => !isVisible(lm))) return null;
    return MathUtils.calculateJointAngle(
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
