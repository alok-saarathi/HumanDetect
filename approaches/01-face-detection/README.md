# 01 · Pretrained face detection

**Ladder position:** 1 of 15 (easiest)
**Status:** see [plan.md](../../plan.md)
**Build:** ~4 prompts
**In the app:** tile 01 of the lab app (versions `0.1.x`)

## Goal

Find out two things:
- Does an open, pretrained face detector, plus a few simple rules, reliably separate genuine customer captures from "no human" fakes (F1)?
- What does it cost to run on a phone?

The winner becomes gate 1 of the final pipeline (15). It also supplies the face crop for the anti-spoof classifier (12) and active liveness (05).

**Expected result:**
- It should catch F1 well.
- It should catch almost nothing in F2 (a screen or printout showing a person), F3 (a screenshot containing a face) or F5 (cartoon or AI face).

We measure those gaps anyway, so later approaches have a baseline to beat.

## Variants

| ID | Detector | Runs in | License |
|---|---|---|---|
| 01a | **MediaPipe BlazeFace** (short-range for selfies, full-range for back camera) | Python **and** Flutter: the same `.tflite` file in both | Apache-2.0 |
| 01b | **YuNet** (OpenCV Zoo) | Python; Flutter through ONNX Runtime only if it clearly beats 01a | MIT |
| 01c | **Haar cascade** (OpenCV) | Python only, as a floor baseline | Apache-2.0 / BSD |

The production check in Pravesh uses this same float16 file with only the confidence and size cutoffs (0.6 and 4%). Dominance and yaw stay lab rules. Phone, server, and APK size: [PRAVESH_FACE_CHECK.md](../../PRAVESH_FACE_CHECK.md).

**Why BlazeFace first:**
- It's the model family Google's closed ML Kit is built on, but released under Apache-2.0.
- We run the raw `.tflite` file with our own decoding code, written once in Python and once in Dart. The laptop numbers and phone numbers then come from identical logic.
- The `mediapipe` Python package serves only as a reference, to check that our decoder is right.

## Decision rule

Every variant feeds the same rule, so only the detector differs between them. Tune thresholds on the **dev** split only.

An image **passes** when all of these hold:
1. **Confidence:** at least one face has confidence ≥ `T_conf`.
2. **Size:** the largest face covers ≥ `A_min` of the image area. This rejects tiny faces on a poster or in the background.
3. **One clear subject:** if there are several faces, the largest is ≥ `R_dom` × the second largest.
4. **Pose:** the head is roughly frontal, with yaw estimated from the eye and nose keypoints within ±`P_max`°.

| Threshold | Sweep range |
|---|---|
| `T_conf` | 0.5–0.9 |
| `A_min` | 2–15 % |
| `R_dom` | 1.5–3 |
| `P_max` | 25–45° |

On failure, the check returns a reason code the app can show: `NO_FACE`, `LOW_CONFIDENCE`, `FACE_TOO_SMALL`, `NO_DOMINANT_FACE` or `FACE_NOT_FRONTAL`.

## Folder layout

```
approaches/01-face-detection/
  README.md              this plan, then findings
  detectors/
    blazeface.py         01a: LiteRT interpreter + our own decoder
    yunet.py             01b
    haar.py              01c
  rules.py               the decision rule, shared by every variant
  run_eval.py            one variant over data/eval → results/<variant>-<split>.csv
  download_models.sh     fetches pinned model files into models/ (git-ignored)
  notebooks/
    explore.ipynb        threshold sweeps, failure gallery
  results/
    summary.md           metrics and the chosen operating point
```

The app side lives at `app/lib/approaches/a01_face_detection/`. Its CSVs from the phone are copied into `results/`.

## Work plan

### Prompts (my part)
1. **Python prototype:**
   - Register the licenses in `THIRD_PARTY_LICENSES.md`.
   - `download_models.sh`.
   - The three detectors, with the BlazeFace decoder checked against `mediapipe`.
   - `rules.py` and `run_eval.py`, built on the shared harness (00).
