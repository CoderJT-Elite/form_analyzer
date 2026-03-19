import asyncio
import json
from playwright.async_api import async_playwright

# Pre-seed data that matches the app's StorageService format
SEED_DATA = {
    "routines": json.dumps([
        {
            "id": "1000000",
            "name": "Power Athlete",
            "exercises": ["squat"]
        },
        {
            "id": "1000001",
            "name": "Morning Strength",
            "exercises": ["squat"]
        }
    ]),
    "workout_sessions": json.dumps([
        {"id": "s1", "routineId": "1000000", "routineName": "Power Athlete",
         "date": "2026-03-17T20:00:00.000", "totalReps": 24,
         "formRating": 4.7, "exerciseResults": [
             {"exerciseType": "squat", "reps": 24, "formRating": 4.7}
         ]},
        {"id": "s2", "routineId": "1000000", "routineName": "Power Athlete",
         "date": "2026-03-15T19:30:00.000", "totalReps": 18,
         "formRating": 4.2, "exerciseResults": [
             {"exerciseType": "squat", "reps": 18, "formRating": 4.2}
         ]},
        {"id": "s3", "routineId": "1000001", "routineName": "Morning Strength",
         "date": "2026-03-13T08:00:00.000", "totalReps": 30,
         "formRating": 4.9, "exerciseResults": [
             {"exerciseType": "squat", "reps": 30, "formRating": 4.9}
         ]},
    ]),
    "user_profile": json.dumps({
        "name": "JT",
        "email": "jt@formanalyzer.app"
    })
}

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        
        # --- Dashboard screenshot ---
        page = await browser.new_page(viewport={"width": 400, "height": 800})
        await page.goto("http://localhost:57677")
        await page.wait_for_selector("canvas", state="attached", timeout=60000)
        await asyncio.sleep(4)
        
        # Inject seed data into localStorage and reload
        for key, value in SEED_DATA.items():
            await page.evaluate(f"localStorage.setItem({json.dumps(key)}, {json.dumps(value)})")
        
        await page.reload()
        await page.wait_for_selector("canvas", state="attached", timeout=60000)
        await asyncio.sleep(4)
        
        await page.screenshot(path="dashboard.png")
        print("✅ Captured dashboard.png")
        
        # --- Stats screenshot --- click Stats (3rd nav item)
        # Find the canvas and click the stats nav icon approximately
        bbox = await page.locator("canvas").bounding_box()
        nav_y = bbox["y"] + bbox["height"] - 30
        stats_x = bbox["x"] + bbox["width"] * 0.625
        await page.mouse.click(stats_x, nav_y)
        await asyncio.sleep(2)
        
        await page.screenshot(path="stats.png")
        print("✅ Captured stats.png")
        
        # --- Profile screenshot --- click Profile (4th nav item)
        profile_x = bbox["x"] + bbox["width"] * 0.875
        await page.mouse.click(profile_x, nav_y)
        await asyncio.sleep(2)
        
        await page.screenshot(path="profile.png")
        print("✅ Captured profile.png")
        
        await browser.close()

asyncio.run(main())
