import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:form_analyzer/logic/exercise_analyzer.dart';
import 'package:form_analyzer/logic/gravity_frame.dart';
import 'package:form_analyzer/services/device_gravity_service.dart';
import 'package:form_analyzer/services/session_recorder.dart';

import 'support/pose_fixtures.dart';
import 'support/recorded_pose_fixtures.dart';
import 'support/recorded_session.dart';
import 'support/test_clock.dart';

const frameSize = Size(480, 640);

/// Push-up frames at 15 fps for [reps] reps.
List<double> pushupAngles(int reps) => [
      for (var i = 0; i < 15; i++) 175.0,
      for (var r = 0; r < reps; r++) ...[
        for (var i = 0; i <= 12; i++) 175 - 105 * i / 12,
        for (var i = 0; i <= 12; i++) 70 + 105 * i / 12,
        for (var i = 0; i < 5; i++) 175.0,
      ],
    ];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('recorder_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  SessionRecorder record(ManualClock clock, List<double> angles, {String stage = 'active'}) {
    final r = SessionRecorder(exercise: 'pushup', clock: clock.call, buildLabel: 'test');
    for (final a in angles) {
      clock.advance(const Duration(milliseconds: 66));
      r.frame(
        pose: PoseFixtures.pushup(elbowAngle: a),
        accepted: true,
        rotation: InputImageRotation.rotation270deg,
        frameSize: frameSize,
        stage: stage,
        gravity: DeviceGravity.estimate(ax: 0, ay: 9.81, frontCamera: true, sensorOrientation: 270),
        accel: const AccelerometerSample(0.01, 9.81, 0.3),
      );
    }
    return r;
  }

  test('frames are written in the fixture format, with only the 12 joints', () {
    final clock = ManualClock();
    final r = record(clock, [175, 150, 120]);
    final frames = r.poseFrames();
    expect(frames, hasLength(3));
    expect(frames.first.keys.toSet(), containsAll(SessionRecorder.joints.keys.where((k) => k.startsWith('left') && k != 'leftHip' && k != 'leftKnee' && k != 'leftAnkle')));
    for (final joint in frames.first.values) {
      expect(joint.keys.toSet(), {'x', 'y', 'z', 'likelihood'});
    }
  });

  test('meta is index-aligned with the poses and carries timing and gravity', () {
    final clock = ManualClock();
    final r = record(clock, pushupAngles(1));
    final meta = r.meta();
    final frames = meta['frames'] as List;
    expect(frames, hasLength(r.frameCount));
    expect(meta['build'], 'test');
    expect(meta['exercise'], 'pushup');
    final f0 = frames.first as Map;
    expect(f0['rotation'], 270);
    expect(f0['stage'], 'active');
    expect(f0['gravity'], isNotNull);
    expect(f0['accel'], hasLength(3));
    // Timestamps rise by one frame each.
    expect((frames[1] as Map)['t'] - f0['t'], 66);
  });

  test('it reports the frame rate it actually achieved', () {
    final r = record(ManualClock(), pushupAngles(1));
    expect(r.analysedFps, closeTo(15, 0.5));
  });

  test('frames with no pose are not stored but are counted', () {
    final clock = ManualClock();
    final r = SessionRecorder(exercise: 'squat', clock: clock.call);
    for (var i = 0; i < 5; i++) {
      clock.advance(const Duration(milliseconds: 66));
      r.frame(
        pose: null,
        accepted: false,
        rotation: InputImageRotation.rotation0deg,
        frameSize: frameSize,
        stage: 'setup',
      );
    }
    expect(r.frameCount, 0);
    expect(r.meta()['detectionFrames'], 5);
  });

  test('events are timestamped and keep their data', () {
    final clock = ManualClock();
    final r = SessionRecorder(exercise: 'squat', clock: clock.call);
    clock.advance(const Duration(seconds: 2));
    r.event('rep', {'count': 1});
    r.event('cue', {'text': 'Nice rep'});
    final events = r.meta()['events'] as List;
    expect(events, hasLength(2));
    expect((events.first as Map)['t'], 2000);
    expect((events.first as Map)['count'], 1);
    expect((events.last as Map)['text'], 'Nice rep');
  });

  test('saving writes two files, once, and an empty recorder writes nothing', () async {
    final clock = ManualClock();
    final r = record(clock, pushupAngles(1));
    final files = await r.save(dir, summary: {'reps': 1});
    expect(files, hasLength(2));
    expect(files.first.path, endsWith('_poses.json'));
    expect(files.last.path, endsWith('_meta.json'));
    expect(jsonDecode(files.last.readAsStringSync())['summary'], {'reps': 1});

    expect(await r.save(dir), isEmpty, reason: 'idempotent');

    final empty = SessionRecorder(exercise: 'squat');
    expect(await empty.save(dir), isEmpty);
  });

  test('a saved recording loads with the ordinary fixture loader', () async {
    final clock = ManualClock();
    final r = record(clock, pushupAngles(2));
    final files = await r.save(dir);
    final poses = RecordedPoseFixtures.loadFile(files.first);
    expect(poses, hasLength(r.frameCount));
  });

  test('replaying a recording reproduces the rep count the phone saw', () async {
    final clock = ManualClock();
    final angles = pushupAngles(4);
    final r = record(clock, angles);
    final files = await r.save(dir);

    final run = replayRecording(files.first, files.last, (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, 4);
    expect(run.repTimes, hasLength(4));
  });

  test('frames from setup and the countdown are not replayed into the analyzer', () async {
    final clock = ManualClock();
    final setup = record(clock, pushupAngles(3), stage: 'setup');
    final files = await setup.save(dir);
    final run = replayRecording(files.first, files.last, (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, 0);
  });

  test('a turned phone is levelled from the gravity in the recording', () async {
    final clock = ManualClock();
    final r = SessionRecorder(exercise: 'pushup', clock: clock.call);
    // Rotate every push-up frame 90 degrees, as if the phone lay on its side,
    // and record the matching gravity: replay must still count the reps.
    final g = GravityFrame(-1, 0);
    for (final a in pushupAngles(3)) {
      clock.advance(const Duration(milliseconds: 66));
      final p = PoseFixtures.pushup(elbowAngle: a);
      final turned = PoseFixtures.fromLandmarks([
        for (final lm in p.landmarks.values)
          PoseFixtures.landmark(lm.type, -lm.y, lm.x, likelihood: lm.likelihood),
      ]);
      r.frame(
        pose: turned,
        accepted: true,
        rotation: InputImageRotation.rotation0deg,
        frameSize: frameSize,
        stage: 'active',
        gravity: GravityEstimate(
          quarterTurns: 1,
          detectionRotation: InputImageRotation.rotation0deg,
          residual: g,
        ),
      );
    }
    final files = await r.save(dir);
    final run = replayRecording(files.first, files.last, (c) => PushupAnalyzer(clock: c));
    expect(run.analyzer.repCount, 3);
  });
}
