# Form Analyzer - Production Deployment Guide

## Project Status: ✅ Production Ready

All errors have been fixed and the application is ready for deployment.

## Recent Fixes Applied

### 1. **iOS Camera Permissions** ✅
- Added `NSCameraUsageDescription` to Info.plist
- Added `NSMicrophoneUsageDescription` for camera plugin compatibility

### 2. **Code Quality** ✅
- Fixed all deprecated `withOpacity()` calls → replaced with `withValues(alpha: ...)`
- Added missing imports (`flutter/services.dart` for DeviceOrientation)
- Proper async handling with `unawaited()` for fire-and-forget futures

### 3. **Android Configuration** ✅
- Updated targetSdk to 34 (latest stable)
- Added ProGuard rules for ML Kit and TensorFlow Lite
- Enabled code minification for release builds
- MultiDex support enabled

### 4. **Error Handling** ✅
- Comprehensive camera error handling
- Permission denial detection
- Graceful fallbacks for missing landmarks
- Processing lock to prevent frame overlap

## Prerequisites

### Development Environment
- Flutter SDK ^3.10.4 or higher
- Android Studio / Xcode (for respective platforms)
- Physical device recommended (emulators may have limited camera support)

### Android Requirements
- minSdk: 21 (Android 5.0 Lollipop)
- targetSdk: 34 (Android 14)
- Camera permission
- Physical device or emulator with camera support

### iOS Requirements
- iOS 11.0 or higher
- Camera permission
- Physical device recommended (Simulator has limited pose detection)

## Installation & Setup

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Verify Flutter Setup
```bash
flutter doctor
```

### 3. Connect Device
```bash
# Check connected devices
flutter devices

# For Android
adb devices

# For iOS
xcrun xctrace list devices
```

## Running the App

### Debug Mode (Development)
```bash
# Run on connected device
flutter run

# Run on specific device
flutter run -d <device-id>

# Run with verbose logging
flutter run -v
```

### Release Mode (Testing)
```bash
# Android
flutter run --release

# iOS (requires signing)
flutter run --release -d ios
```

## Building for Production

### Android APK
```bash
# Build release APK
flutter build apk --release

# Build split APKs (smaller size)
flutter build apk --split-per-abi --release

# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Android App Bundle (Google Play)
```bash
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

### iOS
```bash
# Build iOS app (requires Mac)
flutter build ios --release

# Then open Xcode to archive and distribute
open ios/Runner.xcworkspace
```

## Testing

### Unit Tests
```bash
flutter test
```

### Integration Tests
```bash
# Run on connected device
flutter test integration_test/
```

### Performance Testing
```bash
# Profile mode with performance overlay
flutter run --profile --trace-skia
```

## Configuration

### App Identifier
To publish to stores, update the application ID:

**Android:** `android/app/build.gradle.kts`
```kotlin
applicationId = "com.yourcompany.form_analyzer"
```

**iOS:** Open `ios/Runner.xcworkspace` in Xcode
- Select Runner project
- Update Bundle Identifier

### App Name
**Android:** `android/app/src/main/AndroidManifest.xml`
```xml
android:label="Your App Name"
```

**iOS:** `ios/Runner/Info.plist`
```xml
<key>CFBundleDisplayName</key>
<string>Your App Name</string>
```

### App Icon
Replace icons in:
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

Or use `flutter_launcher_icons` package

## Performance Optimization

### Current Optimizations
✅ YUV420 image format for optimal camera performance
✅ Frame processing lock (15-20 FPS stable)
✅ Early frame drops when processing is behind
✅ ProGuard enabled for Android release builds
✅ Stream mode for ML Kit (optimized for real-time)

### Monitoring
- Use Flutter DevTools for performance profiling
- Monitor frame rates with `flutter run --profile`
- Check memory usage during extended sessions

## Troubleshooting

### Camera Permission Issues
**Android:**
- Grant permission manually in Settings → Apps → Form Analyzer → Permissions
- Check `AndroidManifest.xml` has camera permission

**iOS:**
- Settings → Privacy → Camera → Enable for app
- Verify Info.plist has camera usage description

### ML Kit Errors
- Ensure device has Google Play Services (Android)
- Test on physical device (better than emulator)
- Check ProGuard rules are in place for release builds

### Build Errors
```bash
# Clean build cache
flutter clean

# Get dependencies
flutter pub get

# Rebuild
flutter build apk --release
```

### Pose Detection Not Working
- Ensure full body is visible in frame
- Good lighting conditions
- Camera pointing at person from front or side
- Check device meets minimum requirements

## Production Checklist

✅ All deprecated APIs replaced
✅ Camera permissions configured (Android & iOS)
✅ Error handling implemented
✅ ProGuard rules added
✅ Release build tested
✅ Performance optimized
✅ Code quality verified
✅ README documentation updated

## Security Considerations

### Privacy
- App only uses camera for real-time analysis
- No video recording or image storage
- No data sent to external servers
- All processing happens on-device

### Permissions
- Only camera permission required
- Permission requested at runtime
- Clear usage description provided

## Support & Maintenance

### Dependencies
Keep dependencies updated:
```bash
flutter pub upgrade --major-versions
```

Check for CVEs:
```bash
flutter pub outdated
```

### Monitoring
- Monitor crash reports in production
- Track performance metrics
- User feedback for UX improvements

## License
[Add your license information here]

## Contact
[Add your contact information here]

---

**Version:** 1.0.0+1
**Last Updated:** March 6, 2026
**Status:** Production Ready ✅

