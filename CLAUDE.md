# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This repo contains two independent products:
- `app/` — the Flutter mobile app (primary product; see below)
- `web/` — a static landing page (waitlist signup, deployed via GitHub Pages). Root `index.html` is just a redirect to it.

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

1. `ExerciseScreen` (`lib/ui/screens/exercise_screen.dart`) owns the `CameraController`, skips every other frame (`_frameSkipInterval`) for performance, and runs a short on-screen calibration countdown before analysis starts.
2. Each frame is converted to an ML Kit `InputImage` and run through `PoseDetectorService` (`lib/services/pose_detector_service.dart`), a thin wrapper around `google_mlkit_pose_detection`.
3. The resulting `Pose` is handed to the active exercise's `ExerciseAnalyzer.processPose(pose)` (`lib/logic/exercise_analyzer.dart`), which does all rep-counting and form-scoring.
4. The analyzer fires callbacks (`onRep`, `onFeedback`, `onCorrection`, `onSafetyAlert`) that `ExerciseScreen` wires up to TTS (`TTSService`), haptics, and the on-screen status/skeleton overlay (`PosePainter`).

### Exercise analyzers

`ExerciseAnalyzer` is an abstract base class with a per-exercise state machine (`RepPhase`: neutral/eccentric/concentric, plus a per-exercise state enum like `SquatState` for exercises needing depth tracking). Concrete analyzers — `SquatAnalyzer`, `PushupAnalyzer`, `LungeAnalyzer`, `OverheadPressAnalyzer`, `PlankAnalyzer` — all live in `lib/logic/exercise_analyzer.dart` and follow the same shape:
- Declare `activeLandmarkTypes` (which ML Kit landmarks they need).
- Smooth raw landmark/angle noise via `MovingAverageFilter` / `LandmarkSmoother` / `ExponentialSmoothingFilter` (`lib/utils/math_utils.dart`).
- Drive phase transitions off angle thresholds with a hysteresis dead zone (`AppConstants.hysteresisDeadZoneDegrees`) to avoid flicker at phase boundaries.
- Accumulate `currentRepIssues` per rep, score the rep (1.0 minus penalties), and push into `repScores`/`allRepIssues` on rep completion.

`ExerciseAnalyzer` instances are stateful and single-use per workout session — `ExerciseCatalog.exerciseForType()` (`lib/models/exercise_catalog.dart`) always constructs a fresh analyzer rather than reusing one.

All tunable thresholds (joint-angle cutoffs, smoothing alpha, hysteresis, visibility threshold) live in one place: `lib/core/app_constants.dart`. Adjust form-detection behavior there rather than hardcoding numbers in an analyzer.

`MathUtils.calculateAngleFromCoordinates` computes joint angles via vector dot product; it uses full 3D (x/y/z) when landmark Z values look reliable and falls back to 2D (x/y) when Z is flat/unreliable — see `_hasReliableZCoordinates`.

### Persistence

Fully on-device, no backend/network/auth — `StorageService` (`lib/services/storage_service.dart`) wraps `shared_preferences` with JSON-encoded lists under versioned keys (e.g. `workout_sessions_v2`). Malformed persisted entries are skipped individually (`_decodeList`) rather than failing the whole load. Data models with `toJson`/`fromJson` live in `lib/models/exercise_model.dart` (`Exercise`, `ExerciseSet`, `WorkoutSession`, `WorkoutRoutine`, `RoutineSession`).

### Platforms

The Flutter project scaffolds android/ios/linux/macos/web/windows, but **Android/Google Play is the actual launch target**; other platform directories are default `flutter create` scaffolding, not actively maintained targets.

## Product scope

This is an MVP: one core flow (open app → camera-based analysis → track reps/form cues for one of 5 exercises → review history/stats). When making changes, prefer maintainability over feature expansion, and keep this one core path solid rather than growing surface area.
