# 11 · One-class / anomaly detection

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**What it is:** dataset-based, but it only needs genuine photos.

**Idea:** learn what genuine captures look like and flag everything else.
- **Methods:** kNN or Mahalanobis distance on 10's embeddings, or PatchCore-style models.
- **Why it helps:** genuine photos are plentiful, while fakes are rare and varied.

**Watch out:**
- Threshold tuning is hard.
- Genuine but unusual photos (night shots, odd angles) get flagged.
