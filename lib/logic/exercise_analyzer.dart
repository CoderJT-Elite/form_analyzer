import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/app_constants.dart';
import '../utils/math_utils.dart';

abstract class ExerciseAnalyzer {
  int repCount = 0;
  RepPhase phase = RepPhase.up;
  String statusMessage = "Align yourself in frame";
  double? lastProcessedAngle;
  Function(int)? onRep;

  void reset() {
    repCount = 0;
    phase = RepPhase.up;
    statusMessage = "Get ready!";
    lastProcessedAngle = null;
  }

  void processPose(Pose pose);
}

class SquatAnalyzer extends ExerciseAnalyzer {
  final List<double> _angleHistory = [];
  static const int _historyLimit = 3;

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

    final leftConf =
        (pose.landmarks[PoseLandmarkType.leftKnee]?.likelihood ?? 0) +
        (pose.landmarks[PoseLandmarkType.leftAnkle]?.likelihood ?? 0);
    final rightConf =
        (pose.landmarks[PoseLandmarkType.rightKnee]?.likelihood ?? 0) +
        (pose.landmarks[PoseLandmarkType.rightAnkle]?.likelihood ?? 0);

    double currentAngle = (leftConf > rightConf) ? leftKnee : rightKnee;

    _angleHistory.add(currentAngle);
    if (_angleHistory.length > _historyLimit) _angleHistory.removeAt(0);
    currentAngle = _angleHistory.reduce((a, b) => a + b) / _angleHistory.length;
    lastProcessedAngle = currentAngle;

    final backAngle = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.leftKnee],
    );

    final hipsVisible =
        (pose.landmarks[PoseLandmarkType.leftHip]?.likelihood ?? 0) > 0.6 ||
        (pose.landmarks[PoseLandmarkType.rightHip]?.likelihood ?? 0) > 0.6;
    final anklesVisible =
        (pose.landmarks[PoseLandmarkType.leftAnkle]?.likelihood ?? 0) > 0.4 ||
        (pose.landmarks[PoseLandmarkType.rightAnkle]?.likelihood ?? 0) > 0.4;

    if (!hipsVisible || !anklesVisible) {
      statusMessage = "Show full body on camera";
      return;
    }

    if (phase == RepPhase.up) {
      if (currentAngle < AppConstants.squatDepthMax) {
        phase = RepPhase.down;
        statusMessage = "Great depth! Now stand up.";
      } else if (currentAngle < AppConstants.insufficientDepthAngle) {
        statusMessage = "Lower... keep going!";
      } else {
        statusMessage = "Squat down slowly";
      }
    } else {
      if (currentAngle > AppConstants.squatStandingAngle) {
        repCount++;
        phase = RepPhase.up;
        statusMessage = "Good rep! Stand tall.";
        if (onRep != null) onRep!(repCount);

        if (backAngle < 45) {
          statusMessage = "Keep your chest up! Back is too rounded.";
        }
      } else {
        if (backAngle < 40) {
          statusMessage = "Back straight! Look forward.";
        } else {
          statusMessage = "Drive up! Push through your heels.";
        }
      }
    }
  }
}

class PushupAnalyzer extends ExerciseAnalyzer {
  final List<double> _angleHistory = [];
  static const int _historyLimit = 3;

