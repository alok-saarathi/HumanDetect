# HumanDetect lab app (Flutter, Android)

One app with a grid of tiles, one tile per approach:
- **Tap a tile:** the camera opens with only that approach applied. Take a photo, see the verdict and why, go back, try the next tile.
- **Tap Details on a tile (or ⓘ on its camera screen):** opens that approach's page, covering how it works step by step, its components and their licenses, default thresholds, what it catches and misses, how we checked it, its limitations, and where the code lives.

It's a **test harness, not the production app**.

**Version 0.1.0** covers Tier 1, the approaches that need no training and run on the phone (plan.md §5).

| Tile | Approach | What runs on the phone | Expected to catch |
|---|---|---|---|
| 01 | Face detection | BlazeFace short-range (MediaPipe, Apache-2.0) + size, dominance and head-turn rules | F1 no human |
| 02 | Zero-shot | TinyCLIP ViT-39M/16 (MIT, int8) scored against 25 prompts in 5 buckets | F1, F5, part of F2/F3 |
| 03 | Capture integrity | no model: session nonce, freshness, real device, GPS with mock check, signed receipt | F3, traceability |
| 04 | Recapture forensics | no model: sharpness, glare, contrast, moiré spectrum, EXIF | part of F2, F3 |
| 05 | Active liveness | live video: BlazeFace + Face Mesh V2 (Apache-2.0), random blink and head-turn challenges | F2 prints and screens, F1, F3 |

**Open source only:** every package and model is listed with its license in [`../THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md).

## Install a ready build

Download `humandetect-lab-0.1.0.apk` from the repo's GitHub Releases (tag `lab-0.1.0`). Install it on an Android phone (Android 7.0 or newer), allowing "install unknown apps" for the browser or file manager when asked.

## Build it yourself

### 1. Toolchain (once per machine)
These are the versions this was built with:

| Tool | Version | Install (macOS) |
|---|---|---|
| Flutter | 3.47.6 (Dart 3.13) | `brew install --cask flutter` |
| JDK | 17 | `brew install openjdk@17` |
| Android SDK | platform 36, build-tools 36.x, NDK 28.2.13676358 | `brew install --cask android-commandlinetools`, then `sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.1.0" "ndk;28.2.13676358"` |

```
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools \
               --jdk-dir /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
flutter doctor
```

### 2. Model files
Model files are not in git, because they're large and generated. From the repo root:
```
app/tool/fetch_models.sh                       # BlazeFace + Face Mesh (pinned, SHA-256 checked)
uv sync --group models --group export          # Python deps for the export
uv run --group models --group export python approaches/02-zero-shot-clip/export_tinyclip.py
                                               # TinyCLIP image encoder (40 MB, int8) + prompt vectors
```
Afterwards `app/assets/models/` holds:
- `blaze_face_short_range.tflite`
- `face_landmarks_detector.tflite`
- `tinyclip_image_encoder.tflite`
- `tinyclip_prompts.json`

### 3. Build and install
```
cd app
flutter build apk --release --build-name 0.1.0 --build-number 1
mkdir -p builds && cp build/app/outputs/flutter-apk/app-release.apk builds/humandetect-lab-0.1.0.apk
adb install -r builds/humandetect-lab-0.1.0.apk      # or send the APK file to the phone
```
- **Signing:** release builds are signed with the debug key, which is fine for testers, not for the Play Store.
- **Distribution:** `builds/` is git-ignored. APKs are published as GitHub Releases tagged `lab-<version>`.
- **Version numbers:** `0.<tier>.<iteration>`, so `0.1.x` is the Tier 1 lab and `1.0.0` is reserved for a production candidate.

## Using it

- **Home:** 5 tiles. Each shows its number, what it checks, which fake types it should catch, and a **Details** button.
- **Photo tiles (01–04):**
  - Camera screen: the back camera by default, with a switch button. There's no gallery picker anywhere in the app.
  - Press the shutter to see the result: PASS/FAIL, the score, the reasons in plain words, the photo with face boxes and keypoints (01), the details behind the verdict, and timings.
  - ⓘ opens the approach's Details page.
  - The tune button opens sliders for every threshold. Changes apply to the next photo, and reset when you leave the screen.
- **05 Active liveness:**
  - Press **Start**. The app asks for a blink and a head turn to the left or right, in random order.
  - **Back camera:** the person holding the phone reads the instructions out.
  - **Front camera:** the person follows them on screen.
  - A debug line shows eye openness and head turn live, which helps tune thresholds.
- **Privacy:** photos stay in memory. The camera's temp file is deleted right after capture, and nothing is saved or uploaded.

## Code layout

```
lib/
  main.dart                         portrait-locked MaterialApp
  core/
    check.dart                      PhotoCheck interface, CheckResult, Tunable, reason texts
    image_ops.dart                  JPEG decode + EXIF orientation, bilinear resize, box downsample
    models.dart                     model asset paths, shared interpreters, tensor helpers
  approaches/
    registry.dart                   the grid tiles
    approach_details.dart           text behind each tile's Details page
    a01_face_detection/             blazeface.dart (decoder), face_rules.dart, face_detection_check.dart
    a02_zero_shot/                  zero_shot_check.dart (preprocess, prompt scoring)
    a03_capture_integrity/          capture_integrity_check.dart
    a04_forensics/                  forensics.dart (signals, FFT), forensics_check.dart
    a05_active_liveness/            frame_convert.dart (YUV -> RGB), face_mesh.dart,
                                    liveness_session.dart (state machine), active_liveness_screen.dart
  screens/
    home_screen.dart  approach_detail_screen.dart  photo_check_screen.dart
    result_screen.dart  tunables_sheet.dart
test/
  parity_test.dart                  Dart vs Python references on synthetic inputs, FFT vs DFT
  liveness_session_test.dart        challenge flow: pass, timeout, face lost, face switched, ...
  details_test.dart                 every tile has a Details page; layout fits a small phone
  fixtures/parity.json              made by tool/make_test_fixtures.py
tool/
  fetch_models.sh                   downloads pinned MediaPipe models
  make_test_fixtures.py             regenerates fixtures/parity.json from the Python references
```

**Adding an approach:**
1. Implement `PhotoCheck` (or write a screen, like 05).
2. Add its tile in `approaches/registry.dart` and its Details text in `approaches/approach_details.dart`.
3. Register any new model or package in `THIRD_PARTY_LICENSES.md` first.

## Tests

```
cd app && flutter test
```

- **Parity tests:** check that the Dart code computes what the Python reference code in `approaches/` computes. They cover resize, letterbox, BlazeFace decoding and NMS, face rules, CLIP preprocessing and scoring, forensic signals and the face-mesh crop.
- **No real images:** inputs are generated from a formula.
- **After changing a Python reference:** run `uv run --group models python app/tool/make_test_fixtures.py`.

## Known limitations

- **Not yet run on a phone.** Latency, the camera-frame rotation in 05, and EXIF from the camera plugin still need a first check on real devices. If 05 never finds a face while 01 does, suspect frame rotation (`frame_convert.dart`).
- **Thresholds are uncalibrated.** They're starting points from about 25 public test images, to be tuned on the dataset's dev split.
- **BlazeFace short-range** is designed for faces within about 2 m.
- **03 is local only.** Its nonce and signing key are generated on the phone. A real deployment issues them from the server and verifies the receipt there.
- **05 doesn't rotate the face crop for strongly tilted heads.** Landmarks are accurate for upright faces.
