import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path_provider/path_provider.dart';

import '../core/build_info.dart';
import '../logic/gravity_frame.dart';
import 'device_gravity_service.dart';

/// Records what the app actually saw and did during a workout, for diagnosis.
///
/// Live tests 1-3 were analysed from a screen recording of the phone: pose
/// tracking re-run with a different model, no real timestamps, no idea which
/// way the phone was lying, and (for test #3) a build nobody could identify.
/// This captures the real ML Kit poses, their timing, gravity, phone motion and
/// every rep, cue and spoken phrase, so the next test yields exact fixtures.
///
/// Off by default and entirely on-device: nothing is ever sent anywhere. The
/// files are written next to the app's data and shared only when the athlete
/// chooses to (Profile, once developer options are unlocked).
///
/// Two files are written per exercise visit:
///  * `..._poses.json`: a list of frames in exactly the format
///    `RecordedPoseFixtures` already loads (12 joints, x/y/z/likelihood), so a
///    recording can be dropped straight into the test fixtures;
///  * `..._meta.json`: everything else, index-aligned with the poses.
class SessionRecorder {
  SessionRecorder({
    required this.exercise,
    DateTime Function()? clock,
    String? buildLabel,
  })  : _now = clock ?? DateTime.now,
        buildLabel = buildLabel ?? BuildInfo.label {
    _startedAt = _now();
  }

  final String exercise;
  final String buildLabel;
  final DateTime Function() _now;
  late final DateTime _startedAt;

  /// The joints analyzers use; the same set the fixtures carry.
  static const Map<String, PoseLandmarkType> joints = {
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

  final List<Map<String, Map<String, double>>> _poses = [];
  final List<Map<String, Object?>> _frameMeta = [];
  final List<Map<String, Object?>> _events = [];
  int _detectionsSeen = 0;
  bool _saved = false;

  int get frameCount => _poses.length;
  bool get isEmpty => _poses.isEmpty && _events.isEmpty;

  /// Record one detection frame. [pose] is the first pose exactly as ML Kit
  /// reported it (in the detection frame), or null when nobody was found.
  void frame({
    required Pose? pose,
    required bool accepted,
    required InputImageRotation rotation,
    required Size frameSize,
    required String stage,
    GravityEstimate? gravity,
    AccelerometerSample? accel,
    bool phoneMoving = false,
    int? detectMs,
  }) {
    _detectionsSeen++;
    if (pose == null) return;
    final joint = <String, Map<String, double>>{};
    for (final entry in joints.entries) {
      final lm = pose.landmarks[entry.value];
      if (lm == null) continue;
      joint[entry.key] = {
        'x': _round(lm.x),
        'y': _round(lm.y),
        'z': _round(lm.z),
        'likelihood': _round(lm.likelihood, 3),
      };
    }
    if (joint.isEmpty) return;
    _poses.add(joint);
    _frameMeta.add({
      't': _now().difference(_startedAt).inMilliseconds,
      'stage': stage,
      'accepted': accepted,
      'rotation': rotation.rawValue,
      'frameW': frameSize.width.round(),
      'frameH': frameSize.height.round(),
      if (gravity != null) 'gravity': [_round(gravity.residual.x, 3), _round(gravity.residual.y, 3)],
      if (gravity != null) 'quarterTurns': gravity.quarterTurns,
      if (accel != null) 'accel': [_round(accel.x, 2), _round(accel.y, 2), _round(accel.z, 2)],
      if (phoneMoving) 'phoneMoving': true,
      if (detectMs != null) 'detectMs': detectMs,
    });
  }

  /// Record something that happened: a rep, a cue, speech, a phone movement.
  void event(String type, [Map<String, Object?> data = const {}]) {
    _events.add({
      't': _now().difference(_startedAt).inMilliseconds,
      'type': type,
      ...data,
    });
  }

  /// Frames per second the detector actually delivered, or null with too little
  /// data. Half of camera fps by design (every other frame is analysed) minus
  /// whatever detection latency costs.
  double? get analysedFps {
    if (_frameMeta.length < 2) return null;
    final first = _frameMeta.first['t'] as int;
    final last = _frameMeta.last['t'] as int;
    if (last <= first) return null;
    return (_frameMeta.length - 1) * 1000 / (last - first);
  }

  /// Fixture-format frames.
  List<Map<String, Map<String, double>>> poseFrames() => List.unmodifiable(_poses);

  Map<String, Object?> meta({Map<String, Object?> summary = const {}}) => {
        'format': 1,
        'exercise': exercise,
        'build': buildLabel,
        'startedAt': _startedAt.toIso8601String(),
        'durationMs': _now().difference(_startedAt).inMilliseconds,
        'framesWithPose': _poses.length,
        'detectionFrames': _detectionsSeen,
        'analysedFps': analysedFps,
        'summary': summary,
        'frames': _frameMeta,
        'events': _events,
      };

  /// Write the two files into [directory]. Idempotent: a recorder saves once.
  Future<List<File>> save(Directory directory, {Map<String, Object?> summary = const {}}) async {
    if (_saved || isEmpty) return const [];
    _saved = true;
    await directory.create(recursive: true);
    final base = 'session_${_stamp(_startedAt)}_$exercise';
    final poses = File('${directory.path}/${base}_poses.json');
    final metaFile = File('${directory.path}/${base}_meta.json');
    // Serialise both before the first await: the recorder keeps receiving frames
    // while the files are written, and a frame landing between the two writes
    // left meta one entry longer than poses (live test #5, sit-up), which made
    // the pair impossible to replay.
    final posesJson = jsonEncode(_poses);
    final metaJson = jsonEncode(meta(summary: summary));
    await poses.writeAsString(posesJson);
    await metaFile.writeAsString(metaJson);
    return [poses, metaFile];
  }

  /// 20260929_214012, sortable and safe in a filename.
  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static double _round(double v, [int places = 1]) {
    final f = _pow10(places);
    return (v * f).roundToDouble() / f;
  }

  static double _pow10(int n) {
    var r = 1.0;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}

/// Where recordings live, and what to do with them.
class RecordingStore {
  const RecordingStore._();

  static Future<Directory> directory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/recordings');
  }

  /// Recording files, newest first.
  static Future<List<File>> files() async {
    final dir = await directory();
    if (!await dir.exists()) return const [];
    final found = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_poses.json') || f.path.endsWith('_meta.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return found;
  }

  /// The files of the newest [sessions] workouts (a pair each). Twelve covers a
  /// full routine and then some: live test #5 shared only the newest three, so
  /// five of the eight exercises' recordings never left the phone.
  static Future<List<File>> latest({int sessions = 12}) async {
    return (await files()).take(sessions * 2).toList();
  }

  static Future<int> deleteAll() async {
    final all = await files();
    for (final f in all) {
      await f.delete();
    }
    return all.length;
  }
}