  @override
  void processPose(Pose pose) {
    final leftElbow = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftElbow],
      pose.landmarks[PoseLandmarkType.leftWrist],
    );
    final rightElbow = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.rightShoulder],
      pose.landmarks[PoseLandmarkType.rightElbow],
      pose.landmarks[PoseLandmarkType.rightWrist],
    );

    final leftConf =
        (pose.landmarks[PoseLandmarkType.leftElbow]?.likelihood ?? 0) +
        (pose.landmarks[PoseLandmarkType.leftWrist]?.likelihood ?? 0);
    final rightConf =
        (pose.landmarks[PoseLandmarkType.rightElbow]?.likelihood ?? 0) +
        (pose.landmarks[PoseLandmarkType.rightWrist]?.likelihood ?? 0);

    double currentAngle = (leftConf > rightConf) ? leftElbow : rightElbow;

    _angleHistory.add(currentAngle);
    if (_angleHistory.length > _historyLimit) _angleHistory.removeAt(0);
    currentAngle = _angleHistory.reduce((a, b) => a + b) / _angleHistory.length;
    lastProcessedAngle = currentAngle;

    final shouldersVisible =
        (pose.landmarks[PoseLandmarkType.leftShoulder]?.likelihood ?? 0) >
            0.6 ||
        (pose.landmarks[PoseLandmarkType.rightShoulder]?.likelihood ?? 0) > 0.6;
    final wristsVisible =
        (pose.landmarks[PoseLandmarkType.leftWrist]?.likelihood ?? 0) > 0.6 ||
        (pose.landmarks[PoseLandmarkType.rightWrist]?.likelihood ?? 0) > 0.6;

    if (!shouldersVisible || !wristsVisible) {
      statusMessage = "Show upper body on camera";
      return;
    }

    if (phase == RepPhase.up) {
      if (currentAngle < 90) {
        phase = RepPhase.down;
        statusMessage = "Deep enough! Push back up.";
      } else if (currentAngle < 120) {
        statusMessage = "Lower... chest to floor!";
      } else {
        statusMessage = "Lower your chest slowly";
      }
    } else {
      if (currentAngle > 155) {
        repCount++;
        phase = RepPhase.up;
        statusMessage = "Perfect! Fully extended.";
        if (onRep != null) onRep!(repCount);
      } else {
        statusMessage = "Lock those elbows at the top";
      }
    }
  }
}

class LungeAnalyzer extends ExerciseAnalyzer {
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

    double currentAngle = math.min(leftKnee, rightKnee);
    lastProcessedAngle = currentAngle;

    final hipsVisible =
        (pose.landmarks[PoseLandmarkType.leftHip]?.likelihood ?? 0) > 0.5 ||
        (pose.landmarks[PoseLandmarkType.rightHip]?.likelihood ?? 0) > 0.5;

    if (!hipsVisible) {
      statusMessage = "Keep your lower body visible";
      return;
    }

    if (phase == RepPhase.up) {
      if (currentAngle < 100) {
        phase = RepPhase.down;
        statusMessage = "Good depth! Step back up.";
      } else {
        statusMessage = "Step forward and sink your hips";
      }
    } else {
      if (currentAngle > 160) {
        repCount++;
        phase = RepPhase.up;
        statusMessage = "Great lunge! Switch legs.";
        if (onRep != null) onRep!(repCount);
      } else {
        statusMessage = "Return to neutral standing";
      }
    }
  }
}

class OverheadPressAnalyzer extends ExerciseAnalyzer {
  @override
  void processPose(Pose pose) {
    final leftElbow = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftElbow],
      pose.landmarks[PoseLandmarkType.leftWrist],
    );
    final rightElbow = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.rightShoulder],
      pose.landmarks[PoseLandmarkType.rightElbow],
      pose.landmarks[PoseLandmarkType.rightWrist],
    );

    double currentAngle = (leftElbow + rightElbow) / 2;
    lastProcessedAngle = currentAngle;

    final shouldersVisible =
        (pose.landmarks[PoseLandmarkType.leftShoulder]?.likelihood ?? 0) > 0.6;

    if (!shouldersVisible) {
      statusMessage = "Show your torso and arms";
      return;
    }

    if (phase == RepPhase.up) {
      if (currentAngle < 100) {
        phase = RepPhase.down;
        statusMessage = "Power up! Press to the sky.";
      } else {
        statusMessage = "Lower to shoulder level";
      }
    } else {
      if (currentAngle > 165) {
        repCount++;
        phase = RepPhase.up;
        statusMessage = "Full extension! Rep counted.";
        if (onRep != null) onRep!(repCount);
      } else {
        statusMessage = "Reach higher! Lock elbows.";
      }
    }
  }
}

class PlankAnalyzer extends ExerciseAnalyzer {
  final Stopwatch _timer = Stopwatch();
  bool _isHolding = false;

  @override
  void processPose(Pose pose) {
    final backAngle = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.leftKnee],
    );

    lastProcessedAngle = backAngle;

    final isFormCorrect = backAngle > 160 && backAngle < 195;

    if (isFormCorrect) {
      if (!_isHolding) {
        _timer.start();
        _isHolding = true;
      }
      repCount = _timer.elapsed.inSeconds;
      statusMessage = "Hold tight! Core engaged: ${repCount}s";
    } else {
      if (_isHolding) {
        _timer.stop();
        _isHolding = false;
      }
      if (backAngle <= 160) {
        statusMessage = "Hips too high! Lower them.";
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
