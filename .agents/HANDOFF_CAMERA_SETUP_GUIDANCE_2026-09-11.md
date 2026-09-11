# Handoff: Pre-Exercise Camera Setup Guidance (2026-09-11)

## Executive Summary
This document records the design, implementation, and verification of the pre-exercise camera setup guidance feature in `form_analyzer` (`app/`).

Before the 3-2-1 countdown begins, the application now actively instructs the athlete how to orient their camera and body relative to the screen. The guidance is dynamically keyed off `widget.exercise.analyzer.requiredOrientation`, speaks the instruction via `TTSService`, renders a high-visibility cyber/fitness startup overlay, and adaptively transitions into the countdown once the athlete's stance is confirmed.

---

## 1. Approach Chosen: Adaptive Auto-Advance with Minimum Window & Fallback Timeout

### Rationale
Two approaches were evaluated:
- **Fixed duration (e.g. 3.0s or 4.0s every time)**: Simpler to implement, but creates needless friction for an experienced athlete who is already standing in the proper orientation before tapping start, while potentially rushing an athlete who needs extra seconds to position their mat or step back.
- **Adaptive detection**: Capitalizes on the fact that raw `Pose` landmarks from Google ML Kit are already arriving through `_poseDetector.processImage` during startup, even while `analyzer.processPose` is gated behind calibration.

### Implementation Architecture
1. **Pose Orientation Tracking**:
   During the setup phase (`_isSettingUpCamera = true`), arriving poses are passed to `_onPoseDuringSetup(pose)` which queries `_orientationTracker.track(pose)`. `OrientationTracker` employs a 6-frame debounce window to resist single-frame sensor noise.
2. **Minimum Guidance Window (`minGuidanceDuration`, default 1500ms)**:
   Even if the athlete is immediately in position, transitioning instantly would produce a jarring "flash-and-vanish" visual artifact and cut off TTS playback mid-syllable. The overlay guarantees at least 1.5 seconds so the spoken audio ("Turn side-on to the camera...") and visual instruction can be registered.
3. **Adaptive Auto-Advance**:
   As soon as both the minimum window has elapsed and the required orientation (`ViewOrientation.sideOn` or `ViewOrientation.frontOn`) is confirmed, the system immediately proceeds to the 3-2-1 countdown.
4. **Fallback Timeout (`maxGuidanceDuration`, default 4000ms)**:
   If the athlete never reaches the desired orientation (or landmark confidence is low), the setup phase gracefully times out after 4.0 seconds and advances to countdown anyway. No athlete is ever trapped or blocked from their workout.
5. **Tap-to-Skip**:
   The entire overlay is wrapped in a `GestureDetector`. Tapping anywhere immediately skips the remaining setup duration and kicks off the 3-2-1 countdown.

---

## 2. Exact Copy Shown and Spoken

Copy was directly unified with the existing in-exercise mid-set correction cues defined in `app/lib/logic/cue_engine.dart` (`CueIds.turnSideOn` and `CueIds.turnFrontOn`). Rather than duplicating literal strings, `CameraSetupCopy` constants were introduced and referenced by `kDefaultCues`:

### Side-On Exercises (Squat, Push-up, Lunge, Overhead Press, Plank, Glute Bridge, Sit-up, Wall Sit, Side Plank)
- **Spoken (TTS)**:
  `"Turn side-on to the camera so I can see your form"`
- **Visual Headline**:
  `"Turn side-on to the camera"`
- **Visual Subtext**:
  `"So I can see your form"`

### Front-On Exercise (Jumping Jack)
- **Spoken (TTS)**:
  `"Face the camera"`
- **Visual Headline**:
  `"Face the camera"`
- **Visual Subtext**:
  `"Turn to face the camera"`

### Overlay Status Badges & Action Hints
- **Pending Status Pill**: `"Adjust your position..."` (Cyber amber accent)
- **Confirmed Status Pill**: `"Position confirmed"` (Emerald green accent)
- **Skip Hint**: `"Tap anywhere to skip"`

---

## 3. Practical Verification Details

