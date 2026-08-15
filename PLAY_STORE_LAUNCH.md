# Play Store launch pack

Everything needed for the Google Play listing, in one place. Written for the
first production submission of `com.formanalyzer.app`.

---

## 1. Blockers still outstanding

| # | Item | Who can fix it |
|---|------|----------------|
| 1 | ~~Privacy policy URL is unreachable.~~ **Fixed 2026-08-15.** | — |
| 2 | **Screenshots** must be captured on a real device. | You (needs a phone) |
| 3 | **Fonts are fetched at runtime** from `fonts.gstatic.com` on first launch. | Optional, see §6 |
| 4 | **Data Safety must declare a Device ID** — ML Kit registers one. | You, at form-fill time — see §3a |

### 1a. The privacy policy URL — resolved

The redirect wasn't a `form_analyzer` setting at all: the custom domain
`jt-website.me` was configured on the **`CoderJT-Elite.github.io`** repo (the
personal-site repo), which GitHub applies account-wide — so `form_analyzer`'s
project page inherited the redirect even though it had no custom domain of its
own. That domain's DNS didn't point at GitHub (`104.219.250.37` /
`2.59.170.20`, not GitHub Pages IPs), so the redirect led nowhere and TLS failed.

Fixed by clearing the custom domain on `CoderJT-Elite.github.io` (Settings →
Pages → Custom domain). Checked every other repo on the account first — none of
them had `jt-website.me` set, so this was the only place it needed removing.
`https://coderjt-elite.github.io/form_analyzer/privacy.html` now returns `200`
directly, no redirect, and matches `AppConstants.privacyPolicyUrl` as-is —
nothing to change in the app.

**Verify before submitting** by opening the URL in a private browser window.

---

## 2. Store listing copy

**App name** (30 char max)
```
Form Analyzer
```

**Short description** (80 char max)
```
Real-time form feedback for your workouts, using just your phone camera.
```

**Full description** (4000 char max)
```
Form Analyzer watches you train and tells you what to fix — while you are still
mid-set, not afterwards.

Prop your phone against a wall, pick an exercise, and start moving. Form Analyzer
tracks your body through the camera, counts your reps, and coaches you out loud
when your depth, tempo or back position slips.

EVERYTHING HAPPENS ON YOUR PHONE
No account. No sign-up. Your camera feed is analysed on the device and thrown
away frame by frame — no photo or video is ever recorded, saved or uploaded.
Your workout history is stored on your phone, not on a server, and we never
receive it.

COACHING THAT SOUNDS LIKE A PERSON
Cues are prioritised, spaced out, and varied, so you get "sink a bit lower"
rather than the same word repeated at you every second. Persistent mistakes
escalate to more specific advice. Clean reps get credit.

WHAT IT WATCHES FOR
• Depth and range of motion, with how far short you actually were
• Back position and safety warnings on squats
• Tempo — whether you are lowering under control or just dropping
• Left/right imbalance
• Hip position on planks and holds

TEN EXERCISES
Squats, push-ups, lunges, overhead press, plank, glute bridge, sit-ups,
jumping jacks, wall sit, and side plank.

AFTER EVERY SET
A breakdown of each individual rep, your best and weakest rep, average lowering
time, the single thing most worth fixing, and how you compare to last time.

YOUR HISTORY STAYS YOURS
Workouts are stored on your device. Back them up to a file whenever you want,
and restore them on a new phone.

Form Analyzer gives automated feedback and is not medical advice. Check with a
doctor before starting a new exercise programme, and stop if you feel pain.
```

**Category:** Health & Fitness
**Tags:** fitness, workout, exercise, form, personal trainer
**Contact email:** (see §7 — decide which address to publish)

---

## 3. Data safety form

