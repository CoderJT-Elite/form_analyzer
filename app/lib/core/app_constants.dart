enum RepPhase { neutral, eccentric, concentric }

enum SquatState { neutral, eccentric, concentric }

class AppConstants {
  // Visibility / confidence
  static const double visibilityThreshold = 0.7;

  // Global movement hysteresis and smoothing
  static const double hysteresisDeadZoneDegrees = 7.0;
  static const double angleDirectionDeltaDegrees = 0.75;
  static const double landmarkSmoothingAlpha = 0.35;
  static const int angleMovingAverageWindow = 5;

  // Exercise thresholds (degrees)
  static const double squatDepthThreshold = 90.0;
  static const double squatNeutralThreshold = 160.0;
  static const double squatBackAngleMin = 160.0;
  static const double squatBackAngleCritical = 145.0;

  static const double deadliftBackAngleMin = 160.0;

  static const double pushupDepthThreshold = 90.0;
  static const double pushupNeutralThreshold = 155.0;

  static const double lungeDepthThreshold = 100.0;
  static const double lungeNeutralThreshold = 160.0;

  static const double overheadPressStartThreshold = 100.0;
  static const double overheadPressLockoutThreshold = 165.0;

  static const double plankBackAngleMin = 160.0;
  static const double plankBackAngleMax = 195.0;

  // Backward compatibility aliases
  static const double squatDepthMin = 70;
  static const double squatDepthMax = 95;
  static const double squatStandingAngle = squatNeutralThreshold;
  static const double insufficientDepthAngle = 105;
  static const double minMagnitude = 1e-6;

  // UI Constants
  static const double angleLabelPadding = 6.0;
  static const double repCounterScaleBegin = 1.4;
  static const double repCounterScaleEnd = 1.0;
}
