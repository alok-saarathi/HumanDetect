# 10 · Frozen embeddings + linear probe

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**What it is:** dataset-based. It needs labeled images from the dataset track.

**Idea:**
1. Turn each image into a vector with a pretrained open backbone: DINOv2-small (Apache-2.0), SigLIP 2 (Apache-2.0) or TinyCLIP (MIT).
2. Train logistic regression, a tiny MLP or kNN on a few hundred labeled images per class, using scikit-learn (BSD-3).

**Catches:** whatever our labels cover: F1, F2, F3 and F5.

**Why it's the first dataset-based approach:** it trains in minutes. With a TinyCLIP backbone, it reuses 02's phone export.
