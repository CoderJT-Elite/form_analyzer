# Form Analyzer

FormAnalyzer uses a phone's camera and on-device pose detection to count exercise reps, reject reps with bad form, and coach out loud in real time. It is built for students and home exercisers who train without a coach.

This repository contains:
- `app/`: the Flutter mobile app (Android), written in Dart with Google ML Kit pose detection
- `web/`: landing page assets

## What it does

- Covers ten exercises: squat, push-up, lunge, overhead press, plank, side plank, wall sit, sit-up, glute bridge and jumping jack.
- Each rep is counted, rejected as a "no-rep" with a spoken reason (for example, "A little deeper"), or ignored if it was not an attempt.
- Rules use body measurements that do not depend on how far the person stands from the camera (for example, squat depth is hip height over leg length).
- Camera video and workout data stay on the phone.
- The automated test suite (`flutter test`, 500+ tests) includes replays of recorded workouts.

For app setup, architecture, and validation steps, use:
- [`app/README.md`](app/README.md)

## Quick Start

```bash
cd app
flutter pub get
flutter run
```
