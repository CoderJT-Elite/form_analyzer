import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/app_constants.dart';
import '../utils/math_utils.dart';

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

abstract class ExerciseAnalyzer {
  int repCount = 0;
  RepPhase phase = RepPhase.neutral;
  String statusMessage = 'Align yourself in frame';
  double? lastProcessedAngle;
  Function(int)? onRep;
  Function(String)? onFeedback;
  Function(String)? onCorrection;
  Function(String)? onSafetyAlert;

  final List<String> currentRepIssues = [];
  final List<List<String>> allRepIssues = [];
  final List<double> repScores = [];

  Set<PoseLandmarkType> get activeLandmarkTypes;

  void reset() {
    repCount = 0;
    phase = RepPhase.neutral;
    statusMessage = 'Get ready!';
    lastProcessedAngle = null;
    currentRepIssues.clear();
    allRepIssues.clear();
    repScores.clear();
  }

  bool isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null && landmark.likelihood >= AppConstants.visibilityThreshold;
  }

  void notifyCorrection(String message) {
    statusMessage = message;
    if (onCorrection != null) onCorrection!(message);
  }

  void notifySafetyAlert(String message) {
    statusMessage = message;
    if (onSafetyAlert != null) onSafetyAlert!(message);
  }

  void processPose(Pose pose);

  PerformanceMetrics getPerformanceMetrics() {
    final Map<String, int> issueCounts = {};
    for (var issues in allRepIssues) {
      for (var issue in issues) {
        issueCounts[issue] = (issueCounts[issue] ?? 0) + 1;
      }
    }

    final sortedIssues = issueCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final commonIssues = sortedIssues.take(3).map((e) => e.key).toList();
    final avgScore = repScores.isEmpty
        ? 0.0
        : (repScores.reduce((a, b) => a + b) / repScores.length) * 5.0;

    return PerformanceMetrics(
      averageFormScore: avgScore,
      commonIssues: commonIssues,
      perfectReps: repScores.where((s) => s > 0.9).length,
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
  SquatState squatState = SquatState.neutral;
  bool _reachedDepth = false;
  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
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
    _angleFilter.reset();
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

    final currentAngle = _angleFilter.add(rawAngle);
    lastProcessedAngle = currentAngle;

    final angleDelta = _prevFilteredAngle == null ? 0.0 : currentAngle - _prevFilteredAngle!;
    _prevFilteredAngle = currentAngle;

    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    if (isLandmarkVisible(leftShoulder)) {
      final shoulderSmooth = _smooth(leftShoulder!, 'leftShoulder');
      final backAngle = MathUtils.calculateAngleFromSmoothed(
        shoulderSmooth,
        leftHipSmooth,
        leftKneeSmooth,
      );

      if (backAngle < AppConstants.squatBackAngleCritical) {
        addIssue('Critical Back Rounding');
        notifySafetyAlert('Back Straight');
      } else if (backAngle < AppConstants.squatBackAngleMin) {
        addIssue('Rounded Back');
        notifyCorrection('Back Straight');
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
          _reachedDepth = false;
          statusMessage = 'Lower with control';
        } else {
          statusMessage = 'Squat down slowly';
        }
        break;

      case SquatState.eccentric:
        phase = RepPhase.eccentric;

        if (currentAngle <= AppConstants.squatDepthThreshold) {
          _reachedDepth = true;
        }

        if (_reachedDepth && angleDelta > directionDelta) {
          squatState = SquatState.concentric;
          phase = RepPhase.concentric;
          statusMessage = 'Drive up';
        } else if (!_reachedDepth && angleDelta > directionDelta) {
          notifyCorrection('Lower');
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

            repScores.add(score.clamp(0.0, 1.0));
            allRepIssues.add(List.from(currentRepIssues));
            currentRepIssues.clear();

            statusMessage = 'Rep $repCount';
            if (onRep != null) onRep!(repCount);
          } else {
            notifyCorrection('Lower');
            if (onFeedback != null) onFeedback!('Go deeper next time');
          }

          _reachedDepth = false;
        } else {
          statusMessage = 'Stand tall';
        }
        break;
    }
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
  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevAngle;

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

    final leftConf = (leftElbow?.likelihood ?? 0) + (leftWrist?.likelihood ?? 0);
    final rightConf = (rightElbow?.likelihood ?? 0) + (rightWrist?.likelihood ?? 0);

    final rawAngle = leftConf >= rightConf ? leftAngle : rightAngle;
    final currentAngle = _angleFilter.add(rawAngle);
    final delta = _prevAngle == null ? 0.0 : currentAngle - _prevAngle!;
    _prevAngle = currentAngle;
    lastProcessedAngle = currentAngle;

    final deadZone = AppConstants.hysteresisDeadZoneDegrees;

    switch (phase) {
      case RepPhase.neutral:
        if (currentAngle < AppConstants.pushupNeutralThreshold - deadZone) {
          phase = RepPhase.eccentric;
          statusMessage = 'Lower your chest';
        } else {
          statusMessage = 'Lower with control';
        }
        break;

      case RepPhase.eccentric:
        if (currentAngle <= AppConstants.pushupDepthThreshold) {
          phase = RepPhase.concentric;
          statusMessage = 'Push up';
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            currentAngle > AppConstants.pushupDepthThreshold + deadZone) {
          notifyCorrection('Lower');
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        if (currentAngle >= AppConstants.pushupNeutralThreshold) {
          repCount++;
          phase = RepPhase.neutral;
          statusMessage = 'Rep $repCount';
          if (onRep != null) onRep!(repCount);
        } else {
          statusMessage = 'Lock elbows at top';
        }
        break;
    }
  }
}

