"""
Harvest real stock exercise footage from Pexels using Playwright stealth.
Downloads 2-3 clips per exercise across diverse camera angles and conditions.
"""
from playwright.sync_api import sync_playwright
from pathlib import Path
import urllib.parse
import time
import json

EXERCISE_SEARCHES = {
    'overheadPress': ['overhead press', 'dumbbell shoulder press'],
    'plank': ['plank exercise', 'forearm plank'],
    'gluteBridge': ['glute bridge', 'hip thrust'],
    'situp': ['sit ups', 'crunches workout'],
    'jumpingJack': ['jumping jacks', 'jumping jack exercise'],
    'wallSit': ['wall sit', 'wall squat'],
    'sidePlank': ['side plank', 'side plank exercise'],
    'lunge': ['lunges workout', 'walking lunges'],
    'pushup': ['push ups exercise', 'pushups workout'],
    'squat': ['bodyweight squats', 'squats workout'],
}

BASE_FOOTAGE_DIR = Path("tools/pose_fixture_footage")

def get_pexels_videos_for_query(page, query: str, limit: int = 3):
    url = f"https://www.pexels.com/search/videos/{urllib.parse.quote(query)}/"
    print(f"Navigating to {url}...")
    page.goto(url)
    page.wait_for_timeout(3000)
    
    # Get video page links
    links = page.eval_on_selector_all(
        "a[href*='/video/']",
        "elements => elements.map(el => el.href)"
    )
    # Deduplicate video page links
    video_pages = []
    seen_ids = set()
    for l in links:
        m = urllib.parse.urlparse(l)
        parts = m.path.strip('/').split('-')
        if len(parts) > 1 and parts[-1].isdigit():
            vid_id = parts[-1]
            if vid_id not in seen_ids:
                seen_ids.add(vid_id)
                video_pages.append((vid_id, l))
    print(f"Query '{query}' found {len(video_pages)} distinct video pages.")
    return video_pages[:limit]

def download_pexels_clip(context, page, video_page_url: str, dest_path: Path):
    if dest_path.exists() and dest_path.stat().st_size > 100000:
        print(f"Already exists: {dest_path.name}")
        return True
    
    page.goto(video_page_url)
    page.wait_for_timeout(2500)
    
    # Find direct video CDN link
    try:
        canva_elements = page.query_selector_all("a[href*='file-url=']")
        if canva_elements:
            canva_link = canva_elements[0].get_attribute("href")
            parsed = urllib.parse.urlparse(canva_link)
            qs = urllib.parse.parse_qs(parsed.query)
            if 'file-url' in qs:
                cdn_url = qs['file-url'][0]
                print(f"Fetching CDN: {cdn_url}...")
                res = context.request.get(cdn_url)
                if res.status == 200:
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    dest_path.write_bytes(res.body())
                    print(f"Saved {dest_path.name} ({len(res.body())} bytes)")
                    return True

        # Fallback: check download buttons
        dl_elements = page.query_selector_all("a[href*='/download/video/']")
        if dl_elements:
            dl_url = dl_elements[0].get_attribute("href")
            print(f"Trying download URL {dl_url}...")
            with page.expect_download(timeout=10000) as download_info:
                dl_elements[0].click(force=True)
            download = download_info.value
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            download.save_as(str(dest_path))
            print(f"Saved via download to {dest_path.name} ({dest_path.stat().st_size} bytes)")
            return True
    except Exception as e:
        print(f"Error downloading {video_page_url}: {e}")
    return False

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        context = browser.new_context(
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
        )
        page = context.new_page()
        
        for exercise, queries in EXERCISE_SEARCHES.items():
            print(f"\n==========================================")
            print(f"Harvesting for {exercise}...")
            ex_dir = BASE_FOOTAGE_DIR / exercise
            ex_dir.mkdir(parents=True, exist_ok=True)
            
            candidates = []
            for q in queries:
                c = get_pexels_videos_for_query(page, q, limit=2)
                candidates.extend(c)
                time.sleep(1)
            
            downloaded = 0
            for vid_id, v_url in candidates:
                if downloaded >= 2:
                    break
                dest = ex_dir / f"{exercise}_pexels_{vid_id}.mp4"
                ok = download_pexels_clip(context, page, v_url, dest)
                if ok:
                    downloaded += 1
                time.sleep(1)
            print(f"Completed {exercise}: {downloaded} clips downloaded.")
            
        browser.close()

if __name__ == '__main__':
    main()
