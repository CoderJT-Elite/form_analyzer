# Handoff: Pose & Rep-Counting Pipeline Stress Test Across All 10 Exercises (2026-09-10)

## Executive Summary
This document summarizes the end-to-end stress testing, hardening, and verification of the camera-based pose-detection and rep-counting/form-scoring pipeline in `form_analyzer` across all 10 supported exercises:
1. `SquatAnalyzer`
2. `PushupAnalyzer`
3. `LungeAnalyzer`
4. `OverheadPressAnalyzer`
5. `PlankAnalyzer`
6. `GluteBridgeAnalyzer`
7. `SitupAnalyzer`
8. `JumpingJackAnalyzer`
9. `WallSitAnalyzer`
10. `SidePlankAnalyzer`

### Verification Summary
- **Tests**: 110/110 tests passing (`flutter test` clean across entire test suite, including 17 real-stock-footage integration test cases in `stock_footage_regression_test.dart`).
- **Static Analysis**: `flutter analyze` completed with **0 issues found**.
- **Local Commits**: 3 clean local commits made on `main`. **Zero commits pushed to remote**.

---

## 1. Footage Gathering Matrix
A total of **26 real-world video clips** were harvested from Pexels and Pixabay, downloaded at original quality, and extracted at full source framerate with full 3D landmark depth ($X, Y, Z$) preserved via MediaPipe Pose (matching the production coordinate system).

| Exercise | Source Footage ID | Frames | FPS | View Orientation | Pace / Movement Style | Quality / Form Characteristics |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Squat** | `squat_pexels_8837221` | 388 | 30.0 | Side-on (profile) | Normal tempo | Deep squats (44°-70° knee angle) |
| **Squat** | `squat_pexels_4764175` | 300 | 25.0 | Front-on | Normal tempo | Deep squat, orientation test ("turn side-on") |
| **Squat** | `squat_pixabay_148204` | 344 | 29.97 | Side-on | Controlled tempo | Full range bodyweight squats |
| **Push-up** | `pushup_pexels_4367576` | 338 | 25.0 | 3/4 Profile | Controlled tempo | 4 clean full-depth reps |
| **Push-up** | `pushup_pixabay_302251` | 321 | 29.97 | Side-on | Fast/explosive | 1 clean rep (78° elbow dip, 165° lockout) |
| **Push-up** | `pushup_pixabay_143431` | 300 | 29.97 | Side-on | Normal tempo | Full range push-up |
| **Push-up** | `pushup_pixabay_58984` | 185 | 29.97 | 3/4 Side-on | Normal tempo | Close-grip push-up |
| **Lunge** | `lunge_pexels_8171292` | 277 | 25.0 | Side-on (left profile) | Pulsing / stationary | Stationary split lunge; rear leg remains flexed |
| **Lunge** | `lunge_pexels_4488004` | 329 | 30.0 | Side-on (profile) | Alternating | Walking/alternating lunges, switching lead legs |
| **Overhead Press** | `overheadPress_pexels_4367541` | 715 | 30.0 | Side-on (profile) | Normal tempo | 5 barbell overhead presses, lockout 152°-165° |
| **Overhead Press** | `overheadPress_pexels_32239223` | 675 | 30.0 | 3/4 Front | Controlled tempo | Incomplete lockout; arms top out at 144° |
| **Plank** | `plank_pexels_6525477` | 232 | 30.0 | Right profile | Static hold | Right side facing camera; slight pike (158°) |
| **Plank** | `plank_pexels_7117437` | 575 | 30.0 | Side-on (profile) | Static hold | Prone forearm plank with form fluctuations |
| **Plank** | `plank_pexels_4945589` | 1022 | 30.0 | Side-on | Extended hold | Long duration endurance hold |
| **Glute Bridge** | `gluteBridge_pexels_6525487` | 167 | 25.0 | Side-on (profile) | Controlled tempo | 2 completed bridges, top hip angle 153° |
| **Glute Bridge** | `gluteBridge_pexels_4267359` | 438 | 29.97 | Right side-on | Normal tempo | 6 reps; near side 168°, far side foreshortened |
| **Sit-up** | `situp_pixabay_293079` | 771 | 25.0 | Side-on (profile) | Controlled tempo | 4 bent-knee sit-ups, floor resting angle ~132° |
| **Sit-up** | `situp_pixabay_296446` | 441 | 25.0 | Side-on (profile) | Normal tempo | 2 bent-knee sit-ups, floor resting angle ~135° |
| **Situp** | `situp_pixabay_84706` | 249 | 25.0 | Side-on (profile) | Fast tempo | 1 full sit-up with quick return |
| **Jumping Jack** | `jumpingJack_pixabay_292741` | 628 | 30.0 | Front-on | Normal tempo | 7 clean full overhead jumping jacks |
| **Jumping Jack** | `jumpingJack_pixabay_84375` | 381 | 25.0 | Front-on | Rapid / rhythmic | Continuous jumping jacks; bottom angle 50°-55° |
| **Wall Sit** | `wallSit_pexels_6454275` | 240 | 30.0 | Side-on (profile) | Static hold | Wall sit at ~90° knee angle |
| **Wall Sit** | `wallSit_pexels_6326797` | 534 | 25.0 | 3/4 Profile | Static hold | Wall sit hold |
| **Wall Sit** | `wallSit_pexels_8402078` | 270 | 25.0 | Side-on | Static hold | Wall sit hold |
| **Side Plank** | `sidePlank_pexels_6023264` | 255 | 25.0 | Profile | Static hold | Forearm side plank hold |
| **Side Plank** | `sidePlank_pexels_6023265` | 237 | 25.0 | Profile | Static hold | Forearm side plank hold |

