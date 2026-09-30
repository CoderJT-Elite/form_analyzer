# Changelog

## [Unreleased]

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