**Read §3a first — the app is not quite "collects nothing".**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** — one item, see below |
| Data type | **Device or other IDs** |
| Collected or shared? | Collected (by Google's ML Kit SDK, not by us) |
| Purpose | App functionality |
| Is it required or optional? | Required |
| Is it encrypted in transit? | **Yes** (HTTPS) |
| Can users request deletion? | No — the identifier is random, not tied to a user, and is removed on uninstall |

Notes if Play asks you to justify:

- **Camera**: used for real-time on-device pose detection only. Frames are held
  in memory for a single inference and discarded. Nothing is recorded or
  transmitted.
- **Photos/videos**: none accessed, created, or stored.
- **App activity / fitness info**: workout history is stored locally in
  `shared_preferences`. It is not collected by the developer, because there is no
  server. Android's own backup may copy it to the user's Google account under
  the user's settings — this is Google's backup, not developer collection.
- **No** analytics, advertising, or crash-reporting SDK is present.

### 3a. What ML Kit does on the network

Verified by reading logcat from a real install, not assumed. On first launch
`google_mlkit_pose_detection` does two things over the network, before any
workout starts:

1. Registers a randomly generated **Firebase installation ID** with Google.
2. Fetches its own remote configuration from
   `firebaseremoteconfig.googleapis.com`.

Both are Google's SDK acting on its own behalf. No camera imagery, workout data,
or personal information is involved, and the pose models themselves
(`pose_person_detector_f16.tflite`, `pose_landmark_detector_lite_f16_inf.tflite`)
load from local storage — inference is genuinely on-device.

This is why `INTERNET` cannot be stripped from the manifest, and it is why the
Data Safety answer above is "yes" rather than "no". Play requires you to declare
data collected by third-party SDKs as if it were your own. An installation ID is
a **Device or other ID**. Declaring it costs nothing; *failing* to declare it is
the kind of mismatch that gets an app suspended after launch, which is far worse
than a checkbox.

The privacy policy at `web/privacy.html` describes this in its "Data sharing"
section. Keep the two consistent — reviewers compare them.

**Permissions declared in the release build:** `CAMERA`, plus `INTERNET`,
`ACCESS_NETWORK_STATE` and `WAKE_LOCK` merged in by the ML Kit and TTS
libraries. `RECORD_AUDIO`, `READ_EXTERNAL_STORAGE`, `RECEIVE_BOOT_COMPLETED` and
`FOREGROUND_SERVICE` are explicitly removed in the manifest so the listing does
not claim a microphone it never uses.

---

## 4. Content rating

Answer the questionnaire honestly; this app has no violence, no sexual content,
no gambling, no user-generated content, and no ads. Expect **Everyone / PEGI 3**.

Health & Fitness apps get asked whether the app provides medical advice — answer
**no**, and note the in-app disclaimer shown on first launch.

---

## 4a. Testing on a device

### Emulator (already set up)

The AVD `Pixel_3a_API_33_x86_64` is configured to pipe the **laptop's webcam**
into the emulated camera, so pose detection works for real — stand in front of
the laptop and the app tracks you. The original AVD config is backed up
alongside it as `config.ini.bak`.

```bash
"$LOCALAPPDATA/Android/Sdk/emulator/emulator.exe" -avd Pixel_3a_API_33_x86_64 -camera-front webcam0
```

Then, from `app/`:

```bash
flutter run --target-platform android-x64
```

Good for: UI, navigation, the launcher icon, export/import, cue logic, and
confirming ML Kit loads. **Not** valid for frame-rate numbers or store
screenshots — an x86 emulator with a webcam says nothing about a real phone's
camera pipeline.

### Physical phone (needed for screenshots and perf)

1. On the phone: **Settings → About phone → tap Build number seven times.**
2. **Settings → System → Developer options → USB debugging → on.**
3. Plug into the laptop with a cable that carries data (many charge-only cables
   do not). Accept the "Allow USB debugging?" prompt on the phone.
4. `flutter devices` should now list it. If it does not, the cable or the
   OEM USB driver is the usual cause.
5. `flutter run --release` to install, or `flutter run --profile` for the
   DevTools frame chart.

Wireless alternative (Android 11+, no cable): enable **Wireless debugging** in
Developer options, tap *Pair device with pairing code*, then
`adb pair <ip>:<port>` followed by `adb connect <ip>:<port>`.

---

## 5. Screenshots (needs a physical device)

Play needs at least 2 phone screenshots; 4–8 is better. Requirements: PNG or
JPEG, 16:9 to 9:16 aspect, each side between 320px and 3840px.

The existing PNGs in the repo root are **400×800 and show empty zero states** —
too small and they sell nothing. Capture fresh ones with real data:

1. Build and install a release build on a phone.
2. Do a few real sets so History and Stats have content.
3. Capture: the live camera view mid-rep with the skeleton overlay and a cue on
   screen, the post-set report showing per-rep bars, the dashboard, and Stats.
4. `adb exec-out screencap -p > shot1.png` gives full device resolution.

A 1024×500 feature graphic is also required.

---

## 6. Optional: bundle the fonts

The app uses `google_fonts`, which downloads Outfit and Inter from
`fonts.gstatic.com` on first launch and caches them. No user data is involved —
the privacy policy is written to be accurate either way — but it means first-run
typography degrades without a connection.

To remove it: download the Outfit and Inter TTFs, put them in
`app/assets/fonts/`, declare them under `fonts:` in `pubspec.yaml`, replace the
`GoogleFonts.*` calls with the family names, and set
`GoogleFonts.config.allowRuntimeFetching = false` in `main.dart`.

---

## 7. Before you hit submit

- [ ] Privacy policy URL loads in a private browser window (§1a)
- [ ] Decide which contact email to publish. `web/privacy.html` currently lists
      your personal Gmail — Play requires a public contact address, so consider a
      dedicated one instead.
- [ ] **Back up the upload keystore off this machine.**
      `C:\Users\natuj\AndroidKeystores\form-analyzer-upload-key.jks` is the only
      copy. Lose it and you can never update this listing again. Put it in a
      password manager or encrypted cloud folder, along with the passwords.
- [ ] Install the release build on a real phone and confirm pose detection still
      works after minification, the new icon appears, and voice cues play.
- [ ] Bump `version:` in `pubspec.yaml` for every subsequent upload.

### Timeline note

New **personal** Play developer accounts must run a closed test with a minimum
number of testers (recently 12) for 14 continuous days before production access
is granted. Create the developer account and recruit testers **now** — that clock
runs in parallel with everything else. Confirm the current requirement in Play
Console, since Google has changed it more than once.

### About the bundle size

`app-release.aab` is ~81MB, but a large part of that is debug symbols and the
ProGuard mapping file, which Play uses for crash reports and never ships to
devices.

Measured, not estimated: a single-architecture release APK
(`flutter build apk --release --target-platform android-arm64`) is **58.4MB**.
That is close to what an arm64 phone actually downloads. Normal for an app
carrying on-device ML models, but if you want it smaller the pose models are the
place to look, not the Dart code.