---

## 2. Confirmed Issues & Root Causes

### Issue 1: `LungeAnalyzer` Deadlocked in Concentric Phase on Stationary/Split Lunges
- **Exercise**: Lunges (`LungeAnalyzer`)
- **Clips**: `lunge_pexels_8171292` (277 frames) and `lunge_pexels_4488004` (329 frames).
- **Behavior Before Fix**:
  - `repCount = 0` for both clips. State machine remained stuck in `RepPhase.concentric` ("Return to neutral standing") after the first descent. All subsequent reps were missed.
- **Root Cause** (`app/lib/logic/exercise_analyzer.dart:726`):
  - `final currentAngle = _angleFilter.add(math.min(leftKnee, rightKnee));`
  - In a lunge, the rear/trailing leg stays flexed near the ground (measured between 90° and 121° throughout the clip). Taking `math.min(leftKnee, rightKnee)` locked `currentAngle` below 121.7° at all times.
  - Recovery to standing (`RepPhase.concentric`) required `currentAngle >= AppConstants.lungeNeutralThreshold` (160.0°). Because `currentAngle` could never exceed 121.7°, the analyzer could never transition back to `neutral` to complete any rep.
- **Fix Applied**:
  1. `AppConstants.lungeNeutralThreshold` adjusted from `160.0` to `155.0` (standard upright lockout without joint hyperextension).
  2. In `LungeAnalyzer.processPose`:
     - Both knees' visibility is evaluated with bilateral fallback.
     - Unsmoothed depth is checked via `depthAngle = math.min(leftKnee, rightKnee)`.
     - Standing recovery tracks the extending/supporting leg via `standingAngle = math.max(leftKnee, rightKnee)`.
     - `_reachedDepth` clears any transient `Insufficient Depth` warning.
- **Verified Result**: `lunge_pexels_8171292` and `lunge_pexels_4488004` both detect 3 clean reps with score 1.0.

---

### Issue 2: `SitupAnalyzer` Anatomically Impossible Floor Rest Angle Threshold
- **Exercise**: Sit-ups (`SitupAnalyzer`)
- **Clips**: `situp_pixabay_293079` (771 frames), `situp_pixabay_296446` (441 frames), `situp_pixabay_84706` (249 frames).
- **Behavior Before Fix**:
  - `repCount = 0` across all 3 clips. Athletes curled up deeply (peak angles 29°-55°), but the analyzer remained stuck in `RepPhase.concentric` ("Lower under control").
- **Root Cause** (`app/lib/core/app_constants.dart:84`, `app/lib/logic/exercise_analyzer.dart:1083`):
  - `situpRestAngle = 150.0`. The measured joint is `Shoulder-Hip-Knee`.
  - In standard bent-knee sit-ups, when lying flat on the floor with knees bent at ~90°, the torso-femur angle is only ~125°-135°. Achieving 150° while keeping knees bent would require hyperextending the hips off the floor.
  - Because `progress <= -150.0` was never satisfied, rep completion in `RangeOfMotionAnalyzer` was never triggered.
