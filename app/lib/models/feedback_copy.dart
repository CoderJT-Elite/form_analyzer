/// What to say about a fault after the set: why it matters and how to fix it.
///
/// Every issue label an analyzer can record, and every reason a rep can be turned
/// down, has an entry here for the exercise it belongs to. The summary used to
/// have a fix-it line for about seven of the twenty-odd labels and fell back to
/// "Focus next time: Knees Caving In." for the rest.
library;

import 'exercise_model.dart';

class FeedbackTip {
  const FeedbackTip({required this.why, required this.fix});

  /// One sentence on why the fault matters.
  final String why;

  /// One sentence on what to do about it.
  final String fix;

  /// The two together, as a single line.
  String get line => '$why $fix';
}

class FeedbackCopy {
  const FeedbackCopy._();

  /// The tip for [label] on [type]; never null for a label an analyzer produces.
  static FeedbackTip tip(ExerciseType type, String label) =>
      _byExercise[type]?[label] ?? _shared[label] ?? _fallback(label);

  /// Whether there is a tip written for exactly this exercise and label.
  static bool hasTip(ExerciseType type, String label) =>
      (_byExercise[type]?.containsKey(label) ?? false) || _shared.containsKey(label);

  static FeedbackTip _fallback(String label) => FeedbackTip(
        why: '"$label" came up in this set.',
        fix: 'Slow down and film side-on so the next set can check it properly.',
      );

  /// The labels each exercise can produce, for tests that check coverage.
  static Set<String> labelsFor(ExerciseType type) => {
        ...?_byExercise[type]?.keys,
      };

  /// Spoken at the end of a set when the athlete did well.
  static String praiseFor(ExerciseType type, {required int counted, required int noReps}) {
    if (counted == 0) return '';
    if (noReps == 0) {
      return counted >= 8
          ? 'Strong set. Every ${type.singularName} counted.'
          : 'Clean set. Every ${type.singularName} counted.';
    }
    return '$counted counted, $noReps did not.';
  }

  static const Map<String, FeedbackTip> _shared = {
    'Insufficient Depth': FeedbackTip(
      why: 'Stopping short trains a smaller range than you think.',
      fix: 'Pause for a beat at the bottom before you come back up.',
    ),
    'Not Deep Enough': FeedbackTip(
      why: 'It did not get low enough to count as a rep.',
      fix: 'Go lower on every rep, even if you have to do fewer.',
    ),
    'Incomplete Stand': FeedbackTip(
      why: 'You started the next rep before finishing the last one.',
      fix: 'Stand all the way up (hips and knees straight) before going down again.',
    ),
    'Incomplete Return': FeedbackTip(
      why: 'You started the next rep before coming back to the start.',
      fix: 'Lower all the way down and pause for a beat between reps.',
    ),
    'No Full Lockout': FeedbackTip(
      why: 'Without a full lockout the top of the rep is not trained, and it looks like a half rep.',
      fix: 'Finish every rep with your arms completely straight.',
    ),
    'Hips Sagging': FeedbackTip(
      why: 'Sagging hips load the lower back instead of the abs.',
      fix: 'Squeeze your glutes and tuck your tailbone slightly so your body is one straight line.',
    ),
    'Hips Piked': FeedbackTip(
      why: 'Hips that ride up take the work off your core and shoulders.',
      fix: 'Lower your hips until shoulders, hips and ankles line up.',
    ),
    'Body Not Straight': FeedbackTip(
      why: 'A bent body line spreads the load away from your core.',
      fix: 'Line up your head, hips and heels and brace your abs.',
    ),
    'On The Floor': FeedbackTip(
      why: 'Lying on the floor is not a plank: nothing is holding you up.',
      fix: 'Press your forearms down and lift your hips and knees clear of the floor.',
    ),
    'Elbows Not Under Shoulders': FeedbackTip(
      why: 'Elbows out in front or to the side strain the shoulders.',
      fix: 'Stack each elbow directly under its shoulder.',
    ),
    'Uneven Sides': FeedbackTip(
      why: 'One side is doing more of the work, which builds an imbalance.',
      fix: 'Keep your weight centred and push evenly through both feet.',
    ),
    'Uneven Weight': FeedbackTip(
      why: 'Leaning on one leg lets the other coast.',
      fix: 'Press evenly through both feet.',
    ),
  };

