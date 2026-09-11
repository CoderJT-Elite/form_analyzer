"""Extract MediaPipe Pose landmark sequences from stock exercise footage and
write them as JSON fixtures consumable by app/test/support/recorded_pose_fixtures.dart.

Why MediaPipe instead of the app's real ML Kit detector: ML Kit's pose model is a
platform-channel Android/iOS plugin and can't run outside a device/emulator. MediaPipe
Pose is Google's other pose-landmark model, runs in plain Python, and uses the same
anatomical landmark set, so it's a reasonable stand-in to drive the real
ExerciseAnalyzer classes (app/lib/logic/exercise_analyzer.dart) with realistic,
noisy human-motion trajectories instead of only hand-authored idealized angle sweeps.
It is a proxy, not a guarantee ML Kit itself behaves identically on-device.

Setup (already done once in this environment, kept here for reproducibility):
    pip install mediapipe opencv-python numpy
    (mediapipe 1.0.1 installed fine under the system Python 3.14 here -- no venv
    fallback was needed. If a future machine's pip can't find a wheel for its
    Python version, create a 3.10/3.11/3.12 venv instead: `py -3.10 -m venv .venv`.)

    The MediaPipe Tasks API (this mediapipe version has no mp.solutions.pose) needs
    a downloaded model bundle:
    curl -L "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task" \
        -o tools/pose_fixture_footage/models/pose_landmarker_full.task

Usage:
    python tools/extract_pose_fixtures.py \
        tools/pose_fixture_footage/squat_pexels_4764175.mp4 \
        app/test/fixtures/pose_sequences/squat_pexels_4764175.json \
        --sample-fps 10
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import (
    PoseLandmarker,
    PoseLandmarkerOptions,
    RunningMode,
)

MODEL_PATH = (
    Path(__file__).parent / "pose_fixture_footage" / "models" / "pose_landmarker_full.task"
)

# MediaPipe's 33-point pose model uses the same anatomical landmarks as ML Kit's
# PoseLandmarkType enum (google_mlkit_pose_detection); only the subset the app's
# analyzers actually read (see ExerciseAnalyzer subclasses) is mapped here.
LANDMARK_INDEX_TO_ML_KIT_NAME = {
    11: "leftShoulder",
    12: "rightShoulder",
    13: "leftElbow",
    14: "rightElbow",
    15: "leftWrist",
    16: "rightWrist",
    23: "leftHip",
    24: "rightHip",
    25: "leftKnee",
    26: "rightKnee",
    27: "leftAnkle",
    28: "rightAnkle",
}


def extract(video_path: Path, sample_fps: float) -> list[dict[str, dict[str, float]]]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video: {video_path}")

    source_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frame_width = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
    frame_height = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    frame_stride = max(1, round(source_fps / sample_fps))

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=RunningMode.VIDEO,
        num_poses=1,
    )

    frames_out: list[dict[str, dict[str, float]]] = []
    frame_index = 0
    with PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            if frame_index % frame_stride == 0:
                timestamp_ms = int(frame_index / source_fps * 1000)
                frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
                mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
                result = landmarker.detect_for_video(mp_image, timestamp_ms)

                if result.pose_landmarks:
                    landmarks = result.pose_landmarks[0]
                    frame_out: dict[str, dict[str, float]] = {}
                    for idx, name in LANDMARK_INDEX_TO_ML_KIT_NAME.items():
                        lm = landmarks[idx]
                        frame_out[name] = {
                            "x": lm.x * frame_width,
                            "y": lm.y * frame_height,
                            # MediaPipe documents z as using "roughly the same
                            # scale as x", depth relative to the hip midpoint, so
                            # it's scaled by frame_width like x rather than
                            # zeroed. This matters a lot for a front-on camera:
                            # a squat's knee travel is mostly in depth from that
                            # angle, and MathUtils.calculateAngleFromCoordinates
                            # falls back to a 2D-only angle whenever all three
                            # z's read as flat (_hasReliableZCoordinates) -- an
                            # earlier version of this script zeroed z "to be
                            # safe", which silently forced that 2D fallback and
                            # made a genuinely deep front-facing squat measure as
                            # shallow (117-140 degrees instead of the true
                            # 35-90 degree range). Don't repeat that.
                            "z": lm.z * frame_width,
                            "likelihood": lm.visibility,
                        }
                    frames_out.append(frame_out)
            frame_index += 1

    cap.release()
    return frames_out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument(
        "--sample-fps",
        type=float,
        default=30.0,
        help=(
            "Frames per second to sample from the source video (default: 30, "
            "i.e. effectively every frame for a 30fps clip). Sampling too "
            "coarsely can miss the true bottom of a fast rep -- 10fps missed "
            "the deepest instant of 2 out of 5 reps in one clip during this "
            "pipeline's own testing, undercounting real reps that clearly hit "
            "depth. Only lower this for a very long clip where file size "
            "matters more than catching every rep's true extremum."
        ),
    )
    args = parser.parse_args()

    if not MODEL_PATH.exists():
        print(f"Missing model bundle at {MODEL_PATH}. See the module docstring "
              "for the download command.", file=sys.stderr)
        sys.exit(1)

    frames = extract(args.video, args.sample_fps)
    if not frames:
        print(f"No poses detected in {args.video} -- check the clip.", file=sys.stderr)
        sys.exit(1)

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(frames, indent=2))
    print(f"Wrote {len(frames)} frames to {args.output_json}")


if __name__ == "__main__":
    main()