- **Fix Applied**:
  - `AppConstants.situpRestAngle` updated from `150.0` to `130.0` in `app_constants.dart`.
- **Verified Result**:
  - `situp_pixabay_293079`: 4 reps detected.
  - `situp_pixabay_296446`: 2 clean reps detected.
  - `situp_pixabay_84706`: 1 clean rep detected.

---

### Issue 3: `GluteBridgeAnalyzer` Target Angle Too High for Safe Form & Far-Side Distortion
- **Exercise**: Glute Bridge (`GluteBridgeAnalyzer`)
- **Clips**: `gluteBridge_pexels_6525487` (167 frames), `gluteBridge_pexels_4267359` (438 frames).
- **Behavior Before Fix**:
  - `repCount = 0` for both clips.
- **Root Cause** (`app/lib/core/app_constants.dart:79-80`, `app/lib/logic/exercise_analyzer.dart:1355`):
  - `gluteBridgeTopAngle = 160.0`. A straight diagonal line from knees through hips to shoulders in a safe glute bridge measures ~145°-153°. Requiring 160° demands excessive lumbar hyperextension.
  - In `6525487`, clean bridges peaked at 152.9° and 152.4°, so `_reachedTarget` remained false. When the athlete lowered back down, line 1070 (`else if (!_reachedTarget && progress <= restProgress)`) discarded the rep as incomplete.
  - In `4267359`, `bestSideAngle` selected the distorted far-side hip (max 137.0°) over the visible near-side hip (reaching 168.5°).
- **Fix Applied**:
  1. `AppConstants.gluteBridgeTopAngle` updated from `160.0` to `150.0`, and `gluteBridgeRestAngle` updated to `138.0`.
  2. In `GluteBridgeAnalyzer.measureAngle`, when both sides are visible, take `math.max(leftAngle, rightAngle)` so perspective on the far hip does not mask genuine extension.
- **Verified Result**:
  - `gluteBridge_pexels_6525487`: 2 clean reps detected.
  - `gluteBridge_pexels_4267359`: 6 clean reps detected (score 1.0).

---

### Issue 4: `OverheadPressAnalyzer` Lockout Threshold Hyperextension & False Negative Penalties
- **Exercise**: Overhead Press (`OverheadPressAnalyzer`)
- **Clips**: `overheadPress_pexels_4367541` (715 frames), `overheadPress_pexels_32239223` (675 frames).
- **Behavior Before Fix**:
  - In `4367541` (5 full barbell presses), only rep 1 was counted; reps 2-5 were dropped and the state machine was stuck in `concentric` ("Reach higher").
  - In addition, rep 1 was falsely penalized with `No Full Lockout` (score 0.85).
- **Root Cause** (`app/lib/core/app_constants.dart:52`, `app/lib/logic/exercise_analyzer.dart:911, 948`):
  - `overheadPressLockoutThreshold = 165.0`. Standard overhead lockout avoids hyperextension under heavy load (~152°-158°). Perspective foreshortens the elbow angle. Reps 2-5 reached 152.4°-156.3°, missing 165.0°.
  - Transient frame-to-frame deceleration during descent added `Insufficient Range`, which was never cleared even when full bottom range was reached.
  - Jitter during concentric ascent added `No Full Lockout`, which was never cleared even when full lockout was reached.
- **Fix Applied**:
  1. `AppConstants.overheadPressLockoutThreshold` updated from `165.0` to `152.0`.
  2. In `OverheadPressAnalyzer.processPose`:
     - When `currentAngle <= AppConstants.overheadPressStartThreshold`, clear `Insufficient Range`.
     - When `currentAngle >= AppConstants.overheadPressLockoutThreshold`, clear `No Full Lockout`.
- **Verified Result**:
  - `overheadPress_pexels_4367541`: all 5 reps counted cleanly with score 1.0 (no false penalties).
  - `overheadPress_pexels_32239223`: correctly rejects incomplete lockout (< 145°) and prompts "Reach higher".

---

### Issue 5: `PushupAnalyzer` Sticky Descent & Lockout Tremor Penalties
- **Exercise**: Push-ups (`PushupAnalyzer`)
- **Clips**: `pushup_pixabay_302251`, `pushup_pixabay_143431`, `pushup_pixabay_58984`.
- **Behavior Before Fix**:
  - Athletes performing deep push-ups (78° elbow angle, well past the 90° threshold) and locking out cleanly to 165° received score 0.50 with both `Insufficient Depth` and `Incomplete Lockout` flagged.
