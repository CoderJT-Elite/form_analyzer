enum RepPhase { down, up }

enum SquatState { neutral, descending, atDepth, ascending }

class AppConstants {
  // Squat depth thresholds
  static const double squatDepthMin = 70;
  static const double squatDepthMax = 95;
  static const double squatStandingAngle = 155;
  static const double insufficientDepthAngle = 105;
  static const double minMagnitude = 1e-6;

  // UI Constants
  static const double angleLabelPadding = 6.0;
  static const double repCounterScaleBegin = 1.4;
  static const double repCounterScaleEnd = 1.0;
}
