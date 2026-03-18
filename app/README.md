# Form Analyzer

A Flutter application for real-time exercise form analysis using pose detection and ML Kit. This repository provides a professional, open-source foundation for external review by university researchers and biomechanics professionals.

## Features

- Real-time pose detection using Google ML Kit
- **Back squat tracking** with dynamic depth monitoring
- Live visual feedback with skeletal overlay
- Form guidance and coaching messages
- Automatic camera orientation handling
- Inference throttling for stable performance (target: 30 FPS)

## System Architecture

The application is built on a **Service-Oriented Model** to separate concerns between the UI, camera handling, and machine learning inference. This modular architecture allows for easy swapping of underlying ML models or camera implementations.

![System Data Flow Diagram](assets/system_data_flow_diagram_placeholder.png)

- **Pose Detection Service**: Encapsulates the Google ML Kit Pose Detection API, managing the lifecycle of the model and providing a continuous stream of detected anatomical landmarks.
- **Camera Service**: Manages the device camera, frame capture, and format conversion (optimizing for YUV420) to ensure high-throughput image delivery.
- **Form Analysis Engine**: Processes the stream of structured landmarks, applying biomechanical heuristics to determine exercise states, count repetitions, and provide corrective feedback.
- **UI Layer**: Consumes the real-time analysis results to provide immediate visual feedback, including a scaled skeletal overlay and situational text prompts.

## Technical Specifications

### Asynchronous Processing Lock
To maintain real-time performance and prevent memory exhaustion, the system implements an **Asynchronous Processing Lock**. 
This mechanism safely manages inference throttling to maintain a stable **30 FPS on mid-range mobile hardware**.

- **Frame Dropping**: If a new camera frame arrives while the previous frame is still being processed by the ML model, the new frame is intelligently dropped.
- **Lock Management**: An internal `_isProcessingFrame` flag is atomically checked and set to `true` before model inference, and reliably reset to `false` in a `finally` block, ensuring the pipeline never stalls even if an exception occurs during inference.

### 3D Vector Dot Product Math
The core joint angle calculation utilizes the 3D Vector Dot Product implemented in `math_utils.dart`. Given three 3D points forming a joint $A$, $B$ (vertex), and $C$, we define vectors $\vec{u} = A - B$ and $\vec{v} = C - B$.

The angle $\theta$ is calculated using the following LaTeX formula:
$$ \cos(\theta) = \frac{\vec{u} \cdot \vec{v}}{\|\vec{u}\| \|\vec{v}\|} $$

$$ \theta = \arccos\left(\frac{u_x v_x + u_y v_y + u_z v_z}{\sqrt{u_x^2 + u_y^2 + u_z^2} \sqrt{v_x^2 + v_y^2 + v_z^2}}\right) \times \frac{180}{\pi} $$

This ensures mathematically rigorous joint angle tracking in 3-dimensional space, accounting for depth away from the camera plane.

## Getting Started

### Prerequisites
- Flutter SDK ^3.10.4
- Android: minSdk 21 or higher
- Camera permissions

### Installation
```bash
git clone <repository_url>
cd form_analyzer
flutter pub get
flutter run
```

## Testing
Comprehensive testing is crucial for research validation. Run the unit test suite:
```bash
flutter test
```
Tests cover angle calculation accuracy, 3D coordinate handling, and edge cases (e.g., zero magnitude vectors).

## Troubleshooting
If you encounter camera or image processing errors:
1. Ensure camera permissions are granted
2. Check that your device meets the minimum Android SDK requirement (API 21+)
3. Try restarting the app if camera initialization fails
4. Make sure your full body is visible in the camera frame
