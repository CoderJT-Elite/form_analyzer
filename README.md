# Form Analyzer

A Flutter application for real-time exercise form analysis using pose detection and ML Kit.

## Features

- Real-time pose detection using Google ML Kit
- Exercise rep counting (currently supports bicep curls)
- Live visual feedback with skeletal overlay
- Form guidance and coaching messages
- Automatic camera orientation handling

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

- **Pose Detection**: Uses Google ML Kit's Pose Detection API
- **Camera**: Flutter camera plugin with YUV420 format for optimal performance
- **Rep Counting**: Angle-based detection using joint positions
- **UI**: Custom painter for skeletal overlay visualization

## Troubleshooting

If you encounter camera or image processing errors:

1. Ensure camera permissions are granted
2. Check that your device meets the minimum Android SDK requirement (API 21+)
3. Try restarting the app if camera initialization fails

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
