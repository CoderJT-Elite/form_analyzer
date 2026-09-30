# Changelog

## [Unreleased]

### Fixed (live-test 2026-09-29)
Test #3 was recorded on a build older than the fixes it was meant to test, so it first needed a way to know what is on the phone.
- **Build identity.** `BuildInfo` (git SHA, dirty flag, build time) is shown at the bottom of Profile, and `tools/install_phone.ps1` refuses to build a test APK from uncommitted code.
- **Push-ups were counted on almost no clip** (1-4 reps where the elbow signal shows 6+). The smoothed elbow angle bottomed out at 110-125 degrees on reps whose raw angle reached 55-80, and the state machine waited for 90. Reps are now found from the athlete's own range (`logic/rep_cycle_detector.dart`); depth is graded rather than gating the count, so shallow real reps count and are scored short. Push-ups and sit-ups measure in the image plane only (ML Kit depth added ~16 degrees of mean error on a planar movement).
- **Head-on push-ups** (camera on the floor facing the athlete) are counted from how far the shoulders sit above the wrists, holding the last reading through the tracker dropouts that happen at the bottom of the rep.
- **The phone on its side.** `DeviceGravityService` reads the accelerometer, so ML Kit is given the scene the right way up and poses are levelled before any analyzer sees them (`logic/gravity_frame.dart`, `logic/pose_normalizer.dart`); the skeleton overlay is mapped back to the preview at every rotation. Tested against Android's documented rotation-compensation formula for all four device rotations on both cameras.
- **Hip verdicts no longer flip-flop** ("hips up" then "lower your hips" 0.2 s later). `HipLineJudge` works in the gravity frame with hysteresis, a dwell, a minimum time between opposite calls and an "unjudgeable" outcome for a body too upright to have a floor line (leaning on a wall).
- **Holds.** A plank is judged only once the athlete has settled into a floor position (in the gravity-aligned frame); someone standing up or leaning on a wall is not in a plank and is told so. When gravity is unknown (no accelerometer) that check is skipped, since a sideways plank cannot then be told from standing. Bad form no longer stops the clock (it was read as "stood up"), and holds accept a lower landmark confidence so brief dropouts do not pause it.
- **Phone handling.** Picking the phone up pauses counting, takes back reps counted just before, and offers to save the set (`logic/phone_motion.dart`); floor vibration from jumping jacks does not count as movement. This removes the phantom overhead-press rep at the end of a set.
- **Setup never counts down at an empty room.** The 4 s fallback now needs an athlete recently in frame and a still phone; moving the phone during the countdown returns to guidance.
- **Non-athletes.** Poses on a barbell plate or a blurred face close-up are dropped before they count or draw (`logic/pose_validity.dart`).
- **No lost sets.** Ending a workout in which nothing was counted now asks the athlete to save the set by hand (no form score), keep going or discard, instead of a snackbar. The summary has a rep stepper; the counter's own number is stored with it (`ExerciseSet.countedReps`) as the app's only real accuracy measure.
- **Honest summaries.** Heavily corrected sets get no star rating, sets of fewer than 3 reps get no best/worst commentary, a summary never lists sagging and piked hips together, and multi-set workouts are rated from their saved sets.
- **Cues.** "Turn side-on" is no longer spoken mid-set; it needs a persistently wrong view with nothing counted.
- **Diagnostics.** Optional on-device `SessionRecorder` (Profile, after tapping the build line five times) writes real ML Kit poses in the fixture format plus timing, gravity, phone motion and every rep/cue/spoken phrase, so the next live test yields exact fixtures. A "Test Voice" row lets the athlete check the volume before a workout.
- Tests: `live3_*` fixtures with ground truth, `RepCycleDetector`, gravity/painter rotation invariance, hip judge, phone motion, validity, presence, recorder round trip, session flow. Timing-dependent tests now use simulated clocks (a tight loop on the wall clock made every rep last 0 ms, which is why the old stock push-up tests pinned 1-4 reps).

### Fixed (live-test 2026-09-20)
- Rep counting no longer wedges in the "coming back up" phase: a rep now closes once the athlete has recovered most of their own range and stopped or turned around (`logic/rep_recovery.dart`), with a watchdog. Real-footage counts went from squat 2/~9, jumping jack 2/~15, sit-up 3/~12 to roughly the true numbers.
- Squat works from one visible leg (side-on far leg is occluded), and "Rounded Back / Critical Back Rounding" is replaced by a torso-vs-shin "Excessive Forward Lean" check: the old shoulder-hip-knee angle is hip flexion and flagged every deep squat.
- Range-of-motion exercises (jumping jack, sit-up, glute bridge) count a rep that travels most of the range and score the shortfall, instead of silently discarding it.
- Plank/push-up/side-plank sag-vs-pike no longer assumes an upright phone; plank tolerates brief landmark dropouts and accepts a straight-arm (high) plank.
- Speech: safety cues are no longer chopped off by their own repeat (normal cues are dropped while speaking, urgent ones interrupt only normal ones); a delivered cue now stays on screen; the setup screen no longer speaks the same phrase twice in six seconds.
- Cue wording is direction-correct per exercise (no "lower a little further" for jumping jacks, no "thighs parallel" for push-ups).
- Timed holds show time (`SECONDS` HUD, `TIME HELD` summary, `HELD` history) and no longer inflate lifetime "TOTAL REPS"; tiny samples note that the rating is based on few reps.
- Skeleton: thighs are no longer permanently red outside squats; jumping jacks draw the legs.
- Added `tools/extract_live_test_fixtures.py` and real on-phone fixtures (`test/fixtures/pose_sequences/live2_*.json`) with `live_footage_regression_test.dart`.

### Changed
- Made `web/` the canonical landing site and converted root `index.html` to a redirect.
- Standardized waitlist submission in `web/index.html` to Formspree (`mvzwveen`).
- Improved landing accessibility (removed forced hidden cursor, restored visible scrollbars, modal ARIA + focus trap).
- Added `web/privacy.html` and linked privacy disclosure from the waitlist modal/footer.
- Updated Pages workflow to lint web HTML and validate non-placeholder form configuration before deploy.
- Clarified root README deployment instructions and corrected repository naming/path examples.
- Rebuilt the landing page into a minimal/lightweight single-page layout with one image and removed unsupported marketing claims.
- Replaced synthetic beta counter behavior with `web/data/beta-count.json` consumption.
- Added scheduled Formspree sync workflow (`update_formspree_beta_count.yml`) for `web/data/beta-count.json`.
