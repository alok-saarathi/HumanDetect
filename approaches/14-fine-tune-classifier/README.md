# 14 · Fine-tune a lightweight classifier (all fake types)

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**What it is:** dataset-based, and the toughest approach.

**Candidates:** MobileNetV3, EfficientNet-Lite and MobileViT through `timm`. The code is Apache-2.0; check the license tag of each pretrained weight file.

**Classes:** `live`, `no_human`, `recaptured`, `screenshot`, `not_real`.
- `not_real` examples come from CC0 cartoons and illustrations, plus real flagged cases.
- AI-generated faces are added only if production shows they occur, and only from generators whose license allows it.

**Needs:**
- A few thousand labeled images (from the dataset track, plus labels from 09 or 13).
- Augmentation for lighting, blur and JPEG artifacts.

**Export:** LiteRT with INT8 quantization, run in flavor `a14`.
