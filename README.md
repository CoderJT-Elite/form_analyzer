# Form Analyzer

A Flutter application for real-time exercise form analysis using pose detection and ML Kit.

## Features

- Real-time pose detection using Google ML Kit
- **Back squat tracking** with depth monitoring (70° ≤ θ ≤ 90°)
- Live visual feedback with skeletal overlay
- Form guidance and coaching messages
- Automatic camera orientation handling
- Frame rate control (15-20 FPS) for stable performance

## Current Exercise Support

### Back Squats
- Tracks Hip-Knee-Ankle angle in real-time
- Validates proper squat depth (70-90 degrees at knee)
- Counts reps automatically
- Provides form feedback:
  - "Good depth! Now stand up" - when reaching proper depth
  - "Go lower" - when not deep enough
  - "Too deep - maintain control" - safety warning
  - "Great squat!" - rep completed

## Requirements

- Flutter SDK ^3.10.4
- Android: minSdk 21 or higher
- Camera permission required

## Getting Started

### Prerequisites

Make sure you have Flutter installed. If not, follow the [Flutter installation guide](https://docs.flutter.dev/get-started/install).

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

### Running the App

To run the app on a connected device or emulator:

```bash
flutter run
```

For release build:

```bash
flutter build apk --release
```

## Permissions

The app requires camera permission to function. On first launch, you'll be prompted to grant camera access.

## Architecture

- **Pose Detection**: Uses Google ML Kit's Pose Detection API in stream mode
- **Camera**: Flutter camera plugin with YUV420 format for optimal performance
- **Angle Calculation**: 3D vector math using dot product formula for accurate joint angles
- **Rep Counting**: State machine-based tracking using Hip-Knee-Ankle angles
- **UI**: Custom PosePainter class for skeletal overlay visualization
- **Performance**: Processing lock ensures stable 15-20 FPS by dropping frames when needed

## Technical Details

### calculateAngle Function
The core angle calculation uses the dot product formula:
```dart
cos(θ) = (a·b) / (|a||b|)
```
where `a` and `b` are 3D vectors from the joint to adjacent landmarks.

### Squat Detection Logic
- **Standing**: Knee angle ≥ 160° (straight legs)
- **Proper Depth**: 70° ≤ knee angle ≤ 90° (good squat)
- **Too Deep**: Knee angle < 70° (safety concern)
- **Partial**: 90° < angle < 160° (transitioning)

### Processing Lock
The `_isProcessingFrame` flag prevents frame overlap:
- Set `true` before processing
- Returns early if already processing (frame drop)
- Always set `false` in `finally` block
- Maintains stable 15-20 FPS

## Testing

Run unit tests:
```bash
flutter test
```

Tests cover:
- Angle calculation accuracy (90°, 180°, etc.)
- 3D coordinate handling
- Edge cases (zero magnitude vectors)

## Troubleshooting

If you encounter camera or image processing errors:

1. Ensure camera permissions are granted
2. Check that your device meets the minimum Android SDK requirement (API 21+)
3. Try restarting the app if camera initialization fails
4. Make sure your full body is visible in the camera frame

## Future Enhancements

Potential additions (not currently implemented):
- Multiple exercise types (lunges, push-ups, etc.)
- Bilateral tracking (comparing left vs right)
- Rep history and analytics
- Configurable depth thresholds
- Audio feedback
- Video recording of sets

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
