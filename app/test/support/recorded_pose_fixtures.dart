import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as path;

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

  /// [assetName] is the JSON file's name under
  /// app/test/fixtures/pose_sequences/ (with or without the .json suffix).
  static List<Pose> loadSequence(String assetName) {
    final fileName = assetName.endsWith('.json') ? assetName : '$assetName.json';
    final file = File(path.join(
      Directory.current.path,
      'test',
      'fixtures',
      'pose_sequences',
      fileName,
    ));
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
