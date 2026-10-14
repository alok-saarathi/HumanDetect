# HumanDetect — Plan

This is the master tracker for every approach we try for validating customer photos.
- **Order:** we climb the ladder from the **easiest approach to the toughest**.
- **Licensing:** every piece is **open and license-clean** ([§2](#2-ground-rules)).
- **Our own dataset:** built in parallel from day one ([§4](#4-dataset-track)). It feeds evaluation for every approach and the training approaches at the top of the ladder.

**How to keep this file current:**
- **Checkbox:** tick an approach's box once it reaches **Stage 5 · Decided**.
- **Stage label:** keep it current as work moves.
- **Decisions:** log every one in [§10](#10-decision-log).

## 1. Problem

Field users of our Android app must photograph the customer and upload the picture. Some fake it by photographing something random. We want an automated check that each upload is a **real, live photo of a human, taken at that moment**, and the check has to run in the Android app or behind it.

The original brief and the first plan are kept in [Appendix A](#appendix-a--original-brief-and-first-plan).

### What counts as "fake"

| ID | Fake type | Examples | Typically caught by |
|---|---|---|---|
| F1 | No human at all | wall, table, floor, landscape, blank or dark frame | face detection (01) |
| F2 | Recaptured human | photo of a printed photo, of a phone or laptop screen, of a poster or ID card | anti-spoof classifier (12), active liveness (05), forensics (04) |
| F3 | Screenshot or forwarded still | screenshot of a WhatsApp or social photo, a photo of a screen saved to the gallery | zero-shot (02), forensics pixel signals (04). A gallery photo of a real person is a valid input for 01, 02 and 04; it is not a fake by itself. "Taken just now" (03, 05) applies only to an in-app camera capture |
| F4 | Reused photo | same image submitted for several customers | duplicate search (07) |
| F5 | Synthetic or non-real human | AI-generated face, cartoon, mannequin, statue | zero-shot (02), fine-tuned classifier (14) |
| F6 | Wrong person | a real, live person who isn't the customer | **out of scope for now**: needs a face match against the KYC/ID photo |

## 2. Ground rules

The repo is public, and everything we use or ship must be legally clean.

**Allowed**
- Code, models and datasets under permissive open licenses: MIT, Apache-2.0, BSD, CC0, or CC BY with attribution.
- Images we create ourselves, with signed consent from everyone photographed.

**Not allowed**
- Proprietary SDKs, closed services and paid APIs, even free ones.
- Anything licensed non-commercial or research-only. That includes model weights trained mainly on such datasets.
- Copyleft licenses (GPL, AGPL) in anything we ship.
- Models or datasets with no stated license, or a license we can't confirm from the official source.
- Customer photos in the repo, or sent to any third party.

**How it's enforced:** every model, dataset and package gets a row in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) before first use, with its license and source link. That file also lists what we've excluded and why. The headline exclusions:

| Excluded | Why | What we use instead |
|---|---|---|
| Google ML Kit | closed-source SDK | MediaPipe BlazeFace (Apache-2.0): the same model family, and the same file runs in Python and in the app |
| MobileCLIP weights | Apple research-only license | TinyCLIP (MIT), SigLIP 2 (Apache-2.0) |
| Pretrained anti-spoof models (Silent-Face / MiniFASNet and its ports) | trained on CelebA-Spoof, which is non-commercial | our own anti-spoof classifier (12) |
| Public anti-spoof and face datasets (CelebA, CelebA-Spoof, FFHQ, Replay-Attack, …) | non-commercial or restricted | our own dataset (§4) |
| Ultralytics YOLO | AGPL-3.0 | RT-DETR, D-FINE, RF-DETR (Apache-2.0) |
| InsightFace weights | non-commercial | BlazeFace, YuNet |
| Hosted LLM APIs, Gemini Nano, commercial liveness vendors | proprietary; some send customer data out | self-hosted open VLMs (09); our own models |

## 3. How we work

### Repository layout
```
HumanDetect/
├── plan.md                      this tracker
├── THIRD_PARTY_LICENSES.md      license register: allowed and excluded
├── pyproject.toml, uv.lock      Python environment (uv) shared by everything
├── dataset/                     D · building our own open dataset
├── evaluation/                  00 · shared scoring harness
├── approaches/
│   ├── 01-face-detection/       one folder per approach: code, notebooks, results, findings
│   └── …                        through 15-hybrid-pipeline/
├── app/                         Flutter lab app: a tile per approach
├── server/                      FastAPI service for the Tier 2 approaches (06-09)
└── data/                        the images themselves (git-ignored)
```

### How long things take
- **Writing the code** for one approach takes about **3–5 chat prompts**.
- **Elapsed time** depends on things only people can do:
  - Taking and labeling photos.
  - Installing the Flutter SDK and Android SDK.
  - Testing on real phones.
- Each approach README splits its plan into **prompts** and **needs from you**.

### Stage legend

| Stage | Meaning | Done when |
|---|---|---|
| 0 · Not started | — | — |
| 1 · Research | candidates shortlisted, licenses confirmed and registered | rows in `THIRD_PARTY_LICENSES.md` |
| 2 · Prototype | runs end to end on a handful of images | code in the approach folder |
| 3 · Evaluated | scored on the shared eval set | row filled in the [scoreboard](#9-evaluation) |
| 4 · Deployable | running in its app flavor (or on a server), latency measured | numbers in the scoreboard |
| 5 · Decided | Adopt, Combine or Drop, with the reason | entry in the [decision log](#10-decision-log) |

## 4. Dataset track

**Why our own dataset:** usable public data for this problem barely exists. Almost every anti-spoofing and face dataset is non-commercial, so a dataset we build ourselves is the main asset. It does two jobs:
- **Evaluation:** every approach gets scored on its test split.
- **Training:** the dataset-based approaches (10–14) learn from it.

**Sources:**
1. **Own captures:** staged sessions with consenting volunteers.
   - Genuine photos, and recaptures of those photos on many screens and printouts.
   - Taken with the field team's actual phones.
2. **Production data:** fakes ops has flagged, plus consented genuine captures. Private: never committed, never published.
3. **Open-licensed public images:** Open Images V7, Wikimedia Commons (CC0 or CC BY only), Unsplash Lite (training only, not redistributable). Used mostly for `no_human` scenes and variety.
4. **Generated fakes:** code that turns sources 1 and 3 into simulated fakes:
   - screenshots (phone and chat UI frames)
   - moiré
   - printouts (halftone, paper texture, glare)
5. **Auto-labeling:** open models (02, 06, 09) pre-label images, and people confirm the labels in Label Studio (Apache-2.0).

Full plan: [dataset/README.md](dataset/README.md).

- [ ] **D · Our own open dataset** · `Stage 0 · Not started`
  - [ ] Consent form for staged captures (check with legal)
  - [ ] Tooling: manifest with license fields, validator, license-filtered Open Images downloader, fake generator
  - [ ] **v0:** one staged capture session, enough to start 01 and 02
  - [ ] **v1:** adds flagged production fakes; test split frozen
  - [ ] **Training set:** a few thousand labeled images for 10–14

## 5. Approach ladder — tracker

**Shared foundations (start now)**
- [ ] **D · Our own open dataset** · see [§4](#4-dataset-track) · [dataset/](dataset/)
- [ ] **00 · Shared evaluation harness** · `Stage 0 · Not started` · [evaluation/](evaluation/) · ~1 prompt

**Tier 1: no training, runs on the phone**
- [ ] **01 · Pretrained face detection (BlazeFace)** · `Stage 2 · Prototype ✓ in lab app 0.1.0` · [folder](approaches/01-face-detection/) · next: eval set v0, phone test
- [ ] **02 · Zero-shot image classification (TinyCLIP-39M; SigLIP 2 reference)** · `Stage 2 · Prototype ✓ in lab app 0.1.0` · [folder](approaches/02-zero-shot-clip/) · next: eval set v0, prompt tuning, phone test
- [ ] **03 · Harden the capture flow (non-ML)** · `Stage 2 · Prototype ✓ in lab app 0.1.0` · [folder](approaches/03-capture-hardening/) · next: phone test, server design
- [ ] **04 · Recapture and metadata forensics (rules)** · `Stage 2 · Prototype ✓ in lab app 0.1.0` · [folder](approaches/04-metadata-forensics/) · next: calibrate on eval set
- [ ] **05 · Active liveness (blink, head turn)** · `Stage 2 · Prototype ✓ in lab app 0.1.0` · [folder](approaches/05-active-liveness/) · next: phone test, field trial

**Tier 2: no training, runs on a server**
- [ ] **06 · Zero-shot open-vocabulary detection (OWLv2)** · `Stage 2 · Prototype ✓ server + tile 06` · [folder](approaches/06-zero-shot-detection/) · weak alone (AUC 0.67 on smoke set); Grounding DINO dropped
- [ ] **07 · Duplicate and reuse detection (pHash, DINOv2)** · `Stage 2 · Prototype ✓ server + tile 07` · [folder](approaches/07-duplicate-detection/) · next: retention policy, real resubmissions
- [ ] **08 · Open deep detectors (RT-DETRv2, D-FINE)** · `Stage 2 · Prototype ✓ server + tile 08` · [folder](approaches/08-deep-detectors/) · good person detector, blind to prints/screens
- [ ] **09 · Self-hosted open VLM as benchmark and labeler (SmolVLM2-500M)** · `Stage 2 · Prototype ✓ server + tile 09` · [folder](approaches/09-open-vlm-benchmark/) · best on smoke set (AUC 0.92); `num2words` LGPL needs a decision

**Tier 3: dataset-based, trained on our own data (toughest)**
- [ ] **10 · Frozen embeddings + linear probe** · `Stage 0 · Not started` · [folder](approaches/10-embedding-probe/)
- [ ] **11 · One-class / anomaly detection** · `Stage 0 · Not started` · [folder](approaches/11-one-class-anomaly/)
- [ ] **12 · Anti-spoof classifier (our own passive liveness)** · `Stage 0 · Not started` · [folder](approaches/12-anti-spoof-classifier/)
- [ ] **13 · Distill an open foundation model into a tiny model** · `Stage 0 · Not started` · [folder](approaches/13-distillation/)
- [ ] **14 · Fine-tune a lightweight classifier (all fake types)** · `Stage 0 · Not started` · [folder](approaches/14-fine-tune-classifier/)

**Final**
- [ ] **15 · Hybrid tiered pipeline (target architecture)** · `Stage 0 · Not started` · [folder](approaches/15-hybrid-pipeline/)

**Why this order**
- **01 and 02** need no training and no server. Each runs in the phone build with one model file.
- **03–05** add product changes and new capture UX.
- **06–09** need a server or a historical image index.
- **10–14** need the dataset track to have produced labeled data. 09 and 13 help label it.

## 6. Stages per approach

### 00 · Shared evaluation harness · [details](evaluation/README.md)
- [ ] Dataset loader, metrics, and a report built from results CSVs
- [ ] Results CSV validator (also used for CSVs from the phone)

### 01 · Pretrained face detection · [full plan](approaches/01-face-detection/README.md)
- [x] 1 · Research: licenses registered, model files pinned
- [x] 2 · Prototype: BlazeFace with our own decoder (matches mediapipe), shared decision rule, tile 01 in the lab app. YuNet/Haar deferred
- [ ] 3 · Evaluated: threshold sweep on dev, single run on test, breakdown by capture condition
- [ ] 4 · Deployable: on-device batch eval, latency on the lowest-spec phone (APK built: lab 0.1.0)
- [ ] 5 · Decided

### 02 · Zero-shot image classification · [full plan](approaches/02-zero-shot-clip/README.md)
- [x] 1 · Research: licenses registered (MobileCLIP excluded), export path working (litert-torch), prompt set v0
- [x] 2 · Prototype: 5 open models compared on a smoke-test set; TinyCLIP-39M exported (int8, parity 0.9993), tile 02 in the lab app
- [ ] 3 · Evaluated: prompt iteration on dev, single run on test, combination with 01's gate
- [ ] 4 · Deployable: on-device batch eval, latency on the lowest-spec phone (APK built: lab 0.1.0)
- [ ] 5 · Decided

### 03 · Harden the capture flow
- [ ] Audit the production app: can users pick from the gallery? What metadata is sent?
- [ ] Spec the required capture metadata and server-side checks
- [x] Prototype in the lab app (tile 03): nonce, freshness, real device, GPS + mock check, signed receipt
- [ ] Ship in production and measure the drop in fake uploads
- [ ] Verdict

### 04 · Recapture and metadata forensics
- [ ] Inventory which metadata reaches the server today
- [x] Prototype EXIF, sharpness, glare, contrast and moiré rules (Python + tile 04)
- [ ] Evaluate on `screenshot/` and `recaptured/`
- [ ] Verdict

### 05 · Active liveness
- [x] Pick the challenges: blink + one random head turn
- [x] Prototype in the lab app (tile 05) with BlazeFace + Face Mesh V2; landmarks match mediapipe
- [ ] Field test with a few agents: completion time and failure rate
- [ ] Verdict

### 06 · Zero-shot open-vocabulary detection
- [ ] Notebook using the `transformers` zero-shot-object-detection pipeline
- [ ] Sweep prompts and thresholds on dev; evaluate on test
- [ ] First FastAPI service (D3), plus the app's `remote` flavor; measure latency
- [ ] Verdict: production model, labeler for 13, or drop

### 07 · Duplicate and reuse detection
- [ ] pHash prototype over a historical upload dump
- [ ] DINOv2 near-duplicate search; tune the match threshold
- [ ] Size the index; agree on a retention policy
- [ ] Verdict

### 08 · Open deep detectors
- [ ] Run on the cases 01 got wrong
- [ ] Verdict

### 09 · Self-hosted open VLM
- [ ] Run on the eval set as an accuracy ceiling
- [ ] Decide whether to use it as a labeler for 10–14
- [ ] Verdict

### 10 · Frozen embeddings + linear probe
- [ ] Embedding extraction for 2–3 backbones
- [ ] Train probes; cross-validate on the training split
- [ ] Evaluate on the frozen test split
- [ ] Verdict

### 11 · One-class / anomaly detection
- [ ] Prototype on 10's embeddings
- [ ] Evaluate genuine-reject rate vs. catch rate
- [ ] Verdict

### 12 · Anti-spoof classifier
- [ ] Recapture data ready (dataset track)
- [ ] Train on face crops from 01; evaluate on `live/` vs. `recaptured/`
- [ ] Export to LiteRT; flavor `a12`; on-device latency
- [ ] Verdict

### 13 · Distill an open foundation model
- [ ] Choose the labeler (from 02, 06 or 09 results)
- [ ] Auto-label the dump; spot-check 200 labels by hand
- [ ] Train the student; evaluate
- [ ] Verdict

### 14 · Fine-tune a lightweight classifier
- [ ] Training set ready (dataset track, plus labels from 09 or 13)
- [ ] Baseline fine-tune; track per-fake-type metrics
- [ ] Quantize and export to LiteRT; check the accuracy drop
- [ ] Flavor `a14`; on-device latency
- [ ] Verdict

### 15 · Hybrid tiered pipeline
- [ ] Pick the components from the earlier verdicts
- [ ] Integrate and run end to end on the eval set; flavor `a15`
- [ ] **Shadow mode** in production: log decisions without blocking, and compare with ops review
- [ ] Enforce, with a clear "retake" message for the user
- [ ] Monitor genuine-reject complaints and fake-accept audits

## 7. Flutter test app

The app lives in [`app/`](app/README.md). **Lab 0.2.0 is built locally** (not yet released; 0.1.2 is the last release, tag `lab-0.1.2`): adds a Tier 2 section whose tiles (06–09) send the photo to the FastAPI server in [`server/`](server/README.md). Gallery upload is accepted on tiles 01, 02 and 04 (since 0.1.1); 0.1.2 reopens the camera after leaving the app (e.g. after the gallery picker) and fixes tile 04 on tiny images.
- **One app with a grid:** one tile per Tier 1 approach (01–05).
  - Tap a tile: the camera opens with only that approach applied, then a result screen shows the verdict, reasons, photo marks and timings. Tiles 01, 02 and 04 also accept one photo from the Android gallery picker. Tiles 03 and 05 stay camera-only.
  - **Details** on each tile (and ⓘ on each camera screen): how the approach works step by step, its components and licenses, thresholds, what it catches and misses, how it was checked, limitations and code paths.
  - **Thresholds** are adjustable live from each camera screen.
- **Version** `0.<tier>.<iteration>`: `0.1.x` is the Tier 1 lab. This replaced the earlier plan of one Android flavor per approach.
- **Tests:** 28 Flutter tests. Dart matches the Python references on synthetic inputs; the liveness state machine, the gallery-source rules and the Details pages are covered too.
- **Still to add:** a batch-eval screen (run a check over a folder on the phone, export results CSV) once the eval set exists.

**Open source only:** all Flutter packages must be MIT, BSD or Apache. Unused permissions that plugins merge in (microphone, storage, phone state) are stripped.

## 8. Deployment options — tracker

**Choosing between them:**
- **Offline:** does it work if field agents are in low-connectivity areas?
- **Footprint:** APK size and RAM.
- **Latency:** on the lowest-spec field phone.
- **Tamper resistance:** can a modified app skip the check?
- **Cost per check.**
- **Update speed:** a server model can change without an app release.

- [ ] **D1 · On-device LiteRT** through `tflite_flutter` (Apache-2.0) · `Stage 0 · Not started` · used by 01, 02, 12, 14
- [ ] **D2 · On-device ONNX Runtime** (MIT) · `Stage 0 · Not started` · only if a model won't convert to LiteRT
- [ ] **D3 · Self-hosted FastAPI service** (MIT) · `Stage 0 · Not started` · first built in 06
- [ ] **D4 · Hosting for D3:** our own VM or a managed container platform · `Stage 0 · Not started` · cost and data-residency decision
- [ ] **D5 · Hybrid: on-device pre-check + server verdict (recommended)** · `Stage 0 · Not started` · decided in 15

**D1 conversion:** PyTorch → LiteRT through `ai-edge-torch`, or ONNX → LiteRT through `onnx2tf`. INT8 or FP16 quantization.

**D3 shape:** Docker, ONNX Runtime, and `POST /v1/validate` returning `{is_valid, reasons[], scores{}}`. Add auth, rate limits and an audit log.

## 9. Evaluation

The results CSV format and metrics are in [`evaluation/README.md`](evaluation/README.md). Every approach reports here, so this table is the scoreboard.

| Approach · variant | Runtime | F1 accept ↓ | F2 accept ↓ | F3 accept ↓ | F5 accept ↓ | Genuine reject ↓ | p95 latency | Size | Notes |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

## 10. Decision log

| Date | Approach | Decision | Reason |
|---|---|---|---|
| 2026-10-14 | all | Open, license-clean components only; ML Kit, MobileCLIP, pretrained anti-spoof models and non-commercial datasets excluded | repo is public; no license risk |
| 2026-10-14 | app | One lab app with a grid of approaches instead of one flavor per approach | easier side-by-side testing on one phone |
| 2026-10-14 | 02 | Ship TinyCLIP ViT-39M/16 (YFCC15M, MIT, int8 40 MB); keep SigLIP 2 as the server/teacher reference | 8M too weak on the smoke test (AUC 0.90 vs 0.93); SigLIP 2 best (0.98) but 95M params; avoid LAION-trained variants |
| 2026-10-14 | 06–09 | Tier 2 runs on one FastAPI server (D3); apps send photos over the LAN, judged in memory | models too big for phones; photos stay on our own machine |
| 2026-10-14 | 09 | SmolVLM2-500M kept as benchmark/labeler only; `num2words` (LGPL) flagged | server-side, not shipped; awaiting decision |
| 2026-10-14 | 01 | BlazeFace short-range with our own decoder; YuNet/Haar deferred | decoder matches mediapipe; extra detectors only if BlazeFace underperforms on our eval set |
| 2026-10-14 | app | Gallery is a valid still-photo input for 01, 02 and 04. 03 and 05 stay camera-only. 04's EXIF clock is not a hard fail on a gallery file | a real customer photo may be shot in-app or chosen from the gallery; a file cannot prove it was taken just now |

---

## Appendix A — Original brief and first plan

**Brief:**
> We have a software application where the user has to click a photograph of the customer and then upload, but sometimes the user tries to fake it up and they just simply click any random photograph and then they upload. So I want to add a check or a model-based validation where the ML model or the DL model will simply check for whether the image consists of the image or upload of a real human. [...] Consider all the approaches like there must be some already trained or already implemented projects or models on Kaggle or Hugging Face [...] Will it be a standard approach of collecting images, creating the dataset, and then so on, or shall we use some zero-shot approach or shall we fine-tune a particular model or any other approach?

**First plan (summary):** the problem sits between human detection and anti-spoofing/liveness. Each idea is mapped to the current ladder:

- **Phase 1, existing models:**
  - zero-shot detection with OWL-ViT or Grounding DINO → **06**
  - pretrained passive-liveness models → **excluded** (non-commercial training data), replaced by **12**
- **Phase 2, strategy options:**
  - zero-shot pipeline → **02 / 06**
  - fine-tuned CNN/ViT → **14**
  - hybrid rules + model pipeline → **15**
- **Phase 3, custom training:** collect "live" and "fake" photos and fine-tune MobileNetV3 or EfficientNet-B0 → **D, 14**
- **Next steps it suggested:**
  - test a zero-shot baseline → **02 / 06**
  - define the main cheating pattern → **D**
