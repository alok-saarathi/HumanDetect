# 15 · Hybrid tiered pipeline

The lab pipeline. Cheap checks run first. A failure on the phone stops the run, and that photo is not sent to the server. The slow judge runs last.

**Capture** (taken in the app):

1. **05** blink and head turn (BlazeFace + Face Mesh). This also covers face detection, so 01 is not a separate step.
2. **03** live, fresh capture on a real phone. Gallery uploads skip this.
3. **04** blur, glare, contrast, moiré, EXIF.
4. **02** TinyCLIP-39M.
5. **Server**, only if 02 (and the earlier phone steps) passed.

**Upload** (gallery): skip 05 and 03. Start at **04 → 02 → server**.

**Server:**

| Order | Approach | Role |
|---|---|---|
| 1 | **08** RT-DETRv2 + D-FINE | One clear person. Hard stop. |
| 2 | **07** pHash + DINOv2 | Already submitted? Hard stop. Stored only if the pipeline accepts. |
| 3 | **06** OWLv2 | Face, and not a screen or a painting. A note, not the only reject. |
| 4 | **09** SmolVLM2-500M | Final judge. |

Each step can be switched off in the app (`15 · Pipeline` on the home screen) or, for the server stages, with `POST /v1/pipeline?skip=06,09`.

**10–14** stay out until there is a labeled dataset.

Code: `app/lib/approaches/a15_pipeline/` and `server/humandetect_server/pipeline.py`.
