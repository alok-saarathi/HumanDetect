# Third-party license register

Every model, dataset, package and tool must be listed here **before** first use. The rules are in [plan.md §2](plan.md#2-ground-rules):
- **Allowed:** permissive open licenses only.
- **Not allowed:** non-commercial, research-only, copyleft in shipped code, proprietary, or unconfirmed.

**Confirmed** = someone read the license in the **official** source (model card, repo LICENSE file, package metadata) and wrote the date and the source. Until then a row stays `to confirm` and must not ship.

## Shipped in the lab app (0.1.1)

| Item | Type | License | Used by | Confirmed | Source |
|---|---|---|---|---|---|
| MediaPipe BlazeFace short-range (`blaze_face_short_range.tflite`, float16 v1) | model | Apache-2.0 | 01, 05 | 2026-10-14 | Google model card PDF ("Licensed under Apache License, Version 2.0"); file pinned by SHA-256 in `app/tool/fetch_models.sh` |
| MediaPipe Face Mesh V2 (`face_landmarks_detector.tflite`, from Face Landmarker float16 v1) | model | Apache-2.0 | 05 | 2026-10-14 | Google model card PDF "MediaPipe FaceMesh" (Apache License 2.0); pinned by SHA-256 |
| TinyCLIP ViT-39M/16 Text-19M YFCC15M (`wkcn/...@07a4b0bc`) | model | MIT | 02 | 2026-10-14 | Hugging Face model card metadata `license: mit`; trained on YFCC15M (Creative Commons photos) |
| `camera` 0.12.1 (+ `camera_android_camerax`) | Dart package | BSD-3 | app | 2026-10-14 | LICENSE file in package |
| `tflite_flutter` 0.12.1 | Dart package | Apache-2.0 | app | 2026-10-14 | LICENSE file in package |
| LiteRT Android runtime (`com.google.ai.edge.litert:litert`, `litert-gpu`) | native library | Apache-2.0 | app (via tflite_flutter) | to confirm | google-ai-edge/LiteRT |
| `image` 4.12.0 | Dart package | MIT | app | 2026-10-14 | LICENSE file in package |
| `device_info_plus` 13.3.0 | Dart package | BSD-3 | 03 | 2026-10-14 | LICENSE file in package |
| `crypto` 3.0.7 | Dart package | BSD-3 | 03 | 2026-10-14 | LICENSE file in package |
| `exif` 3.3.0 | Dart package | MIT | 04 | 2026-10-14 | LICENSE file in package |
| `geolocator_android` 5.1.1 + `geolocator_platform_interface` 4.4.0 | Dart package | MIT | 03 | 2026-10-14 | LICENSE files. Used instead of `geolocator`, whose Linux implementation pulls in MPL-2.0 packages (`dbus`, `geoclue`, `gsettings`) |
| All transitive Dart packages | Dart packages | MIT / BSD / Apache | app | 2026-10-14 | LICENSE files scanned for every hosted dependency; no copyleft remains |
| Flutter SDK 3.47.6 | toolchain | BSD-3 | app | to confirm | flutter/flutter |

## Laptop tooling (not shipped)

| Item | Type | License | Used by | Confirmed | Source |
|---|---|---|---|---|---|
| `mediapipe` 1.1.0 (Python) | package | Apache-2.0 | 01, 05 reference checks | 2026-10-14 | package metadata |
| `ai-edge-litert` 2.2.0 | package | Apache-2.0 | run .tflite in Python | 2026-10-14 | package metadata |
| `litert-torch` 0.9.4, `litert-converter` 0.4.0 | package | Apache-2.0 | 02 export | 2026-10-14 | package metadata |
| `ai-edge-quantizer` 0.9.0 | package | Apache-2.0 | 02 int8 quantization | 2026-10-14 | package metadata |
| `torch` 2.13 | package | Apache-2.0 (per package metadata) | 02 | 2026-10-14 | package metadata |
| `torchao`, `jax` (pulled in by litert-torch) | package | jax Apache-2.0; torchao to confirm | 02 export | partly | package metadata (torchao has none) |
| `transformers` 5.19, `huggingface-hub`, `safetensors`, `tokenizers` | package | Apache-2.0 | 02 | 2026-10-14 | package metadata |
| `opencv-python-headless` 5.0 | package | Apache-2.0 | reference code | 2026-10-14 | package metadata |
| numpy, Pillow, PyYAML | package | BSD-3 (+ permissive) / MIT-CMU / MIT | all | 2026-10-14 | package metadata |
| `google/owlv2-base-patch16-ensemble`, `IDEA-Research/grounding-dino-tiny` | model | Apache-2.0 | 06 (server) | 2026-10-14 | Hugging Face model card metadata; pinned commits in `approaches/06-zero-shot-detection/zero_shot_detection.py` |
| `facebook/dinov2-small` | model | Apache-2.0 | 07 (server) | 2026-10-14 | Hugging Face model card metadata |
| `PekingU/rtdetr_v2_r18vd`, `ustc-community/dfine-small-coco` | model | Apache-2.0 | 08 (server) | 2026-10-14 | Hugging Face model card metadata; pure `transformers`, no remote code |
| `HuggingFaceTB/SmolVLM2-500M-Video-Instruct` | model | Apache-2.0 | 09 (server) | 2026-10-14 | Hugging Face model card metadata |
| `fastapi` 0.143 (MIT), `uvicorn` 0.54 (BSD-3), `starlette` (BSD-3), `pydantic` (MIT), `anyio` (MIT) | server package | permissive | server | 2026-10-14 | package metadata |
| `imagehash` 4.3.2 (BSD-2), `PyWavelets` (MIT/BSD-3), `scipy` (BSD) | package | permissive | 07 | 2026-10-14 | package metadata |
| `torchvision` 0.28 | package | BSD | 09 | 2026-10-14 | package metadata |
| `httpx`, `pytest` | test package | BSD-3 / MIT | server tests | to confirm | dev only |
| `num2words` 0.5.14 | package | LGPL (weak copyleft) | 09 (server only) | 2026-10-14 | **Accepted 2026-10-15 as a server-side exception.** SmolVLM's processor imports it. Used unmodified as a library on our own server and never shipped in the app, so no source obligations reach app users. Revisit if the server software is ever distributed to others |
| SigLIP 2 base (`google/siglip2-base-patch32-256`, `-patch16-224`) | model | Apache-2.0 | 02 comparison only | 2026-10-14 | Hugging Face model card metadata |
| TinyCLIP ViT-8M/16 YFCC, ViT-40M/32 and ViT-61M/32 LAION | model | MIT | 02 comparison only | 2026-10-14 | Hugging Face model card metadata |
| Wikimedia Commons test images (CC0 / public domain only) | data | CC0 / PD | smoke tests, scratch only, not committed | per file | license field read from the Commons API for each file |

## Allowed candidates for later approaches

| Item | Type | License | Used by | Confirmed | Source / notes |
|---|---|---|---|---|---|
| YuNet | model | MIT | 01 (deferred) | to confirm | LICENSE in opencv_zoo `models/face_detection_yunet` |
| OpenAI CLIP ViT-B/32 | model | MIT | reference only, never shipped | to confirm | model card says deployed use is out of scope |
| RF-DETR; EfficientDet-Lite, SSD-MobileNet; Florence-2; Qwen2.5-VL-7B-Instruct | model | Apache-2.0 / MIT | 08, 09 (not used yet) | to confirm | **that Qwen size only**: other sizes differ |
| `timm` + weights | package / model | Apache-2.0 (code) | 12, 14 | to confirm | check each weight file's license tag |
| scikit-learn, `imagehash` (BSD-2), FAISS (MIT), FastAPI (MIT), ONNX Runtime (MIT), Label Studio (Apache-2.0) | package / tool | permissive | various | to confirm | |
| `autodistill` core | package | Apache-2.0 | 13 | to confirm | its YOLO student plugins are AGPL: don't use them |
| Open Images V7 | dataset | annotations CC BY 4.0; images listed as CC BY 2.0 | dataset (train/dev only) | to confirm | Google doesn't warrant image licenses: keep each image's URL and attribution |
| Unsplash Lite | dataset | Unsplash dataset terms | dataset (train only) | to confirm | training for internal use allowed; not redistributable; never published |

## Excluded

| Item | Why | Instead |
|---|---|---|
| Google ML Kit (face detection, GenAI / Gemini Nano) | closed-source SDK | MediaPipe BlazeFace (01) |
| MobileCLIP / MobileCLIP2 weights | Apple research-only license (AMLR) | TinyCLIP, SigLIP 2 (02) |
| Silent-Face-Anti-Spoofing / MiniFASNet and its ports (e.g. face-antispoof-onnx) | weights trained on CelebA-Spoof (non-commercial); upstream license unconfirmed | our own anti-spoof classifier (12) |
| InsightFace weights (RetinaFace, SCRFD, ArcFace), InspireFace SDK | non-commercial, or a commercial license | BlazeFace, YuNet |
| Ultralytics YOLO (v5, v8, 11, …) and YOLO-face ports | AGPL-3.0 | RT-DETR, D-FINE, RF-DETR (08) |
| `geolocator` (app-facing package) | pulls in MPL-2.0 Linux packages (`dbus`, `geoclue`, `gsettings`) | `geolocator_android` directly |
| CelebA, CelebA-Spoof, FFHQ | non-commercial | our own dataset |
| Idiap Replay-Attack / Replay-Mobile | restricted access | our own dataset |
| Places365 | non-commercial research and education | Open Images, our own captures |
| Unsplash Full dataset | non-commercial | Unsplash Lite (training only) |
| Hugging Face models with no clear license (AI-face detectors, moiré detectors, …) | unlicensed | train on our own data (12, 14) |
| Face-recognition weights trained on MS-Celeb-1M and similar withdrawn datasets | dataset withdrawn or restricted | same-face dedup on hold (07) |
| Hosted LLM APIs (Gemini, GPT, Claude) | proprietary; sends customer data out | self-hosted open VLMs (09) |
| Commercial liveness/KYC vendors (HyperVerge, Signzy, IDfy, AWS Rekognition, Azure Face) | proprietary paid APIs | our own models |
| Google Play Integrity API | proprietary service | optional; team decision in 03 |
