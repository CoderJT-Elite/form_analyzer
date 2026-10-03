# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This repo contains two independent products:
- `app/` — the Flutter mobile app (primary product; see below)
- `web/` — a static landing page (waitlist signup, deployed via GitHub Pages). Root `index.html` is just a redirect to it.

**Note:** this repo is also connected to a Vercel project (`form_analyzer`, auto-deploys on
every push to `main`) that mirrors the same `web/` content — likely a leftover from before
GitHub Pages became the real deploy target, not something actively relied on. Its deployments
are behind Vercel SSO deployment protection with no exempted custom domain, so **never open one
of its `*.vercel.app` URLs in a real browser tool (Claude in Chrome, `navigate`, `computer`)** —
doing so pops a Vercel authentication challenge in whatever browser made the request. If you
need to confirm a `web/` change deployed, check the real GitHub Pages URL instead.

The app is the priority. Marketing/site work is secondary — keep it lightweight and don't let it block app reliability.

## Commands

All app commands run from `app/`:

```bash
flutter pub get       # install dependencies
flutter run            # run on a connected device/emulator
flutter analyze        # static analysis (must pass — enforced in CI)
flutter test           # run all tests
flutter test test/analyzer_test.dart   # run a single test file
flutter test --plain-name "Reset clears all tracking data"  # run one test by name
```

CI (`.github/workflows/flutter_ci.yml`) runs `flutter analyze` and `flutter test` on any PR/push touching `app/`. There is no separate lint step — `flutter analyze` using `analysis_options.yaml` (which includes `package:flutter_lints/flutter.yaml`) is the only gate.

Web changes are checked by `.github/workflows/web_ci.yml`: it fails the build if `PLACEHOLDER_FORM_ID` appears anywhere in `web/`/`index.html`, lints HTML with `htmlhint`, and validates `web/data/beta-count.json` has `total_submissions`, `source: "formspree"`, and `last_updated`. The waitlist form submits to Formspree.

## App architecture

### Pose pipeline (the core of the product)

Camera frames flow through a fixed pipeline:

1. `ExerciseScreen` (`lib/ui/screens/exercise_screen.dart`) owns the `CameraController`, skips every other frame (`_frameSkipInterval`) for performance, and runs setup guidance and a short countdown before analysis starts.
2. `DeviceGravityService` (accelerometer via `sensors_plus`) says which way is down. Each frame is converted to an ML Kit `InputImage` using a **detection rotation that follows the phone's physical orientation** (`logic/gravity_frame.dart`), then run through `PoseDetectorService` (a thin wrapper around `google_mlkit_pose_detection`). The UI is portrait-locked, so the preview is drawn in the sensor's own frame; `PosePainter` maps poses from the detection frame back to it.
3. `PoseValidator` (`logic/pose_validity.dart`) drops detections that are not an athlete (a barbell plate, a face close-up). Survivors are levelled with `normalizePose` so that +y is gravity, which is what every analyzer assumes.
4. The pose is handed to the active exercise's `ExerciseAnalyzer.processPose(pose)` (`lib/logic/exercise_analyzer.dart`), which does all rep-counting and form-scoring. While the phone itself is being moved (`PhoneMotionMonitor`) nothing is fed, and reps counted just before are retracted.
5. The analyzer fires callbacks (`onRep`, `onFeedback`, `onCorrection`, `onSafetyAlert`) that `ExerciseScreen` wires up to TTS (`TTSService`), haptics, and the on-screen status/skeleton overlay (`PosePainter`). Everything spoken goes through `_say`, so the optional `SessionRecorder` can log it.

Reps are judged by **gates, not scores**. Every rep-counted analyzer measures a scale-free signal (hip height as a share of leg length, elbow angle, torso elevation, feet spread in torso lengths...), median-filters it over a few frames, and at the end of each attempt decides one of three things: **counted** (scored 1.0 minus soft penalties), **no-rep** (a serious fault with enough good frames behind it: `recordNoRep`, announced via `onNoRep`, kept in `noRepRecords`) or **ignored** (not an attempt at all: `noteIgnored`, silent). Counts are emitted the moment the athlete is back at the start; there is no plateau wait, rocking or watchdog. Thresholds were read off real footage and live in `core/app_constants.dart` with the numbers they came from.

