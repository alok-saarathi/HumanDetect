# 07 · Duplicate and reuse detection

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Idea:** catch the same photo being submitted again, for the same or a different customer.
- **Exact or near-exact copies:** perceptual hashes (pHash, dHash) through `imagehash` (BSD-2).
- **Re-shot or edited copies:** DINOv2 image embeddings (Apache-2.0), searched with FAISS (MIT).

**Catches:** F4. It also surfaces repeat offenders.

**On hold: same-face detection.** Catching the same *face* across different photos needs a face-recognition model. Most open face-recognition weights were trained on withdrawn or restricted datasets (e.g. MS-Celeb-1M), so this waits until a cleanly licensed model turns up.

**Watch out:** runs server-side and needs an index of past uploads, which raises data-retention questions.

## Implementation (server 0.2.0)

**Status:** Stage 2 · Prototype, in the Tier 2 server and the app (tile 07).

Code: `duplicates.py` (class `DuplicateCheck`). Index: `server/data/duplicate_index.npz` (pHash bits, DINOv2 embeddings, ids, times; git-ignored). New photos are added after they pass; duplicates are not re-added. `POST /v1/approaches/07/reset` clears it.

**Calibration** (13 public-domain photos × 7 edits, 78 different-photo pairs):

| Same photo after | pHash bits differing | DINOv2 similarity |
|---|---|---|
| JPEG q40 | 0–10 | 0.84–1.00 |
| resize to 40 % | 0–6 | 0.97–1.00 |
| brightness +25 % | 0–4 | 0.98–1.00 |
| rotate 4° | 6–24 | 0.92–0.98 |
| screenshot frame | 4–22 | 0.85–0.98 |
| crop to 80 % | 12–26 | 0.87–0.96 |
| mirror | 28–34 | 0.82–0.99 |
| **different photos** | **20–40** | **−0.13–0.60** |

Defaults: copy if pHash ≤ 10 bits; re-shot if similarity ≥ 0.85. There is a wide gap between the worst different-photo pair (0.60) and the worst edit (0.82), so the thresholds are conservative. They come from synthetic edits and must be re-checked against real resubmissions.

**Open:** retention policy for the fingerprint index; same-face matching stays on hold.
