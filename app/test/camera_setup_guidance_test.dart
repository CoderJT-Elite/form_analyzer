import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/core/app_constants.dart';
import 'package:form_analyzer/core/app_theme.dart';
import 'package:form_analyzer/logic/cue_engine.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/pose_orientation.dart';
import 'package:form_analyzer/models/exercise_catalog.dart';
import 'package:form_analyzer/models/exercise_model.dart';
import 'package:form_analyzer/services/tts_service.dart';
import 'package:form_analyzer/ui/screens/exercise_screen.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pose_fixtures.dart';

class FakeTTSService extends TTSService {
  final List<String> spoken = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String message) async {
    spoken.add(message);
  }

  @override
  Future<void> stop() async {}
}

/// A dummy analyzer with configurable requiredOrientation for testing
/// that guidance is keyed strictly off requiredOrientation, not exercise name.
class TestOrientationAnalyzer extends ExerciseAnalyzer {
  final ViewOrientation _orientation;

  TestOrientationAnalyzer(this._orientation);

  @override
  ViewOrientation get requiredOrientation => _orientation;

  @override
  Set<PoseLandmarkType> get activeLandmarkTypes => {
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
      };

  @override
  void processPose(Pose pose) {}
}

Future<void> pumpExerciseScreen(
  WidgetTester tester, {
  required Exercise exercise,
  required FakeTTSService tts,
  Duration minGuidanceDuration = const Duration(milliseconds: 1500),
  Duration maxGuidanceDuration = const Duration(milliseconds: 4000),
  Size? imageSize,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: ExerciseScreen(
        exercise: exercise,
        tts: tts,
        skipCameraInitialization: true,
        minGuidanceDuration: minGuidanceDuration,
        maxGuidanceDuration: maxGuidanceDuration,
        imageSizeForTesting: imageSize,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Camera Setup Guidance Copy Consistency', () {
    test('reuses existing cue definitions from CueIds', () {
      final sideOnCue =
          kDefaultCues.firstWhere((c) => c.id == CueIds.turnSideOn);
      final frontOnCue =
          kDefaultCues.firstWhere((c) => c.id == CueIds.turnFrontOn);

      expect(CameraSetupCopy.sideOnSpoken, sideOnCue.phrasings.first);
      expect(CameraSetupCopy.frontOnSpoken, frontOnCue.phrasings.first);
    });

    test('headline and spoken text are provided for both orientations', () {
      expect(CameraSetupCopy.spokenFor(ViewOrientation.sideOn),
          'Turn side-on to the camera so I can see your form');
      expect(CameraSetupCopy.headlineFor(ViewOrientation.sideOn),
          'Turn side-on to the camera');
      expect(CameraSetupCopy.subtextFor(ViewOrientation.sideOn),
          'So I can see your form');

      expect(CameraSetupCopy.spokenFor(ViewOrientation.frontOn),
          'Face the camera');
      expect(CameraSetupCopy.headlineFor(ViewOrientation.frontOn),
          'Face the camera');
      expect(CameraSetupCopy.subtextFor(ViewOrientation.frontOn),
          'Turn to face the camera');
    });
  });

  group('Camera Setup Guidance Widget UI & Speech', () {
    testWidgets(
        'Squat (side-on exercise) displays and speaks side-on instruction',
        (WidgetTester tester) async {
      final tts = FakeTTSService();
      final squatExercise = ExerciseCatalog.exerciseForType(ExerciseType.squat);

      expect(squatExercise.analyzer.requiredOrientation, ViewOrientation.sideOn);

      await pumpExerciseScreen(tester, exercise: squatExercise, tts: tts);

      // Verify header and side-on instruction text are visible on screen
      expect(find.text('CAMERA SETUP'), findsOneWidget);
      expect(find.text('Turn side-on to the camera'), findsOneWidget);
      expect(find.text('So I can see your form'), findsOneWidget);
      expect(find.text('Adjust your position...'), findsOneWidget);
      expect(find.text('Tap anywhere to start countdown'), findsOneWidget);

      // Verify TTS spoke the exact side-on instruction
      expect(tts.spoken,
          contains('Turn side-on to the camera so I can see your form'));
    });

    testWidgets(
        'Jumping Jack (front-on exercise) displays and speaks front-on instruction',
        (WidgetTester tester) async {
      final tts = FakeTTSService();
      final jumpingJackExercise =
          ExerciseCatalog.exerciseForType(ExerciseType.jumpingJack);

      expect(jumpingJackExercise.analyzer.requiredOrientation,
          ViewOrientation.frontOn);

      await pumpExerciseScreen(tester, exercise: jumpingJackExercise, tts: tts);

      // Verify header and front-on instruction text are visible on screen
      expect(find.text('CAMERA SETUP'), findsOneWidget);
      expect(find.text('Face the camera'), findsOneWidget);
      expect(find.text('Turn to face the camera'), findsOneWidget);
      expect(find.text('Adjust your position...'), findsOneWidget);

      // Verify TTS spoke the exact front-on instruction
      expect(tts.spoken, contains('Face the camera'));
    });

    testWidgets(
        'Instruction is keyed off requiredOrientation, not hardcoded exercise name',
        (WidgetTester tester) async {
      final tts = FakeTTSService();

      // Custom exercise with arbitrary name but requiredOrientation = frontOn
      final customFrontExercise = Exercise(
        name: 'Custom Lateral Drill',
        description: 'Testing front orientation',
        instructions: 'Test instructions',
        muscleGroup: 'Full Body',
        difficulty: 'Beginner',
        iconAsset: 'assets/icons/squat.png',
        type: ExerciseType.squat,
        analyzer: TestOrientationAnalyzer(ViewOrientation.frontOn),
      );

      await pumpExerciseScreen(tester,
          exercise: customFrontExercise, tts: tts);

      expect(find.text('Face the camera'), findsOneWidget);
      expect(tts.spoken, contains('Face the camera'));
    });
  });

  group('Adaptive Guidance & Countdown Flow', () {
    testWidgets('Adaptive auto-advance once matching orientation is confirmed',
        (WidgetTester tester) async {
      final tts = FakeTTSService();
      final squatExercise = ExerciseCatalog.exerciseForType(ExerciseType.squat);

      await pumpExerciseScreen(
        tester,
        exercise: squatExercise,
        tts: tts,
        minGuidanceDuration: const Duration(milliseconds: 1000),
        maxGuidanceDuration: const Duration(milliseconds: 4000),
      );

      final state =
          tester.state<ExerciseScreenState>(find.byType(ExerciseScreen));
      expect(state.isSetupGuiding, isTrue);
      expect(state.isOrientationConfirmed, isFalse);

      // Deliver side-on pose frames to satisfy debounce threshold
      final sideOnPose = PoseFixtures.torso(
        shoulderWidth: 20,
        hipWidth: 16,
        torsoHeight: 160,
      );

      for (var i = 0; i < AppConstants.orientationDebounceFrames + 1; i++) {
        state.handleTestPose(sideOnPose);
      }
      await tester.pump();

      // Orientation confirmed indicator should now be displayed
      expect(state.isOrientationConfirmed, isTrue);
      expect(find.text('Position confirmed'), findsOneWidget);

      // Advance past minGuidanceDuration (1000ms)
      await tester.pump(const Duration(milliseconds: 1050));

      // Guidance should have auto-advanced into countdown
      expect(state.isSetupGuiding, isFalse);
      expect(find.text('3'), findsOneWidget);
      expect(tts.spoken, contains('3'));

      // Progress through 3 -> 2 -> 1 -> Go!
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      expect(tts.spoken, contains('2'));

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      expect(tts.spoken, contains('1'));

      await tester.pump(const Duration(seconds: 1));
      expect(state.isCalibrated, isTrue);
      expect(tts.spoken, contains('Go!'));
      expect(find.text('1'), findsNothing);
    });

    testWidgets('Non-matching orientation does not trigger early advance',
        (WidgetTester tester) async {
      final tts = FakeTTSService();
      final squatExercise = ExerciseCatalog.exerciseForType(ExerciseType.squat);

      await pumpExerciseScreen(
        tester,
        exercise: squatExercise,
        tts: tts,
        minGuidanceDuration: const Duration(milliseconds: 1000),
        maxGuidanceDuration: const Duration(milliseconds: 4000),
      );

      final state =
          tester.state<ExerciseScreenState>(find.byType(ExerciseScreen));

      // Deliver front-on poses for a side-on exercise
      final frontOnPose = PoseFixtures.torso(
        shoulderWidth: 120,
        hipWidth: 100,
        torsoHeight: 160,
      );

      for (var i = 0; i < AppConstants.orientationDebounceFrames + 1; i++) {
        state.handleTestPose(frontOnPose);
      }
      await tester.pump();

      expect(state.isOrientationConfirmed, isFalse);
      expect(find.text('Adjust your position...'), findsOneWidget);

      // Pump 1500ms: should NOT have advanced because orientation did not match
      await tester.pump(const Duration(milliseconds: 1500));
      expect(state.isSetupGuiding, isTrue);
      expect(find.text('CAMERA SETUP'), findsOneWidget);

      // Pump to reach maxGuidanceDuration (4000ms fallback timeout)
      await tester.pump(const Duration(milliseconds: 2600));
      expect(state.isSetupGuiding, isFalse);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('Tapping overlay manually advances to countdown immediately',
        (WidgetTester tester) async {
      final tts = FakeTTSService();
      final squatExercise = ExerciseCatalog.exerciseForType(ExerciseType.squat);

      await pumpExerciseScreen(
        tester,
        exercise: squatExercise,
        tts: tts,
        minGuidanceDuration: const Duration(milliseconds: 3000),
        maxGuidanceDuration: const Duration(milliseconds: 8000),
      );

      final state =
          tester.state<ExerciseScreenState>(find.byType(ExerciseScreen));
      expect(state.isSetupGuiding, isTrue);

      // Tap on the overlay
      await tester.tap(find.text('CAMERA SETUP'));
      await tester.pump();

      // Immediately transitions to countdown
      expect(state.isSetupGuiding, isFalse);
      expect(find.text('3'), findsOneWidget);
      expect(tts.spoken, contains('3'));
    });
  });

  group('Framing (in-frame) checks', () {
    testWidgets(
        'a cropped pose (limbs near the frame edge) is told to step back, '
        'not to turn side-on', (WidgetTester tester) async {
      final tts = FakeTTSService();
      final squatExercise = ExerciseCatalog.exerciseForType(ExerciseType.squat);

      await pumpExerciseScreen(
        tester,
        exercise: squatExercise,
        tts: tts,
        imageSize: const Size(1000, 1000),
      );

      // Shoulders pinned near the top edge and ankles near the bottom edge
      // of a 1000x1000 frame -- half of the squat's 8 required landmarks
      // sit within PoseFraming's edge margin, well below the 80% threshold.
      final croppedPose = PoseFixtures.fromLandmarks([
        PoseFixtures.landmark(PoseLandmarkType.leftShoulder, 500, 2),
        PoseFixtures.landmark(PoseLandmarkType.rightShoulder, 500, 2),
        PoseFixtures.landmark(PoseLandmarkType.leftHip, 500, 300),
        PoseFixtures.landmark(PoseLandmarkType.rightHip, 500, 300),
        PoseFixtures.landmark(PoseLandmarkType.leftKnee, 500, 600),
        PoseFixtures.landmark(PoseLandmarkType.rightKnee, 500, 600),
        PoseFixtures.landmark(PoseLandmarkType.leftAnkle, 500, 998),
        PoseFixtures.landmark(PoseLandmarkType.rightAnkle, 500, 998),
      ]);

      final state =
          tester.state<ExerciseScreenState>(find.byType(ExerciseScreen));
      state.handleTestPose(croppedPose);
      await tester.pump();

      expect(state.setupIssue, SetupIssue.notInFrame);
      expect(state.isOrientationConfirmed, isFalse);
      expect(find.text('Step back from the camera'), findsOneWidget);
      expect(find.text('I need to see your whole body'), findsOneWidget);
      expect(tts.spoken, contains('Step back so I can see all of you'));
      // The orientation instruction should NOT be showing -- framing takes
      // priority, and turning side-on wouldn't fix a cropped shot.
      expect(find.text('Turn side-on to the camera'), findsNothing);
    });

    testWidgets(
        'once fully in frame but still misoriented, the orientation copy '
        'takes over from the framing copy', (WidgetTester tester) async {
      final tts = FakeTTSService();
      final squatExercise = ExerciseCatalog.exerciseForType(ExerciseType.squat);

      await pumpExerciseScreen(
        tester,
        exercise: squatExercise,
        tts: tts,
        imageSize: const Size(1000, 1000),
      );

      final croppedPose = PoseFixtures.fromLandmarks([
        PoseFixtures.landmark(PoseLandmarkType.leftShoulder, 500, 2),
        PoseFixtures.landmark(PoseLandmarkType.rightShoulder, 500, 2),
        PoseFixtures.landmark(PoseLandmarkType.leftHip, 500, 300),
        PoseFixtures.landmark(PoseLandmarkType.rightHip, 500, 300),
        PoseFixtures.landmark(PoseLandmarkType.leftKnee, 500, 600),
        PoseFixtures.landmark(PoseLandmarkType.rightKnee, 500, 600),
        PoseFixtures.landmark(PoseLandmarkType.leftAnkle, 500, 998),
        PoseFixtures.landmark(PoseLandmarkType.rightAnkle, 500, 998),
      ]);

      final state =
          tester.state<ExerciseScreenState>(find.byType(ExerciseScreen));
      state.handleTestPose(croppedPose);
      await tester.pump();
      expect(state.setupIssue, SetupIssue.notInFrame);

      // Now comfortably centered and away from every edge (all 8 required
      // landmarks present, unlike PoseFixtures.torso() which only covers
      // shoulders/hips), but facing the camera front-on -- a squat needs
      // side-on. Shoulder/hip spread mirrors PoseFixtures.torso's own
      // (120/100/160) known-frontOn ratio.
      final frontOnCentered = PoseFixtures.fromLandmarks([
        PoseFixtures.landmark(PoseLandmarkType.leftShoulder, 440, 300),
        PoseFixtures.landmark(PoseLandmarkType.rightShoulder, 560, 300),
        PoseFixtures.landmark(PoseLandmarkType.leftHip, 450, 460),
        PoseFixtures.landmark(PoseLandmarkType.rightHip, 550, 460),
        PoseFixtures.landmark(PoseLandmarkType.leftKnee, 450, 620),
        PoseFixtures.landmark(PoseLandmarkType.rightKnee, 550, 620),
        PoseFixtures.landmark(PoseLandmarkType.leftAnkle, 450, 780),
        PoseFixtures.landmark(PoseLandmarkType.rightAnkle, 550, 780),
      ]);
      for (var i = 0; i < AppConstants.orientationDebounceFrames + 1; i++) {
        state.handleTestPose(frontOnCentered);
      }
      await tester.pump();

      expect(state.setupIssue, SetupIssue.wrongOrientation);
      expect(find.text('Turn side-on to the camera'), findsOneWidget);
      expect(find.text('Step back from the camera'), findsNothing);
    });
  });
}
