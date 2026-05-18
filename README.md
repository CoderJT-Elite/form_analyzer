# Form Analyzer | Elite Biomechanics for All

Democratizing sports science for under-resourced communities with 3D vector-based biomechanics.
Powered by Flutter, Google ML Kit (BlazePose), and high-fidelity 3D Vector Math.

## 📁 Repository Structure

- **/app**: The core Flutter mobile application source code.
- **/web**: Canonical high-conversion landing page and marketing site (GitHub Pages deployment source).

## 🚀 Deployment Guide

This repository is structured for seamless delivery:

### 1. Initialize GitHub
Execute these commands in your local terminal:
```bash
git init
git add .
git commit -m "chore: initial structural reorganization + landing page"
# Replace with your actual repository URL
git remote add origin https://github.com/YOUR_USERNAME/form_analyzer.git
git push -u origin main
```

### 2. Enable GitHub Pages
1. Navigate to your repository on **GitHub.com**.
2. Go to **Settings** > **Pages**.
3. Under **Build and deployment** > **Source**, select **GitHub Actions**.
4. Push to `main` to trigger `.github/workflows/static.yml`, which deploys the `web/` directory.
5. Your landing page will be available at `https://YOUR_USERNAME.github.io/form_analyzer/`.
6. The repository root `index.html` redirects to `/web/` to keep one canonical landing implementation.

## 🔒 Privacy & Release Readiness

- Camera frames are processed on-device for live form analysis.
- Workout history is stored locally using SharedPreferences.
- Voice coaching and haptic feedback can be toggled in **Profile → Settings**.

### Quality checklist before release

From `/home/runner/work/form_analyzer/form_analyzer/app`:

```bash
flutter analyze
flutter test
```

---
&copy; 2026 Form Analyzer Biomechanics Lab.
Validation: IEEE ISEC 2026 Submission Peer-Review.
