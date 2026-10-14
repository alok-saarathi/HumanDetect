# 08 · Open deep detectors

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**When to use it:** only if 01's recall isn't good enough.

**Candidates** (all Apache-2.0, detecting the COCO "person" class):
- **Phone-sized:** EfficientDet-Lite and SSD-MobileNet from the TensorFlow Model Garden.
- **Server:** RT-DETR, D-FINE and RF-DETR.

**Excluded under the ground rules:**
- Ultralytics YOLO (AGPL-3.0).
- InsightFace weights: RetinaFace and SCRFD are non-commercial.

**Resources**
- https://github.com/lyuwenyu/RT-DETR
- https://github.com/Peterande/D-FINE
- https://github.com/roboflow/rf-detr

## Implementation (server 0.2.0)

**Status:** Stage 2 · Prototype, in the Tier 2 server and the app (tile 08).

Code: `detectors.py` (class `DeepDetector`): RT-DETRv2 R18 by default, D-FINE small with `model=1`. Both load through plain `transformers` at pinned commits, no remote code.

**Rule:** largest confident person must be ≥ 8 % of the photo and ≥ 2× the second person, and not mostly (≥ 70 %) inside a detected `tvmonitor`, `laptop`, `cell phone` or `book` box. "Book" is included because phone frames and printed photos are often detected as books.

**Findings** (26-image smoke test, not an evaluation):

| Model | Correct | ROC-AUC |
|---|---|---|
| RT-DETRv2 R18 | 17/26 | 0.77 |
| D-FINE small | 15/26 | 0.87 |

- All 7 genuine photos passed and all 5 scenes were rejected, with both models.
- **Weakness:** people in paintings pass (3 of 6 not-real), and only 1–2 of 8 recaptures were caught: the detector must first recognise the screen or print as an object.
- D-FINE ranks better (higher AUC) but its verdicts at these thresholds are worse; thresholds need the eval set.
- 100 ms per photo on an M4 GPU after loading.
