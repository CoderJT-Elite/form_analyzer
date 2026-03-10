# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-03-06

### Fixed
- **iOS Camera Permission**: Added required `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` keys to Info.plist for camera access
- **Deprecated APIs**: Replaced all `withOpacity()` calls with `withValues(alpha: ...)` throughout the application for Flutter 3.10+ compatibility
- **Missing Import**: Added `package:flutter/services.dart` import for `DeviceOrientation` enum
- **Android Target SDK**: Updated targetSdk from 33 to 34 for latest Android compatibility

### Added
- **ProGuard Rules**: Created `proguard-rules.pro` with rules for ML Kit, TensorFlow Lite, and Camera libraries to ensure proper functionality in release builds
- **Code Minification**: Enabled minification in release builds for smaller app size
- **Production Documentation**: Created comprehensive deployment guide with setup, testing, and troubleshooting instructions
- **Error Handling**: Enhanced error messages for camera permissions and initialization failures

### Improved
- **Code Quality**: Fixed all deprecation warnings for production readiness
- **Build Configuration**: Optimized Android build settings for release deployment
- **Documentation**: Updated README with technical details and usage instructions

### Technical Details
#### Image Processing
- Using YUV420 format for optimal ML Kit compatibility
- Frame processing lock prevents overlapping work
- Stable 15-20 FPS performance
- Format fallback to NV21 if raw format unavailable

#### Platform Support
- **Android**: Minimum SDK 21, Target SDK 34
- **iOS**: iOS 11.0+, camera permission required
- **Flutter**: SDK ^3.10.4

#### Dependencies
```yaml
camera: ^0.11.0
google_mlkit_pose_detection: ^0.12.0
```

### Security
- On-device processing only (no data transmission)
- Runtime permission requests
- Clear privacy descriptions for users
- No video recording or image storage

## [Pre-Release] - Before 2026-03-06

### Initial Features
- Real-time pose detection using Google ML Kit
- Squat exercise tracking with depth monitoring
- Hip-Knee-Ankle angle calculation (70-90° optimal depth)
- Automatic rep counting with phase detection
- Live skeletal overlay visualization
- Form feedback and coaching messages
- Color-coded visual feedback (green/red based on form)
- Automatic camera orientation handling
- Multi-pose support with confidence scoring
- App lifecycle management (pause/resume handling)

### Architecture
- State machine-based rep counting
- Custom painter for pose overlay
- 3D vector mathematics for joint angles
- Processing lock for frame rate stability
- Comprehensive error handling
- Material 3 dark theme UI

---

## Semantic Versioning

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions  
- **PATCH** version for backwards-compatible bug fixes

## Categories

### Types of Changes
- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security updates

