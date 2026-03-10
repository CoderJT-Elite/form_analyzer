import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/app_constants.dart';
import '../utils/math_utils.dart';

abstract class ExerciseAnalyzer {
  int repCount = 0;
  RepPhase phase = RepPhase.up;
  String statusMessage = "Align yourself in frame";
  double? lastProcessedAngle;

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
    // Bilateral Tracking
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

    final leftConf = (pose.landmarks[PoseLandmarkType.leftKnee]?.likelihood ?? 0) +
                     (pose.landmarks[PoseLandmarkType.leftAnkle]?.likelihood ?? 0);
    final rightConf = (pose.landmarks[PoseLandmarkType.rightKnee]?.likelihood ?? 0) +
                      (pose.landmarks[PoseLandmarkType.rightAnkle]?.likelihood ?? 0);

    double currentAngle = (leftConf > rightConf) ? leftKnee : rightKnee;
    
    // Smoothing
    _angleHistory.add(currentAngle);
    if (_angleHistory.length > _historyLimit) _angleHistory.removeAt(0);
    currentAngle = _angleHistory.reduce((a, b) => a + b) / _angleHistory.length;
    lastProcessedAngle = currentAngle;

    // Advanced: Torso Uprightness (Back Angle)
    final backAngle = MathUtils.calculateJointAngle(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.leftKnee],
    );

    // Visibility Check
    final hipsVisible = (pose.landmarks[PoseLandmarkType.leftHip]?.likelihood ?? 0) > 0.6 ||
                        (pose.landmarks[PoseLandmarkType.rightHip]?.likelihood ?? 0) > 0.6;
    final anklesVisible = (pose.landmarks[PoseLandmarkType.leftAnkle]?.likelihood ?? 0) > 0.4 ||
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
        
        // Form Feedback: Back Angle
        if (backAngle < 45) {
          statusMessage = "Keep your chest up!";
        }
      } else {
        statusMessage = "Push up through your heels";
      }
    }
  }
}

class PushupAnalyzer extends ExerciseAnalyzer {
  final List<double> _angleHistory = [];
  static const int _historyLimit = 3;

  @override
  void processPose(Pose pose) {
    // Track elbow angle
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

    final leftConf = (pose.landmarks[PoseLandmarkType.leftElbow]?.likelihood ?? 0) +
                     (pose.landmarks[PoseLandmarkType.leftWrist]?.likelihood ?? 0);
    final rightConf = (pose.landmarks[PoseLandmarkType.rightElbow]?.likelihood ?? 0) +
                      (pose.landmarks[PoseLandmarkType.rightWrist]?.likelihood ?? 0);

    double currentAngle = (leftConf > rightConf) ? leftElbow : rightElbow;

    // Smoothing
    _angleHistory.add(currentAngle);
    if (_angleHistory.length > _historyLimit) _angleHistory.removeAt(0);
    currentAngle = _angleHistory.reduce((a, b) => a + b) / _angleHistory.length;
    lastProcessedAngle = currentAngle;

    // Visibility Check
    final shouldersVisible = (pose.landmarks[PoseLandmarkType.leftShoulder]?.likelihood ?? 0) > 0.6 ||
                             (pose.landmarks[PoseLandmarkType.rightShoulder]?.likelihood ?? 0) > 0.6;
    final wristsVisible = (pose.landmarks[PoseLandmarkType.leftWrist]?.likelihood ?? 0) > 0.6 ||
                          (pose.landmarks[PoseLandmarkType.rightWrist]?.likelihood ?? 0) > 0.6;

    if (!shouldersVisible || !wristsVisible) {
      statusMessage = "Show upper body on camera";
      return;
    }

    // Push-up Logic: Down threshold ~70-90 deg, Up threshold ~160+ deg
    if (phase == RepPhase.up) {
      if (currentAngle < 90) {
        phase = RepPhase.down;
        statusMessage = "Deep enough! Push back up.";
      } else {
        statusMessage = "Lower your chest";
      }
    } else {
      if (currentAngle > 155) {
        repCount++;
        phase = RepPhase.up;
        statusMessage = "Perfect! Keep it going.";
      } else {
        statusMessage = "Lock those elbows";
      }
    }
  }
}
