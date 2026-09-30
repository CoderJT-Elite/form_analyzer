"""Extract pose fixtures from an on-phone screen recording of the app itself.

Crops to the camera-preview region of the recording (below the rep HUD, above the
bottom controls) and samples at a fixed rate by presentation time, so the phone's
variable-frame-rate capture doesn't skew timing. Output matches
extract_pose_fixtures.py, so it loads through RecordedPoseFixtures.

    python tools/extract_live_test_fixtures.py recording.mp4 OUT_DIR --prefix live2 \
        squat=12,55 jumpingJack=104,132 ...
"""
from __future__ import annotations
import argparse, json
from pathlib import Path
import cv2, mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import PoseLandmarker, PoseLandmarkerOptions, RunningMode
from extract_pose_fixtures import LANDMARK_INDEX_TO_ML_KIT_NAME, MODEL_PATH

def extract_segment(cap, start, end, fps, top=0.16, bottom=0.82):
    cap.set(cv2.CAP_PROP_POS_MSEC, start * 1000)
    opts = PoseLandmarkerOptions(base_options=BaseOptions(model_asset_path=str(MODEL_PATH)),
                                 running_mode=RunningMode.VIDEO, num_poses=1)
    out, nxt, ts = [], start, 0
    with PoseLandmarker.create_from_options(opts) as lm:
        while True:
            t = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000
            if t > end: break
            ok, f = cap.read()
            if not ok: break
            if t < nxt: continue
            nxt += 1.0 / fps
            h, w = f.shape[:2]
            crop = f[int(h * top):int(h * bottom)]
            ch, cw = crop.shape[:2]
            ts += int(1000 / fps)
            img = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))
            res = lm.detect_for_video(img, ts)
            if not res.pose_landmarks: continue
            L = res.pose_landmarks[0]
            out.append({n: {"x": L[i].x * cw, "y": L[i].y * ch, "z": L[i].z * cw,
                            "likelihood": L[i].visibility}
                        for i, n in LANDMARK_INDEX_TO_ML_KIT_NAME.items()})
    return out

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path); ap.add_argument("out_dir", type=Path)
    ap.add_argument("--prefix", default="live"); ap.add_argument("--fps", type=float, default=15)
    ap.add_argument("segments", nargs="+", help="name=start,end (seconds)")
    a = ap.parse_args()
    cap = cv2.VideoCapture(str(a.video)); a.out_dir.mkdir(parents=True, exist_ok=True)
    for seg in a.segments:
        name, rng = seg.split("="); s, e = map(float, rng.split(","))
        frames = extract_segment(cap, s, e, a.fps)
        p = a.out_dir / f"{a.prefix}_{name}.json"
        p.write_text(json.dumps(frames, separators=(",", ":")))
        print(name, len(frames), "frames ->", p.name)