  static const Map<ExerciseType, Map<String, FeedbackTip>> _byExercise = {
    ExerciseType.squat: {
      'Excessive Forward Lean': FeedbackTip(
        why: 'Your chest folded forward, which puts the load on your lower back.',
        fix: 'Keep your chest up and your torso roughly parallel to your shins.',
      ),
      'Chest Collapsed': FeedbackTip(
        why: 'You bent over instead of sitting down: that is a hip hinge, not a squat.',
        fix: 'Sit your hips back and down between your heels and keep your chest tall.',
      ),
      'Knees Caving In': FeedbackTip(
        why: 'Knees that fall inward stress the joint.',
        fix: 'Push your knees out over your toes the whole way down and up.',
      ),
    },
    ExerciseType.pushup: {
      'Knees Down': FeedbackTip(
        why: 'With your knees on the floor it is an easier exercise, not a push-up.',
        fix: 'Lift your knees and hold a straight line from shoulders to ankles.',
      ),
    },
    ExerciseType.lunge: {
      'Torso Lean': FeedbackTip(
        why: 'Leaning forward or back shifts the work off your legs.',
        fix: 'Keep your chest up and drop straight down between your feet.',
      ),
    },
    ExerciseType.overheadPress: {
      'Insufficient Range': FeedbackTip(
        why: 'The bar did not come all the way down to your shoulders.',
        fix: 'Lower the bar to shoulder height on every rep before pressing.',
      ),
      'Not Low Enough': FeedbackTip(
        why: 'The bar did not come down to your shoulders, so it did not count.',
        fix: 'Lower the bar until it touches your shoulders before pressing again.',
      ),
      'Wrist Not Stacked': FeedbackTip(
        why: 'Wrists drifting out from over your elbows waste force and strain the wrists.',
        fix: 'Keep each wrist directly above its elbow, with the bar over your mid-foot.',
      ),
      'Leg Drive': FeedbackTip(
        why: 'Bending your knees to get the bar up makes it a push press.',
        fix: 'Keep your legs still and press with your shoulders and arms only.',
      ),
    },
    ExerciseType.gluteBridge: {
      'Hips Not Fully Extended': FeedbackTip(
        why: 'Stopping short of full hip extension leaves the glutes undertrained.',
        fix: 'Drive through your heels until your shoulders, hips and knees form a straight line.',
      ),
      'Hips Not High Enough': FeedbackTip(
        why: 'The lift was too small to count as a bridge.',
        fix: 'Push your hips up until your body is a straight line from shoulders to knees.',
      ),
    },
    ExerciseType.situp: {
      'Insufficient Range': FeedbackTip(
        why: 'You came up only part of the way, so the abs did a fraction of the work.',
        fix: 'Curl your chest all the way toward your knees before lowering.',
      ),
      'Not High Enough': FeedbackTip(
        why: 'That was a crunch, not a sit-up.',
        fix: 'Sit up until your torso is well off the floor, then lower back down.',
      ),
      'Straight Legs': FeedbackTip(
        why: 'Straight legs shift the work onto your hip flexors and lower back.',
        fix: 'Keep your knees bent and your feet flat.',
      ),
    },
    ExerciseType.jumpingJack: {
      'Feet Not Spread': FeedbackTip(
        why: 'Feet that stay close together cut the leg work and the cardio.',
        fix: 'Jump your feet clearly wider than your shoulders.',
      ),
      'Arms Not Fully Raised': FeedbackTip(
        why: 'Arms that stop at shoulder height shorten the movement.',
        fix: 'Sweep your arms all the way overhead on every jump.',
      ),
      'Arms Not Raised': FeedbackTip(
        why: 'Your arms barely moved, so it was a hop, not a jumping jack.',
        fix: 'Sweep your arms up and overhead as your feet go out.',
      ),
    },
    ExerciseType.plank: {},
    ExerciseType.sidePlank: {
      'Bent Knees': FeedbackTip(
        why: 'Bending your legs shortens the lever and lets your hips drop.',
        fix: 'Stack your feet and keep your legs straight.',
      ),
    },
    ExerciseType.wallSit: {
      'Not Low Enough': FeedbackTip(
        why: 'Above a right angle at the knee the quads are barely working.',
        fix: 'Slide down until your thighs are level with the floor.',
      ),
      'Too Low': FeedbackTip(
        why: 'Sitting below a right angle loads the knees more than the muscles.',
        fix: 'Slide up until your knees are bent to about 90 degrees.',
      ),
      'Knee Past Toe': FeedbackTip(
        why: 'Your feet are too close to the wall, which loads the knees.',
        fix: 'Walk your feet further out so your knees stack over your ankles.',
      ),
    },
  };
}
