import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as path;

import 'package:form_analyzer/logic/gravity_frame.dart';
import 'package:form_analyzer/logic/pose_normalizer.dart';

import 'pose_fixtures.dart';

/// Loads a `Pose` sequence recorded from real stock footage (see
/// tools/extract_pose_fixtures.py) rather than hand-authored like the rest of
/// pose_fixtures.dart. Used to drive the real analyzers with realistic,
/// noisy human-motion trajectories instead of only idealized angle sweeps.
class RecordedPoseFixtures {
  static const Map<String, PoseLandmarkType> _landmarkTypesByName = {
    'leftShoulder': PoseLandmarkType.leftShoulder,
    'rightShoulder': PoseLandmarkType.rightShoulder,
    'leftElbow': PoseLandmarkType.leftElbow,
    'rightElbow': PoseLandmarkType.rightElbow,
    'leftWrist': PoseLandmarkType.leftWrist,
    'rightWrist': PoseLandmarkType.rightWrist,
    'leftHip': PoseLandmarkType.leftHip,
    'rightHip': PoseLandmarkType.rightHip,
    'leftKnee': PoseLandmarkType.leftKnee,
    'rightKnee': PoseLandmarkType.rightKnee,
    'leftAnkle': PoseLandmarkType.leftAnkle,
    'rightAnkle': PoseLandmarkType.rightAnkle,
  };

  /// Recorded sets in which the phone was lying on its side, and which way
  /// gravity points in those frames (x right, y down).
  ///
  /// These fixtures were extracted from the screen recordings of the live tests,
  /// where the poses are in the phone's own frame. In the app they are levelled
  /// by the accelerometer before an analyzer sees them (see `normalizePose`), so
  /// the tests must do the same or they replay a plank as a body standing up.
  /// In every one of these clips the floor -- the mat the athlete's hands or back
  /// are on -- is at the left edge of the frame, so gravity points left.
  static const Map<String, GravityFrame> gravityByFixture = {
    'live2_plank': GravityFrame(-1, 0),
    'live2_pushup': GravityFrame(-1, 0),
    'live2_situp': GravityFrame(-1, 0),
    'live2_gluteBridge': GravityFrame(-1, 0),
    'live3_plank': GravityFrame(-1, 0),
    'live3_pushupSide': GravityFrame(-1, 0),
    'live3_pushupFloor': GravityFrame(-1, 0),
    'live3_situp': GravityFrame(-1, 0),
    'live3_gluteBridge': GravityFrame(-1, 0),
  };

  /// [assetName] is the JSON file's name under
  /// app/test/fixtures/pose_sequences/ (with or without the .json suffix).
  /// Poses are returned levelled to gravity where the phone was on its side.
  static List<Pose> loadSequence(String assetName) {
    final fileName = assetName.endsWith('.json') ? assetName : '$assetName.json';
    final poses = loadFile(File(path.join(
      Directory.current.path,
      'test',
      'fixtures',
      'pose_sequences',
      fileName,
    )));
    final gravity = gravityByFixture[fileName.replaceAll('.json', '')];
    if (gravity == null) return poses;
    return [for (final p in poses) normalizePose(p, gravity)];
  }

  /// Load a fixture-format file from anywhere, including a `_poses.json`
  /// written by SessionRecorder on a real phone.
  static List<Pose> loadFile(File file) {
    final frames = jsonDecode(file.readAsStringSync()) as List<dynamic>;

    return frames.map((frame) {
      final frameMap = frame as Map<String, dynamic>;
      final landmarks = frameMap.entries.map((entry) {
        final type = _landmarkTypesByName[entry.key];
        if (type == null) {
          throw StateError('Unknown landmark name in fixture: ${entry.key}');
        }
        final data = entry.value as Map<String, dynamic>;
        return PoseFixtures.landmark(
          type,
          (data['x'] as num).toDouble(),
          (data['y'] as num).toDouble(),
          z: (data['z'] as num).toDouble(),
          likelihood: (data['likelihood'] as num).toDouble(),
        );
      }).toList();

      return PoseFixtures.fromLandmarks(landmarks);
    }).toList();
  }
}
