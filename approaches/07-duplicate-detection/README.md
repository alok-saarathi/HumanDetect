# 07 · Duplicate and reuse detection

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Idea:** catch the same photo being submitted again, for the same or a different customer.
- **Exact or near-exact copies:** perceptual hashes (pHash, dHash) through `imagehash` (BSD-2).
- **Re-shot or edited copies:** DINOv2 image embeddings (Apache-2.0), searched with FAISS (MIT).

**Catches:** F4. It also surfaces repeat offenders.

**On hold: same-face detection.** Catching the same *face* across different photos needs a face-recognition model. Most open face-recognition weights were trained on withdrawn or restricted datasets (e.g. MS-Celeb-1M), so this waits until a cleanly licensed model turns up.

**Watch out:** runs server-side and needs an index of past uploads, which raises data-retention questions.
