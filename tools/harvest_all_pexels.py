"""
Comprehensive Pexels harvester to gather footage across all 10 exercises.
"""
from playwright.sync_api import sync_playwright
from pathlib import Path
import urllib.parse
import time
import json

TARGET_SEARCHES = {
    'plank': ['plank'],
    'sidePlank': ['side plank'],
    'gluteBridge': ['glute bridge', 'bridge exercise'],
    'situp': ['sit ups', 'crunches'],
    'jumpingJack': ['jumping jacks'],
    'wallSit': ['wall sit', 'wall squat'],
    'overheadPress': ['overhead press', 'shoulder press'],
    'lunge': ['lunges'],
    'pushup': ['push ups'],
    'squat': ['squats'],
}

BASE_FOOTAGE_DIR = Path("tools/pose_fixture_footage")

def harvest_all():
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        context = browser.new_context(
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            accept_downloads=True
        )
        page = context.new_page()
        
        manifest = {}

        for exercise, queries in TARGET_SEARCHES.items():
            ex_dir = BASE_FOOTAGE_DIR / exercise
            ex_dir.mkdir(parents=True, exist_ok=True)
            print(f"\n==========================================")
            print(f"Searching for {exercise}...")
            
            video_entries = []
            seen_ids = set()
            for q in queries:
                url = f"https://www.pexels.com/search/videos/{urllib.parse.quote(q)}/"
                try:
                    page.goto(url)
                    page.wait_for_timeout(2500)
                    links = page.eval_on_selector_all(
                        "a[href*='/video/']",
                        "elements => elements.map(el => el.href)"
                    )
                    for l in links:
                        m = urllib.parse.urlparse(l)
                        parts = m.path.strip('/').split('-')
                        if len(parts) > 1 and parts[-1].isdigit():
                            vid_id = parts[-1]
                            slug = '-'.join(parts[:-1])
                            if vid_id not in seen_ids:
                                seen_ids.add(vid_id)
                                video_entries.append((vid_id, slug, l))
                except Exception as e:
                    print(f"Error searching {q}: {e}")
                time.sleep(1)
            
            print(f"Found {len(video_entries)} candidate videos for {exercise}")
            
            downloaded = 0
            manifest[exercise] = []
            for vid_id, slug, v_url in video_entries:
                if downloaded >= 3:
                    break
                dest_file = ex_dir / f"{exercise}_pexels_{vid_id}.mp4"
                if dest_file.exists() and dest_file.stat().st_size > 100000:
                    print(f"  Already exists: {dest_file.name}")
                    manifest[exercise].append({
                        'id': vid_id,
                        'slug': slug,
                        'file': str(dest_file),
                        'size': dest_file.stat().st_size
                    })
                    downloaded += 1
                    continue
                
                print(f"  Downloading [{vid_id}] {slug}...")
                dl_url = f"https://www.pexels.com/download/video/{vid_id}/"
                try:
                    with page.expect_download(timeout=15000) as download_info:
                        try:
                            page.goto(dl_url)
                        except Exception as e:
                            if "Download is starting" in str(e) or "net::ERR_ABORTED" in str(e):
                                pass
                            else:
                                raise
                    download = download_info.value
                    download.save_as(str(dest_file))
                    print(f"    Saved {dest_file.name} ({dest_file.stat().st_size} bytes)")
                    manifest[exercise].append({
                        'id': vid_id,
                        'slug': slug,
                        'file': str(dest_file),
                        'size': dest_file.stat().st_size
                    })
                    downloaded += 1
                except Exception as e:
                    print(f"    Failed download for {vid_id}: {e}")
                time.sleep(1)
            
            print(f"Harvested {downloaded} clips for {exercise}.")
            
        Path("tools/harvested_clips_manifest.json").write_text(json.dumps(manifest, indent=2))
        print("\nWrote tools/harvested_clips_manifest.json")
        browser.close()

if __name__ == '__main__':
    harvest_all()