class LungeAnalyzer extends ExerciseAnalyzer {
  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevAngle;

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
          statusMessage = 'Lower into lunge';
        } else {
          statusMessage = 'Step forward and lower';
        }
        break;

      case RepPhase.eccentric:
        if (currentAngle <= AppConstants.lungeDepthThreshold) {
          phase = RepPhase.concentric;
          statusMessage = 'Drive up';
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            currentAngle > AppConstants.lungeDepthThreshold + deadZone) {
          notifyCorrection('Lower');
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        if (currentAngle >= AppConstants.lungeNeutralThreshold) {
          repCount++;
          phase = RepPhase.neutral;
          statusMessage = 'Rep $repCount';
          if (onRep != null) onRep!(repCount);
        } else {
          statusMessage = 'Return to neutral standing';
        }
        break;
    }
  }
}

class OverheadPressAnalyzer extends ExerciseAnalyzer {
  final MovingAverageFilter _angleFilter =
      MovingAverageFilter(windowSize: AppConstants.angleMovingAverageWindow);
  double? _prevAngle;

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

    final leftLikelihoodSum = (leftElbowLandmark?.likelihood ?? 0) + (leftWristLandmark?.likelihood ?? 0);
    final rightLikelihoodSum = (rightElbowLandmark?.likelihood ?? 0) + (rightWristLandmark?.likelihood ?? 0);
    final rawAngle = leftLikelihoodSum >= rightLikelihoodSum ? leftElbow : rightElbow;

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
          statusMessage = 'Lower to shoulder level';
        } else {
          statusMessage = 'Lower under control';
        }
        break;

      case RepPhase.eccentric:
        if (currentAngle <= AppConstants.overheadPressStartThreshold) {
          phase = RepPhase.concentric;
          statusMessage = 'Press up';
        } else if (delta > AppConstants.angleDirectionDeltaDegrees &&
            currentAngle > AppConstants.overheadPressStartThreshold + deadZone) {
          notifyCorrection('Lower');
        } else {
          statusMessage = 'Lower';
        }
        break;

      case RepPhase.concentric:
        if (currentAngle >= AppConstants.overheadPressLockoutThreshold) {
          repCount++;
          phase = RepPhase.neutral;
          statusMessage = 'Rep $repCount';
          if (onRep != null) onRep!(repCount);
        } else {
          statusMessage = 'Reach higher';
        }
        break;
    }
  }
}

class PlankAnalyzer extends ExerciseAnalyzer {
  final Stopwatch _timer = Stopwatch();
  bool _isHolding = false;

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
  void processPose(Pose pose) {
    final keyVisible =
        isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftShoulder]) &&
            isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftHip]) &&
            isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftKnee]);
    if (!keyVisible) {
      statusMessage = 'Adjust Camera';
      return;
    }

    final backAngle = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.leftKnee],
    );

    lastProcessedAngle = backAngle;

    final isFormCorrect = backAngle > AppConstants.plankBackAngleMin &&
        backAngle < AppConstants.plankBackAngleMax;

    if (isFormCorrect) {
      if (!_isHolding) {
        _timer.start();
        _isHolding = true;
      }
      repCount = _timer.elapsed.inSeconds;
      statusMessage = 'Hold tight! Core engaged: ${repCount}s';
    } else {
      if (_isHolding) {
        _timer.stop();
        _isHolding = false;
      }
      if (backAngle <= AppConstants.plankBackAngleMin) {
        statusMessage = 'Hips too high! Lower them.';
      } else {
        statusMessage = "Don't sag! Hips up.";
      }
    }
  }

  @override
  void reset() {
    super.reset();
    _timer.reset();
    _isHolding = false;
  }
}
