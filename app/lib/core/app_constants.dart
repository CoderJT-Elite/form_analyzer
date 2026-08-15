enum RepPhase { neutral, eccentric, concentric }

enum SquatState { neutral, eccentric, concentric }

class AppConstants {
  // Visibility / confidence
  // Minimum landmark likelihood required before a landmark is used for analysis.
  // 0.7 was chosen from live testing to reduce false positives from partial occlusion while keeping rep detection responsive.
  static const double visibilityThreshold = 0.7;

  // Camera-relative orientation
  // Average body width divided by torso height. In profile the left/right
  // landmark pairs nearly coincide so the ratio collapses; facing the camera it
  // opens up. The gap between the two is deliberately left as 'unknown' rather
  // than forcing a guess at three-quarter angles.
  static const double sideOnMaxWidthRatio = 0.32;
  static const double frontOnMinWidthRatio = 0.50;

  /// Consecutive disagreeing frames before the tracked orientation flips.
  static const int orientationDebounceFrames = 6;

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

  // Squat scoring penalties
  static const double squatRoundedBackPenalty = 0.3;
  static const double squatCriticalBackRoundingPenalty = 0.5;

  static const double pushupDepthThreshold = 90.0;
  static const double pushupNeutralThreshold = 155.0;
  static const double pushupInsufficientDepthPenalty = 0.35;

  // Failing to finish a rep at full extension is a real fault, not just a note.
  static const double incompleteLockoutPenalty = 0.15;

  static const double lungeDepthThreshold = 100.0;
  static const double lungeNeutralThreshold = 160.0;
  static const double lungeInsufficientDepthPenalty = 0.3;

  static const double overheadPressStartThreshold = 100.0;
  static const double overheadPressLockoutThreshold = 165.0;
  static const double overheadPressInsufficientRangePenalty = 0.3;

  // Joint angles come from acos and are therefore unsigned, in [0, 180]. A
  // straight plank measures near 180 and BOTH sagging and piking pull it down,
  // so the angle alone cannot tell them apart — the hip's position relative to
  // the shoulder-knee line supplies the direction.
  static const double plankBackAngleMin = 160.0;

  // Coaching
  /// Lowering faster than this is a drop, not a controlled eccentric.
  static const int minEccentricMillis = 700;

  /// Score above which a rep counts as clean for praise and streaks.
  static const double cleanRepScore = 0.9;

  /// Consecutive clean reps before the athlete gets a bigger compliment.
  static const int praiseStreakLength = 3;

  /// Sustained left/right joint-angle gap that counts as favouring one side.
  /// Generous, because a side-on camera foreshortens the far leg.
  static const double asymmetryDegreesThreshold = 18.0;

  /// Frames of left/right difference averaged before trusting the reading.
  static const int asymmetryWindow = 10;

  // Glute bridge — shoulder/hip/knee opens up as the hips rise.
  static const double gluteBridgeRestAngle = 130.0;
  static const double gluteBridgeTopAngle = 160.0;
  static const double gluteBridgeShortRangePenalty = 0.3;

  // Sit-up — the same joint closes as the torso comes up.
  static const double situpRestAngle = 150.0;
  static const double situpTopAngle = 95.0;
  static const double situpShortRangePenalty = 0.3;

  // Jumping jack — arm abduction measured at the shoulder, seen front-on.
  static const double jumpingJackRestAngle = 45.0;
  static const double jumpingJackTopAngle = 135.0;
  static const double jumpingJackShortRangePenalty = 0.25;

  // Wall sit — knee angle held near a right angle.
  static const double wallSitKneeAngleMin = 70.0;
  static const double wallSitKneeAngleMax = 110.0;

  // Side plank — shoulder/hip/ankle held close to a straight line.
  static const double sidePlankBodyAngleMin = 155.0;

  // Timed holds (plank and friends)
  // A second held with broken form still counts toward duration but scores low.
  static const double timedHoldBrokenFormScore = 0.4;
  // How long form may stay broken before we assume the user has left the
  // position entirely and stop the clock.
  static const int timedHoldBreakGraceSeconds = 3;

  // Backward compatibility aliases
  static const double squatDepthMin = 70;
  static const double squatDepthMax = 95;
  static const double squatStandingAngle = squatNeutralThreshold;
  static const double insufficientDepthAngle = 105;
  static const double minMagnitude = 1e-6;

  // Legal / external links
  static const String privacyPolicyUrl =
      'https://coderjt-elite.github.io/form_analyzer/privacy.html';

  /// Shown on first launch and available from Profile at any time. A fitness
  /// app that tells people how to move under load needs to be explicit that it
  /// is not a medical professional.
  static const String healthDisclaimer =
      'Form Analyzer gives automated feedback from your camera. It is not '
      'medical advice and it is not a substitute for a qualified coach or '
      'healthcare professional.\n\n'
      'Check with a doctor before starting a new exercise programme. Work '
      'within your own ability, make sure you have clear space around you, and '
      'stop immediately if you feel pain, dizziness or discomfort.\n\n'
      'You are responsible for your own safety while training.';

  // UI Constants
  static const double angleLabelPadding = 6.0;
  static const double repCounterScaleBegin = 1.4;
  static const double repCounterScaleEnd = 1.0;
}
