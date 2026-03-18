# Form Analyzer - Quick Start Guide

## 🚀 Get Started in 3 Steps

### 1️⃣ Install Dependencies
```bash
flutter pub get
```

### 2️⃣ Connect Your Device
```bash
flutter devices
```

### 3️⃣ Run the App
```bash
flutter run
```

---

## 📱 Using the App

### First Launch
1. **Grant Camera Permission** when prompted
2. **Position yourself** so your full body is visible in the camera frame
3. **Start squatting!** The app will automatically count your reps

### Understanding the Interface

#### Top Bar
- **📱 Squat Analyzer** - App title
- **🔢 Rep Counter** - Shows your current rep count
- **🔄 Reset Button** - Tap to reset the counter

#### Bottom Bar
- **💬 Status Message** - Real-time coaching feedback
- **📐 Angle Display** - Shows your current knee angle

### Status Messages Explained

| Message | Meaning | What to Do |
|---------|---------|------------|
| 🔵 "Ready to squat" | Standing upright | Begin your squat |
| 🟢 "Good depth! Now stand up" | Proper squat depth achieved | Return to standing |
| 🟢 "Great squat!" | Rep completed | Continue to next rep |
| 🟠 "Go lower" | Not deep enough | Squat lower (70-90°) |
| 🟠 "Stand up" | In transition | Complete the movement |
| 🔴 "Too deep - maintain control" | Squatting too low | Safety warning |
| 🟠 "Move fully into the frame" | Body not visible | Adjust position |
| 🟠 "Keep your full body visible" | Partial body visible | Show full body |

### Visual Feedback

**Skeleton Colors:**
- **🟢 Green Lines** = Good form
- **🔴 Red Lines** = Needs improvement (while squatting)

**Angle Badge:**
- Appears near your knee joint
- Color matches your form quality
- Shows Hip-Knee-Ankle angle in degrees

---

## 🏋️ Perfect Squat Form

### Target Angles
- **Standing:** 160° or more (straight legs)
- **Squat Depth:** 70-90° (optimal range)
- **Too Deep:** Below 70° (safety concern)

### How Reps are Counted
1. Start standing (knee angle > 160°)
2. Squat down to proper depth (70-90°)
3. Return to standing (> 160°)
4. ✅ **Rep counted!**

**Note:** Partial squats (not reaching 70-90°) won't be counted.

---

## 📸 Camera Setup Tips

### Positioning
- **Distance:** 2-3 meters from camera
- **Height:** Camera at chest/shoulder level
- **Angle:** Facing the camera or side profile
- **Frame:** Head to feet fully visible

### Lighting
- ✅ Well-lit room (natural or artificial)
- ✅ Light in front of you (not behind)
- ❌ Avoid backlighting (windows behind you)
- ❌ Avoid very dark rooms

### Background
- ✅ Uncluttered background
- ✅ Contrasting colors (wear different color than background)
- ❌ Avoid crowded/busy backgrounds
- ❌ Avoid other people in frame (focuses on one person)

---

## 🎯 Workout Tips

### Best Practices
1. **Warm up** before starting
2. **Focus on form** over rep count
3. **Controlled movements** - no rushing
4. **Breathe properly** - inhale down, exhale up
5. **Watch the feedback** - adjust based on status messages

### Common Mistakes
- ❌ Not squatting deep enough → "Go lower"
- ❌ Squatting too deep → "Too deep - maintain control"
- ❌ Partial body visible → "Keep your full body visible"
- ❌ Moving out of frame → "Move fully into the frame"

---

## 🔧 Troubleshooting

### Camera Not Starting
**Solution 1:** Grant camera permission
- Android: Settings → Apps → Form Analyzer → Permissions → Camera
- iOS: Settings → Privacy → Camera → Enable for app

**Solution 2:** Restart the app
- Tap the "Try Again" button

### Pose Not Detected
**Check:**
- ✅ Full body visible (head to feet)
- ✅ Good lighting
- ✅ Standing 2-3 meters from camera
- ✅ Not wearing overly baggy clothes

### Reps Not Counting
**Ensure:**
- ✅ Starting from standing position (>160°)
- ✅ Reaching proper depth (70-90°)
- ✅ Returning to standing (>160°)
- ✅ Completing full movement

### App Freezes or Crashes
**Try:**
1. Close and restart the app
2. Restart your device
3. Check for app updates
4. Reinstall if issue persists

---

## 📊 Performance Tips

### Optimal Performance
- Use on physical device (better than emulator)
- Close other apps to free memory
- Ensure device isn't overheating
- Keep device charged (>20% battery)

### Expected Performance
- **Frame Rate:** 15-20 FPS
- **Latency:** <100ms for rep detection
- **Battery:** ~15-20% per 30 minutes

---

## 🔒 Privacy & Security

### Your Data
- ✅ **All processing on-device** (no cloud/server)
- ✅ **No video recording** (live stream only)
- ✅ **No image storage** (frames discarded after processing)
- ✅ **No data transmission** (completely offline)

### Permissions Used
- **Camera:** Required for pose detection
- **No other permissions needed**

---

## 💡 Pro Tips

1. **Mirror Mode:** Use front camera to see yourself while exercising
2. **Side Angle:** Side profile often gives better angle detection
3. **Contrasting Outfit:** Wear clothes that contrast with background
4. **Consistency:** Use same setup (position, lighting) for each session
5. **Reset Between Sets:** Use reset button between workout sets

---

## 📞 Support

### Need Help?
- Check the [Testing Guide](TESTING_GUIDE.md) for detailed testing
- Review [Deployment Guide](DEPLOYMENT_GUIDE.md) for technical setup
- Check [README](README.md) for architecture details

### Found a Bug?
Please report with:
- Device model & OS version
- Steps to reproduce
- Screenshots if possible

---

## 🎉 Ready to Start!

**That's it!** You're ready to track your squats with AI-powered form analysis.

### Quick Reminder
1. Full body in frame ✅
2. Good lighting ✅
3. 2-3 meters away ✅
4. Start squatting! 💪

---

**Version:** 1.0.0  
**Last Updated:** March 6, 2026

