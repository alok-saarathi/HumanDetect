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
