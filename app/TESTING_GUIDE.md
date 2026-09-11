# Testing Guide

## Form Analyzer - Comprehensive Testing Documentation

This document provides detailed testing procedures for the Form Analyzer application.

## Table of Contents
1. [Setup for Testing](#setup-for-testing)
2. [Manual Testing](#manual-testing)
3. [Automated Testing](#automated-testing)
4. [Performance Testing](#performance-testing)
5. [Platform-Specific Testing](#platform-specific-testing)

---

## Setup for Testing

### Prerequisites
```bash
# Verify Flutter installation
flutter doctor -v

# Get dependencies
flutter pub get

# Check connected devices
flutter devices
```

### Test Environment
- **Recommended**: Physical device with good camera
- **Lighting**: Well-lit environment for pose detection
- **Space**: 2-3 meters clearance for full body visibility

---

## Manual Testing

### 1. Camera Initialization Tests

#### Test Case 1.1: Successful Camera Launch
**Steps:**
1. Launch the app
2. Grant camera permission when prompted

**Expected Results:**
- Camera preview loads within 2-3 seconds
- "Starting camera..." loading indicator displays briefly
- Camera stream starts smoothly

**Status Indicators:**
- ✅ Top bar shows "Squat Analyzer" badge
- ✅ Rep counter shows "0 reps"
- ✅ Bottom status shows "Align yourself in the frame"

#### Test Case 1.2: Permission Denied
**Steps:**
1. Launch app
2. Deny camera permission

**Expected Results:**
- Error screen with warning icon
- Message: "Camera permission denied. Please enable it in settings."
- "Try Again" button visible
- No crash or freeze

#### Test Case 1.3: No Camera Available
**Steps:**
1. Test on device/emulator without camera

**Expected Results:**
- Error screen displays
- Message: "No cameras available on this device."
- Graceful fallback (no crash)

---

### 2. Pose Detection Tests

#### Test Case 2.1: Body Not Visible
**Steps:**
1. Launch app
2. Stand outside camera frame

**Expected Results:**
- Status: "Move fully into the frame"
- Orange warning icon
- No skeletal overlay
- No angle displayed

#### Test Case 2.2: Partial Body Visible
**Steps:**
1. Launch app
2. Show only upper body or only lower body

**Expected Results:**
- Status: "Keep your full body visible"
- Orange warning icon
- Partial skeletal overlay (if any landmarks detected)

#### Test Case 2.3: Full Body Visible
**Steps:**
1. Launch app
2. Stand fully in frame (head to feet visible)

**Expected Results:**
- Skeletal overlay displays
- Hip-Knee-Ankle angle shows near knee
- Status updates based on position
- Green lines for good form, red for insufficient depth

---

### 3. Squat Tracking Tests

#### Test Case 3.1: Standing Position
**Steps:**
1. Stand upright with legs straight

**Expected Results:**
- Knee angle: ~160° or higher
- Status: "Ready to squat"
- Cyan icon
- Green skeletal lines

#### Test Case 3.2: Proper Squat Depth
**Steps:**
1. From standing, squat down
2. Stop when knees at ~80-90° angle

**Expected Results:**
- Knee angle: 70-90° displayed
- Status: "Good depth! Now stand up"
- Green checkmark icon
- Phase changes to "down"

#### Test Case 3.3: Complete Rep
**Steps:**
1. From standing, squat to proper depth (70-90°)
2. Return to standing (>160°)

**Expected Results:**
- Rep counter increments: "0" → "1"
- Counter animates (elastic pop effect)
- Status: "Great squat!"
- Green checkmark icon

#### Test Case 3.4: Insufficient Depth
**Steps:**
1. Perform partial squat (>100° knee angle)

**Expected Results:**
- Status: "Go lower"
- Orange icon
- Red skeletal lines (while squatting)
- Rep NOT counted

#### Test Case 3.5: Too Deep
**Steps:**
1. Squat very deep (<70° knee angle)

**Expected Results:**
- Status: "Too deep - maintain control"
- Red warning icon
- Visual feedback for safety

#### Test Case 3.6: Multiple Reps
**Steps:**
1. Perform 5 consecutive proper squats

**Expected Results:**
- Counter increments: 1 → 2 → 3 → 4 → 5
- Each rep counted only once
- No phantom counts
- Smooth counter animation

#### Test Case 3.7: Reset Counter
**Steps:**
1. Perform 3 reps (counter shows "3")
2. Tap reset button (circular arrow icon)

**Expected Results:**
- Counter resets to "0"
- Status resets to "Align yourself in the frame"
- No crash or lag

---

### 4. UI/UX Tests

#### Test Case 4.1: UI Elements Visible
**Steps:**
1. Launch app with full body visible

**Expected Results:**
- Top overlay: App title, rep counter, reset button
- Bottom overlay: Status message with icon, angle badge
- Semi-transparent backgrounds
- Readable text on all backgrounds

#### Test Case 4.2: Status Messages & Colors
**Verify color coding:**
- Cyan: "Ready to squat", "Align yourself"
- Green: "Great squat!", "Good depth!"
- Orange: "Go lower", "Stand up", "Move into frame"
- Red: "Too deep"

#### Test Case 4.3: Angle Display
**Expected:**
- Angle displayed near knee on skeleton
- Background color matches form status
- Updates in real-time
- Readable font size

---

### 5. App Lifecycle Tests

#### Test Case 5.1: Background/Foreground
**Steps:**
1. Launch app
2. Press home button (app goes to background)
3. Return to app

**Expected Results:**
- Camera stops when backgrounded
- Loading indicator when returning
- Camera restarts automatically
- No crash

#### Test Case 5.2: Lock Screen
**Steps:**
1. Launch app
2. Lock device
3. Unlock device

**Expected Results:**
- Camera pauses
- Camera resumes on unlock
- No crash or freeze

#### Test Case 5.3: App Termination
**Steps:**
1. Launch app
2. Force close from task manager
3. Relaunch

**Expected Results:**
- Clean restart
- No residual data
- Camera initializes normally

---

## Automated Testing

### Unit Tests

```bash
# Run all unit tests
flutter test

# Run with coverage
flutter test --coverage

# View coverage report
genhtml coverage/lcov.info -o coverage/html
```

### Key Test Areas
- `calculateJointAngle()` function accuracy
- `SquatHeuristic` state machine logic
- Angle calculations with edge cases (null landmarks, coincident points)
- Rep counting logic

### Sample Unit Test
```dart
test('calculateJointAngle returns 0 for null landmarks', () {
  final angle = calculateJointAngle(null, null, null);
  expect(angle, equals(0.0));
});

test('SquatHeuristic counts rep on depth then stand', () {
  final squat = SquatHeuristic();
  expect(squat.repCount, equals(0));
  
  squat.update(80); // Proper depth
  expect(squat.repCount, equals(0)); // Not counted yet
  
  squat.update(165); // Stand up
  expect(squat.repCount, equals(1)); // Rep counted
});
```

### Real-Footage Regression Tests

`test/stock_footage_regression_test.dart` drives the real `ExerciseAnalyzer`
subclasses with landmark sequences recorded from real stock exercise footage,
instead of only the hand-authored idealized angle sweeps used elsewhere. This
runs under plain `flutter test` (no device/emulator needed) and catches things
a clean synthetic sweep can't: noisy, non-monotonic real motion tripping up
the rep-counting state machine.

**How it works**: ML Kit's pose detector is a platform-channel plugin and
can't run outside a device, so these fixtures are generated offline with
MediaPipe Pose (Google's other pose-landmark model, close enough
anatomically to drive the same analyzer logic) via
`tools/extract_pose_fixtures.py`. This is a proxy for ML Kit's real output,
not a guarantee ML Kit behaves identically on-device — full on-device
verification still needs a real `integration_test` + emulator/device suite,
which doesn't exist yet.

**Adding a new recorded fixture** (e.g. for lunge/plank/overhead press):
```bash
# one-time setup
pip install mediapipe opencv-python numpy
curl -L "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task" \
    -o tools/pose_fixture_footage/models/pose_landmarker_full.task

# extract a new clip (defaults to sampling at the source frame rate)
python tools/extract_pose_fixtures.py \
    tools/pose_fixture_footage/<clip>.mp4 \
    app/test/fixtures/pose_sequences/<name>.json
```

Then **actually trace the real analyzer against the fixture** before writing
assertions — don't assume the app will agree with what the source video looks
like. Two mistakes already happened building this pipeline, both worth not
repeating:
- **Don't zero out Z.** `MathUtils.calculateAngleFromCoordinates` falls back
  to 2D-only math whenever all three landmarks' Z reads as flat/zero
  (`_hasReliableZCoordinates`). MediaPipe documents Z as using roughly the
  same scale as X, so `extract_pose_fixtures.py` carries it through, scaled
  like X. Skipping this makes a front-facing camera's squat depth (which is
  mostly a depth-axis motion, invisible in 2D from the front) measure as far
  shallower than it really is.
- **Don't undersample.** A fast rep's true bottom can fall between sampled
  frames. Sampling one real clip at 10fps undercounted 2 of 5 genuinely deep
  squats because the analyzer never saw the actual minimum angle. The script
  now defaults to the source frame rate for exactly this reason.

Even with both of those right, this pipeline caught two more real bugs in
`SquatAnalyzer.processPose` itself, both since fixed and locked in by
`stock_footage_regression_test.dart`:
- The depth check compared against an angle that had been through two
  stages of smoothing (a per-landmark exponential filter, then a 5-frame
  moving average on top). A fast rep's true bottom can survive neither —
  real footage showed a rep that hit 61-66 degrees at its actual deepest
  frame read as high as 100 degrees post-smoothing, missing
  `squatDepthThreshold` despite genuinely reaching depth. Fixed by checking
  depth against the unsmoothed landmarks directly; the eccentric/concentric
  direction-reversal check still uses the smoothed angle, since that one
  benefits from the noise rejection.
- That depth check also picked a leg by ML Kit's confidence score, on the
  assumption the more confident leg is the more accurate one. Real footage
  showed the opposite for a full rep: the higher-confidence leg read
  100-160 degrees for its entire duration while the other leg (still
  comfortably above the visibility threshold) read 66-95 degrees for the
  same frames. A squat's depth is bilaterally symmetric, so a confidence
  gap between the two sides reflects estimation error, not anatomy — fixed
  by taking whichever visible leg reads deeper for the depth check
  specifically.

If a future fixture surfaces a similar-looking discrepancy, don't assume
it's already covered by these two fixes — trace it and confirm. Other real
(non-bug) ways a clip can fail to produce the rep count you expect from
watching it:
- **Visibility**: `SquatAnalyzer` requires all six leg landmarks
  (`AppConstants.visibilityThreshold = 0.7`); a clip where one leg is
  occluded or blurred will read "Adjust Camera" forever and never exercise
  the rep-counting logic at all.
- **Camera angle**: a rep only closes when the tracked angle climbs back to
  `AppConstants.squatNeutralThreshold`/`pushupNeutralThreshold`. A
  front-facing camera can leave MediaPipe's 3D "standing" reconstruction
  permanently short of that threshold, so no rep ever counts regardless of
  depth -- the same reason the app's back-angle safety check already gates
  itself on a confirmed side view (`hasSideView` in `SquatAnalyzer.processPose`).
  This isn't a silent failure: `updateOrientation` runs unconditionally every
  frame and already fires the "turn side-on" cue (`CueIds.turnSideOn`,
  repeating every 5 seconds) via pure 2D geometry (`PoseOrientation`,
  unaffected by the Z issues above), so a front-facing athlete gets told why
  before assuming the app is broken. Verified, not assumed -- see the second
  squat test in `stock_footage_regression_test.dart`.

The only trustworthy way to know which of these you're looking at is to
print `lastProcessedAngle`/`phase`/`squatState` (or the pushup/plank
equivalents) frame-by-frame from a real `flutter test` run and read what the
state machine actually did, then write the assertion to match that —
verified behavior, not a guess from the source video.

---

## Performance Testing

### Frame Rate Test
**Steps:**
1. Enable performance overlay:
```bash
flutter run --profile
```
2. Tap screen to show FPS overlay
3. Perform squats while monitoring

**Expected:**
- Steady 15-20 FPS
- No significant drops during processing
- GPU/CPU usage reasonable

### Memory Test
**Steps:**
1. Run with DevTools:
```bash
flutter run --profile
# Open DevTools from terminal link
```
2. Monitor memory tab
3. Perform 50+ reps over 5 minutes

**Expected:**
- No memory leaks
- Stable memory usage
- GC events reasonable

### Battery Test
**Steps:**
1. Full battery charge
2. Run app for 30 minutes
3. Monitor battery drain

**Expected:**
- <15% battery drain per 30 minutes
- Device doesn't overheat
- Sustainable for typical workout session

---

## Platform-Specific Testing

### Android Testing

#### API Levels
Test on:
- Android 5.0 (API 21) - Minimum supported
- Android 10 (API 29) - Common version
- Android 14 (API 34) - Latest target

#### Device Variations
- **Low-end**: 2GB RAM, budget processor
- **Mid-range**: 4GB RAM, standard processor
- **High-end**: 6GB+ RAM, flagship processor

#### Specific Checks
- ProGuard working in release build
- Camera permissions prompt
- ML Kit models download (first run)
- Orientation lock works

### iOS Testing

#### iOS Versions
Test on:
- iOS 11.0 - Minimum supported
- iOS 14.0 - Common version
- iOS 17.0 - Latest

#### Device Variations
- iPhone SE (small screen)
- iPhone 12/13 (standard)
- iPhone 14 Pro Max (large screen)

#### Specific Checks
- Camera permission alert
- Portrait orientation locked
- No camera API crashes
- Pose detection accuracy

---

## Regression Testing Checklist

Before each release:
- [ ] Camera initializes successfully
- [ ] Permissions work on both platforms
- [ ] Pose detection functional
- [ ] Rep counting accurate
- [ ] UI elements display correctly
- [ ] No crashes during 10-minute session
- [ ] App lifecycle handling works
- [ ] Release build optimized (ProGuard working)
- [ ] Performance acceptable (FPS, memory)
- [ ] All deprecation warnings resolved

---

## Bug Reporting Template

When filing bugs, include:

```
**Environment:**
- Device: [e.g., Pixel 6, iPhone 13]
- OS Version: [e.g., Android 13, iOS 16]
- App Version: [e.g., 1.0.0+1]
- Build Type: [Debug/Release]

**Steps to Reproduce:**
1. 
2. 
3. 

**Expected Behavior:**


**Actual Behavior:**


**Screenshots/Logs:**


**Frequency:**
[Always / Sometimes / Rarely]
```

---

## Test Results Log

### Test Session Template
```
Date: YYYY-MM-DD
Tester: [Name]
Device: [Model]
OS: [Version]
Build: [Version]

| Test Case | Status | Notes |
|-----------|--------|-------|
| 1.1       | ✅     |       |
| 1.2       | ✅     |       |
| 2.1       | ✅     |       |
...
```

---

**Last Updated:** March 6, 2026
**Version:** 1.0.0

