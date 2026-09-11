"""
Batch extraction of MediaPipe pose landmark sequences from all gathered stock footage.
Extracts at source frame rate, preserving real Z depth.
"""
import sys
import json
from pathlib import Path
import subprocess

MODEL_PATH = Path("tools/pose_fixture_footage/models/pose_landmarker_full.task")
FOOTAGE_DIR = Path("tools/pose_fixture_footage")
FIXTURES_DIR = Path("app/test/fixtures/pose_sequences")

def extract_all():
    if not MODEL_PATH.exists():
        print(f"Error: Model not found at {MODEL_PATH}")
        sys.exit(1)
    
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    
    # Find all mp4 files
    mp4_files = sorted(FOOTAGE_DIR.glob("**/*.mp4"))
    print(f"Found {len(mp4_files)} mp4 videos to process.")
    
    success_count = 0
    for mp4 in mp4_files:
        json_name = f"{mp4.stem}.json"
        out_json = FIXTURES_DIR / json_name
        
        if out_json.exists() and out_json.stat().st_size > 10000:
            print(f"Fixture already exists: {out_json.name} ({out_json.stat().st_size} bytes)")
            success_count += 1
            continue
        
        print(f"\nExtracting {mp4.name} -> {out_json.name}...")
        cmd = [
            sys.executable,
            "tools/extract_pose_fixtures.py",
            str(mp4),
            str(out_json),
            "--sample-fps", "100"  # Ensure source frame rate (stride = 1)
        ]
        
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(f"  {res.stdout.strip()}")
            success_count += 1
        except subprocess.CalledProcessError as e:
            print(f"  Extraction failed for {mp4.name}:\n  {e.stderr}")
            # If no poses detected or corrupted, remove partial output
            if out_json.exists():
                out_json.unlink()
        except Exception as e:
            print(f"  Unexpected error: {e}")
            
    print(f"\nDone! Extracted {success_count} / {len(mp4_files)} fixtures successfully.")

if __name__ == '__main__':
    extract_all()