### Automated Verification
1. **Full Test Suite (`flutter test`)**:
   - **120 / 120 tests passed**.
   - Includes all 17 real-world stock footage regression tests in `stock_footage_regression_test.dart` (confirming no regression to pose-detection, angle computation, or rep-counting pipelines).
   - Includes 8 targeted tests in `camera_setup_guidance_test.dart`.
   - Includes 2 widget tests in `widget_test.dart`.
2. **Static Analysis (`flutter analyze`)**:
   - Clean run: **0 issues found** across the entire Flutter codebase.

### Physical / Emulator Verification Boundary
- A local Android Virtual Device (AVD) `Pixel_3a_API_33_x86_64` (`emulator-5554`) was booted up via `emulator` CLI and reached `sys.boot_completed = 1`.
- When invoking `flutter run -d emulator-5554`, the build failed during Gradle execution due to a Windows filesystem lock on the Gradle dependency cache (`java.io.IOException: Could not move temporary workspace '.../.gradle/caches/transforms-3/.../workspace' to immutable location`).
- The emulator process was cleanly terminated via `adb emu kill`.
- In strict adherence to project standards ("If it can't, say so plainly and rely on `flutter test` widget tests plus a careful manual read-through of the flow instead — don't claim visual verification you didn't actually do"), visual rendering was verified through headless Flutter widget tests (`ExerciseScreen` rendered with fake camera controllers, pump-timing assertions, orientation simulation, and widget tree inspection) rather than claiming live emulator execution.

---

## 4. Full List of New and Modified Tests

### New Test Suite: `app/test/camera_setup_guidance_test.dart` (8 tests)
1. `CameraSetupCopy: preserves identical copy as CueIds defaults` — Verifies `CameraSetupCopy.sideOnSpoken` and `CameraSetupCopy.frontOnSpoken` match `kDefaultCues[CueIds.turnSideOn]` and `kDefaultCues[CueIds.turnFrontOn]`.
2. `ExerciseScreen: displays side-on setup guidance for SquatAnalyzer` — Verifies headline, subtext, and TTS invocation on startup for a `sideOn` exercise.
3. `ExerciseScreen: displays front-on setup guidance for JumpingJackAnalyzer` — Verifies headline, subtext, and TTS invocation for the `frontOn` exercise.
4. `ExerciseScreen: respects custom analyzer requiredOrientation` — Tests an analyzer overriding `requiredOrientation` to `frontOn` to guarantee behavior is driven strictly by the property rather than exercise name or ID.
5. `ExerciseScreen: adaptive auto-advance progresses when required orientation detected` — Simulates 6 matching orientation frames via `handleTestPose()`, confirms position confirmed state, and verifies progression to countdown after `minGuidanceDuration`.
6. `ExerciseScreen: does not auto-advance early when orientation does not match` — Simulates mismatched orientation frames and asserts that the setup overlay remains visible past `minGuidanceDuration`.
7. `ExerciseScreen: fallback timeout advances after maxGuidanceDuration` — Confirms fallback transition to countdown even with zero poses or non-matching poses after 4.0s.
8. `ExerciseScreen: tap on overlay immediately skips guidance and starts countdown` — Taps overlay at $t=100\text{ ms}$ and asserts immediate jump to countdown "3".

### Modified Test Suite: `app/test/widget_test.dart` (2 new tests added)
1. `ExerciseScreen displays side-on setup guidance for Squat` — Full integration widget pump test verifying initial overlay, TTS invocation, and timer transitions.
2. `ExerciseScreen displays front-on setup guidance for Jumping Jack` — Full integration widget pump test verifying front-on instruction rendering and TTS invocation.

---

## 5. Local Commits & Remote Push Status

- **Commit `d15f7143b9d17b5703dc31930af1760cf665c80c`**:
  `feat(ui): add pre-exercise camera setup guidance keyed off requiredOrientation`
- **Documentation Commit**: Handoff documentation added to `.agents/HANDOFF_CAMERA_SETUP_GUIDANCE_2026-09-11.md`.
- **Remote Push Confirmation**: **Zero commits were pushed to `origin`**. All changes remain strictly on local branch `main`.
