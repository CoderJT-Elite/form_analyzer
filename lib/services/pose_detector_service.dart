import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseDetectorService {
  late PoseDetector _poseDetector;

  PoseDetectorService() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
  }

  Future<List<Pose>> processImage(InputImage inputImage) {
    return _poseDetector.processImage(inputImage);
  }

  Future<void> dispose() {
    return _poseDetector.close();
  }
}