- **Root Cause** (`app/lib/logic/exercise_analyzer.dart:638, 675`):
  - Any 1-frame deceleration on the way down triggered `addIssue('Insufficient Depth')`. Line 618 (`_reachedDepth = true`) never removed it.
  - Any 1-frame tremor during ascent triggered `addIssue('Incomplete Lockout')`. Reaching `currentAngle >= pushupNeutralThreshold` never cleared it.
- **Fix Applied**:
  - When `currentAngle <= AppConstants.pushupDepthThreshold`, `currentRepIssues.remove('Insufficient Depth')`.
  - When `currentAngle >= AppConstants.pushupNeutralThreshold`, `currentRepIssues.remove('Incomplete Lockout')`.
- **Verified Result**: `pushup_pixabay_302251`, `143431`, `58984` all receive score 1.0 with 0 false penalties.

---

### Issue 6: `PlankAnalyzer` Hardcoded Unilateral Landmark Check
- **Exercise**: Plank (`PlankAnalyzer`)
- **Clips**: `plank_pexels_6525477` (232 frames), `plank_pexels_7117437` (575 frames).
- **Behavior Before Fix**:
  - In `6525477`, the athlete faces the camera with their right side. The analyzer output was 100% "Adjust Camera".
- **Root Cause** (`app/lib/logic/exercise_analyzer.dart:1240-1248`):
  - `PlankAnalyzer.evaluateHold` hardcoded checks for `leftShoulder`, `leftHip`, `leftKnee` only. If an athlete faces right, the left limbs are occluded and `evaluateHold` returned `null` every frame.
- **Fix Applied**:
  - Implemented bilateral check in `PlankAnalyzer.evaluateHold`: tests both `left` and `right` sides, selecting the visible side (or higher-confidence side when both are visible).
- **Verified Result**: `plank_pexels_6525477` successfully evaluates form (accurately detecting hip pike / high hips) and tracks hold time.

---

### Issue 7: `TimedExerciseAnalyzer` Clock Decoupling & Untestability
- **Exercise**: Plank, Wall Sit, Side Plank (`TimedExerciseAnalyzer`)
- **Clips**: All timed fixtures (`plank_pexels_6525477`, `wallSit_pexels_6454275`, `sidePlank_pexels_6023264`, `sidePlank_pexels_6023265`).
- **Behavior Before Fix**:
  - In automated tests or offline playback, `heldSeconds` and `repCount` were always 0 because CPU processing of frames finishes in milliseconds.
- **Root Cause** (`app/lib/logic/exercise_analyzer.dart:1139`):
  - `final Stopwatch _timer = Stopwatch();`. It bypassed the injected `now()` clock from `ExerciseAnalyzer(clock: ...)` and relied on system wall-clock time.
- **Fix Applied**:
  - Replaced internal `Stopwatch` with timestamps driven by `now()`: tracks `_accumulatedHeldMs`, `_lastFrameTime`, `_brokenSince`, and `_lastScoredSecond`.
  - In production, defaults to `DateTime.now`. In tests, respects simulated or stepped clock time.
- **Verified Result**: `wallSit_pexels_6454275` (7s held) and `sidePlank_pexels_6023264` (5s held) accurately record held seconds and fire `onRep`.

---

### Issue 8: `JumpingJackAnalyzer` Bottom Arm Abduction Threshold in Continuous Jumps
- **Exercise**: Jumping Jacks (`JumpingJackAnalyzer`)
- **Clips**: `jumpingJack_pixabay_84375` (381 frames), `jumpingJack_pixabay_292741` (628 frames).
- **Behavior Before Fix**:
  - In `84375` (continuous rhythmic jumping jacks), `repCount = 0`. Analyzer remained stuck in `concentric` ("And back down").
- **Root Cause** (`app/lib/core/app_constants.dart:89-90`):
  - `jumpingJackRestAngle = 45.0`. During rapid jumping jacks, the athlete's arms bounce at ~50°-55° abduction at the bottom of each jump without clamping against the ribs.
  - Because `curAngle` bottomed out at 54.6°, `curAngle <= 45.0` was never satisfied, trapping the analyzer in `concentric`.