**Before trusting a live test, read the build line at the bottom of Profile.** Live test #3 was recorded on a stale build. Install with `tools/install_phone.ps1`, which refuses to build from uncommitted code and stamps the APK. Turn on "Record Test Sessions" (tap the build line five times) to capture real poses; `test/support/recorded_session.dart` replays them with their real timing and gravity.

To choose or check a threshold, don't guess: `python tools/dump_rep_metrics.py <fixture>` and `python tools/peaks.py <fixture> <metric>` print the signals from a recorded set, and `flutter test test/tool/dump_replay_test.dart --dart-define=DUMP=live5_squat:squat` replays one through the real analyzer (skipped otherwise). `test/live5_regression_test.dart` pins what each set of live test #5 must do, and `test/strict_gates_test.dart` pins every way a rep can be bad on synthetic poses.

Timing-dependent tests must use a simulated clock (`test/support/test_clock.dart`, `replay_harness.dart`): analyzers judge reps by duration, and a tight loop on the wall clock makes every rep last zero milliseconds.

### Exercise analyzers

`ExerciseAnalyzer` is an abstract base class with a per-exercise state machine (`RepPhase`: neutral/eccentric/concentric). The ten analyzers — `SquatAnalyzer`, `PushupAnalyzer`, `LungeAnalyzer`, `OverheadPressAnalyzer`, `GluteBridgeAnalyzer`, `SitupAnalyzer` (the last two on the `RangeOfMotionAnalyzer` base), `JumpingJackAnalyzer`, and the holds `PlankAnalyzer`, `SidePlankAnalyzer`, `WallSitAnalyzer` (on `TimedExerciseAnalyzer`) — all live in `lib/logic/exercise_analyzer.dart` and follow the same shape:
- Declare `activeLandmarkTypes` (which ML Kit landmarks they need).
- Measure with `logic/body_signals.dart` (`sampleLeg(s)`, `angle2D`, `ScaleWatch`) and filter with `logic/signal_filters.dart` (`MedianFilter`, `AttemptEvidence`, which judges a fault over the share of good frames in a rep, never one frame).
- Open an attempt, track the extreme, count/no-rep/ignore at the return. Per-rep results are `RepRecord`s (`counted`, `noRepReason`, `uncertain`, tempo, range short); `attemptRecords` has counted and rejected attempts in order and is what gets saved.
- Holds count only good-form time: hard faults are forgiven for `holdFaultGrace`, then the clock pauses until the position has been right for `holdResumeClean`; paused seconds are saved as records that did not count. The hip line is one smoothed offset (`logic/hip_line.dart: HipLineMeter`).

`ExerciseAnalyzer` instances are stateful and single-use per workout session — `ExerciseCatalog.exerciseForType()` (`lib/models/exercise_catalog.dart`) always constructs a fresh analyzer rather than reusing one.

All tunable thresholds (joint-angle cutoffs, smoothing alpha, hysteresis, visibility threshold) live in one place: `lib/core/app_constants.dart`. Adjust form-detection behavior there rather than hardcoding numbers in an analyzer.

`MathUtils.calculateAngleFromCoordinates` computes joint angles via vector dot product; it uses full 3D (x/y/z) when landmark Z values look reliable and falls back to 2D (x/y) when Z is flat/unreliable — see `_hasReliableZCoordinates`.

### Persistence

Fully on-device, no backend/network/auth — `StorageService` (`lib/services/storage_service.dart`) wraps `shared_preferences` with JSON-encoded lists under versioned keys (e.g. `workout_sessions_v2`). Malformed persisted entries are skipped individually (`_decodeList`) rather than failing the whole load. Data models with `toJson`/`fromJson` live in `lib/models/exercise_model.dart` (`Exercise`, `ExerciseSet`, `WorkoutSession`, `WorkoutRoutine`, `RoutineSession`).

### Platforms

The Flutter project scaffolds android/ios/linux/macos/web/windows, but **Android/Google Play is the actual launch target**; other platform directories are default `flutter create` scaffolding, not actively maintained targets.

## Product scope

This is an MVP: one core flow (open app → camera-based analysis → track reps/form cues for one of 10 exercises → review history/stats, including per-rep detail). When making changes, prefer maintainability over feature expansion, and keep this one core path solid rather than growing surface area.
