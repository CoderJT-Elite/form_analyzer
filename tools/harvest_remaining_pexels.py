"""
Harvest remaining exercises from Pexels with human-like delays.
"""
from playwright.sync_api import sync_playwright
from pathlib import Path
import urllib.parse
import time
import json

EXERCISES = [
    ('sidePlank', 'side plank exercise'),
    ('gluteBridge', 'glute bridge exercise'),
    ('wallSit', 'wall sit exercise'),
    ('overheadPress', 'shoulder press exercise'),
    ('lunge', 'lunges exercise'),
]

BASE_DIR = Path("tools/pose_fixture_footage")

def harvest_one(exercise: str, query: str):
    ex_dir = BASE_DIR / exercise
    ex_dir.mkdir(parents=True, exist_ok=True)
    
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
        
        url = f"https://www.pexels.com/search/videos/{urllib.parse.quote(query)}/"
        print(f"Searching {exercise}: {url}")
        page.goto(url)
        page.wait_for_timeout(3500)
        
        links = page.eval_on_selector_all(
            "a[href*='/video/']",
            "elements => elements.map(el => el.href)"
        )
        print(f"Found {len(links)} links")
        
        seen = set()
        cands = []
        for l in links:
            parts = urllib.parse.urlparse(l).path.strip('/').split('-')
            if len(parts) > 1 and parts[-1].isdigit():
                vid_id = parts[-1]
                slug = '-'.join(parts[:-1])
                if vid_id not in seen:
                    seen.add(vid_id)
                    cands.append((vid_id, slug))
        
        print(f"Unique videos for {exercise}: {len(cands)}")
        downloaded = 0
        for vid_id, slug in cands:
            if downloaded >= 2:
                break
            dest = ex_dir / f"{exercise}_pexels_{vid_id}.mp4"
            if dest.exists() and dest.stat().st_size > 100000:
                print(f"Already downloaded: {dest.name}")
                downloaded += 1
                continue
            
            print(f"Downloading [{vid_id}] {slug}...")
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
                download.save_as(str(dest))
                print(f"  Saved {dest.name} ({dest.stat().st_size} bytes)")
                downloaded += 1
            except Exception as e:
                print(f"  Download error: {e}")
            time.sleep(2)
            
        browser.close()

if __name__ == '__main__':
    for ex, q in EXERCISES:
        harvest_one(ex, q)
        time.sleep(3)
