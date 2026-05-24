# Form Analyzer (MVP)

A Flutter app that analyzes exercise form in real time using on-device pose detection.

## MVP Scope

This repository currently focuses on one complete flow:
- Open app
- Start camera-based analysis
- Track **back squat** reps and form cues
- Review in-app history/stats

Anything outside that core path is considered non-MVP and should stay secondary.

## Core Features (Kept)

- Real-time pose detection (Google ML Kit)
- Squat rep counting and depth guidance
- Live pose overlay
- Voice/text coaching feedback
- Local history storage

## Project Layout

- `lib/main.dart`: App entry point
- `lib/services/pose_detector_service.dart`: Pose detection pipeline
- `lib/logic/exercise_analyzer.dart`: Form analysis logic
- `lib/ui/screens/`: Main app screens
- `test/`: Unit/widget tests

## Run Locally

```bash
flutter pub get
flutter run
```

## Validate

```bash
flutter analyze
flutter test
```

> Note: In this execution environment, Flutter SDK may be unavailable; run validation commands on a machine with Flutter installed.
