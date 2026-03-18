import asyncio
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 400, "height": 800})
        
        # Navigate to Flutter app
        await page.goto("http://localhost:57677")
        
        # Wait for canvas to be fully drawn
        await page.wait_for_selector("canvas", state="attached", timeout=60000)
        await asyncio.sleep(5)  # Wait for app to render and load animations
        
        # Dashboard screenshot
        await page.screenshot(path="dashboard.png")
        print("Captured dashboard.png")
        
        # Click 3rd icon (Stats)
        x_3rd = int(400 * 5/8)
        y_bottom = 800 - 30
        await page.mouse.click(x_3rd, y_bottom)
        await asyncio.sleep(2)
        
        # Stats screenshot
        await page.screenshot(path="stats.png")
        print("Captured stats.png")
        
        # Click 4th icon (Profile)
        x_4th = int(400 * 7/8)
        await page.mouse.click(x_4th, y_bottom)
        await asyncio.sleep(2)
        
        # Profile screenshot
        await page.screenshot(path="profile.png")
        print("Captured profile.png")
        
        await browser.close()

asyncio.run(main())