- **Fix Applied**:
  - In `app_constants.dart`: `jumpingJackRestAngle = 55.0` and `jumpingJackTopAngle = 130.0`.
- **Verified Result**: `jumpingJack_pixabay_84375` counts 5 reps, and `jumpingJack_pixabay_292741` counts 7 clean reps.

---

## 3. "Fixed" vs "Found but Not Fixed"

### Fixed
- All 8 confirmed root causes detailed above across `PushupAnalyzer`, `LungeAnalyzer`, `OverheadPressAnalyzer`, `PlankAnalyzer`, `GluteBridgeAnalyzer`, `SitupAnalyzer`, `JumpingJackAnalyzer`, and `TimedExerciseAnalyzer` (`WallSitAnalyzer`, `SidePlankAnalyzer`).

### Found but Not Fixed (Explicit Design Decisions / Tradeoffs)
1. **Front-Facing Squats (`squat_pexels_4764175`)**:
   - *Behavior*: Athlete squats deeply from a front-facing perspective, but reps do not count.
   - *Decision*: **Not fixed by design**. Squat form analysis requires measuring spine curvature (back rounding) and 3D hip hinge depth, which cannot be accurately verified from a front-on view. The analyzer already correctly detects `ViewOrientation.frontOn` and issues the `"turn side-on"` audio/visual cue every 5 seconds.
2. **Partial Overhead Press Lockout (`overheadPress_pexels_32239223`)**:
   - *Behavior*: Reps peaking at 144° elbow extension are not credited.
   - *Decision*: **Not fixed by design**. A 144° elbow angle represents an incomplete press (stopping well short of overhead lockout). The analyzer correctly withholds rep counts and prompts `"Reach higher"`.
3. **Plank Extreme Hip Pike (`plank_pexels_7117437`)**:
   - *Behavior*: In frames where the athlete's body folds into a tent shape (> 35° deviation from midline), landmarks fluctuate between piked and sagging.
   - *Decision*: **Not fixed by design**. Extreme distortion breaks 2D posture geometry; the app correctly flags broken form (`Hips Piked`) and reduces hold score to 0.40.

---

## 4. Test Files and Artifacts

### Test Files
- `app/test/stock_footage_regression_test.dart`: Updated to contain 17 regression test cases across all 10 exercises, driving recorded pose fixtures directly through real analyzers.

### Pose Sequences (JSON Fixtures in `app/test/fixtures/pose_sequences/`)
- `squat_pexels_8837221.json`
- `squat_pexels_4764175.json`
- `squat_pixabay_148204.json`
- `pushup_pexels_4367576.json`
- `pushup_pixabay_302251.json`
- `pushup_pixabay_143431.json`
- `pushup_pixabay_58984.json`
- `lunge_pexels_8171292.json`
- `lunge_pexels_4488004.json`
- `overheadPress_pexels_4367541.json`
- `overheadPress_pexels_32239223.json`
- `plank_pexels_6525477.json`
- `plank_pexels_7117437.json`
- `plank_pexels_4945589.json`
- `gluteBridge_pexels_6525487.json`
- `gluteBridge_pexels_4267359.json`
- `situp_pixabay_293079.json`
- `situp_pixabay_296446.json`
- `situp_pixabay_84706.json`
- `jumpingJack_pixabay_292741.json`
- `jumpingJack_pixabay_84375.json`
- `wallSit_pexels_6454275.json`
- `wallSit_pexels_6326797.json`
- `wallSit_pexels_8402078.json`
- `sidePlank_pexels_6023264.json`
- `sidePlank_pexels_6023265.json`

### Tools & Scripts
- `tools/harvest_all_pexels.py`
- `tools/harvest_pexels.py`
- `tools/harvest_remaining_pexels.py`
- `tools/extract_all_fixtures.py`
- `tools/harvested_clips_manifest.json`
- `tools/video_manifest.json`

---

## 5. Local Commits Log
All commits were created locally on `main` and **have NOT been pushed to origin**:

1. `a1418a0` - `test: add stock footage pose fixtures and extraction tools for 10 exercises`
2. `1f68cd4` - `fix(logic): harden exercise analyzers against real footage across all 10 exercises`
3. `b789ea2` - `test: add regression tests for all 10 exercises on real stock footage`