2. **Evaluate:**
   - Sweep thresholds on dev, freeze them, and run once on test.
   - Break results down by capture condition: low light, front vs. back camera, spectacles, head coverings, elderly customers.
   - Build a failure gallery, then fill in `summary.md` and the scoreboard.
3. **App:**
   - Scaffold the Flutter app: the shared `HumanCheck` interface, capture and batch-eval screens, flavors and build script.
   - Add the BlazeFace check in Dart.
   - This prompt may spill into two, because it sets up the whole app.
4. **On-device:**
   - Compare the phone's CSV with Python's and fix any mismatch.
   - Build `humandetect-a01-0.1.0.apk` and record the decision.

### Needs from you
- [ ] Dataset v0, at least the `live/` and `no_human/` classes ([dataset/](../../dataset/README.md)). Other classes make the expected gaps measurable.
- [ ] Flutter SDK and Android SDK installed, before prompt 3.
- [ ] A low-end Android phone like the field team's, connected over USB with debugging on, before prompt 4.
- [ ] 2–3 testers who capture live and try to fool the APK.

## Exit criteria

These are placeholders until the business targets are agreed:
- Genuine reject ≤ 2 %
- F1 accept ≤ 2 %
- On-device p95 latency ≤ 150 ms on the lowest-spec field phone

**Expected verdict:** adopt as gate 1 and as the face cropper for 05 and 12, not as a standalone check.

## Risks

- **Field conditions.** These detectors were trained on public data and may struggle with our capture conditions: outdoor or dim light, older phones. That's why results are broken down by condition.
- **Face-size rule.** It may reject genuine photos taken from too far away. Check with field users how they actually frame the customer.
- **Decoder bugs.** A mistake in our BlazeFace decoder (anchors, NMS) would silently hurt accuracy. That's why we check it against the `mediapipe` reference.

## Resources

- MediaPipe Face Detector: https://developers.google.com/edge/mediapipe/solutions/vision/face_detector
- YuNet: https://huggingface.co/opencv/face_detection_yunet
- `tflite_flutter` (pub.dev, Apache-2.0)

## Implementation (lab app 0.1.0)

**Status:** Stage 2 · Prototype done, both in Python and in the app. Stage 3 waits for dataset v0; Stage 4 waits for a phone test.

| Part | Where |
|---|---|
| BlazeFace decoder (anchors, sigmoid, weighted NMS, letterbox removal) | `blazeface.py` → mirrored in `app/lib/approaches/a01_face_detection/blazeface.dart` |
| Decision rule (confidence, size, dominance, yaw) | `rules.py` → `face_rules.dart` |
| Check shown in the app (result rows, face boxes, tunable thresholds) | `face_detection_check.dart` |
| Check against Google's `mediapipe` | `verify_against_mediapipe.py IMAGE…` |
| Model file | `app/tool/fetch_models.sh` (pinned URL + SHA-256) |

**What changed from the plan:**
- **No raw-model Python dependency:** the model runs through `ai-edge-litert`, and our own decoder is used on both sides, so laptop and phone share identical logic.
- **Plain bilinear resize (no antialiasing):** the reference uses OpenCV-style resizing, matching what MediaPipe does. Pillow's smoothing changed the scores on small faces.
- **Rounding:** Python and Dart both round half up.
- **01b/01c not yet run:** YuNet and Haar are not implemented yet; they are only worth adding if BlazeFace underperforms on our eval set.
- **`run_eval.py` not written yet:** it needs the eval set and the shared harness (00).

## Findings

- **Decoder vs `mediapipe`:**
  - On the MediaPipe test portrait, its mirror and a no-face image: boxes within 1.6 % of image size, keypoints within 1.2 %.
  - On 22 CC0/public-domain images: same face count on 19. The 3 differences are borderline scores (0.33–0.58 vs 0.43–0.52) that the 0.6 confidence rule rejects anyway.
- **Behaviour on the sample images:** accepted faces in paintings, statues and mannequin heads. That's the expected weakness: 01 only answers "is there a face".
- **Parity:** Dart matches Python on synthetic inputs (`app/test/parity_test.dart`).
