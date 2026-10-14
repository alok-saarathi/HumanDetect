# 06 · Zero-shot open-vocabulary detection

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Candidates:**
- OWLv2 (`google/owlv2-base-patch16-ensemble`, Apache-2.0)
- Grounding DINO (`IDEA-Research/grounding-dino-tiny` / `-base`, Apache-2.0)

**Idea:** prompt with "a human face" or "a person", and reject the image if nothing scores above a threshold. This was the zero-shot approach in the first plan.

**Catches:** F1. Prompts like "a photo displayed on a screen" may weakly catch F2.

**Watch out:** these models are too heavy for a phone, so they're **server-only**.
- This is the first approach that needs our FastAPI service (D3) and the app's `remote` flavor.
- It's also a candidate labeler for distillation (13).

## Implementation (server 0.2.0)

**Status:** Stage 2 · Prototype, in the Tier 2 server and the app (tile 06). Needs the eval set to calibrate.

Code: `zero_shot_detection.py` (loaded by `server/humandetect_server/registry.py`). Rule and thresholds are in the file's docstring and in the app's Details page.

**Findings** (26-image smoke test: CC0/public-domain photos plus simulated screens, not an evaluation):

| Model | Correct at defaults | ROC-AUC |
|---|---|---|
| OWLv2 base/16 (used) | 22/26 | 0.67 |
| Grounding DINO tiny | 17/26 | 0.71 |

- **OWLv2 as a rejector:** all 5 scenes rejected (`NO_FACE`), 4 of 6 paintings/statues/mannequins flagged `NOT_REAL`.
- **False rejects:** `portrait.jpg` (the MediaPipe sample) scored a face of only 0.09 and was rejected; small faces on screens are rejected as `NO_FACE`, which is the right outcome for the wrong reason.
- **Grounding DINO** fired every context prompt on every image, even walls, so it is available only on the command line (`--param model=1`).
- **Rule change from the plan:** "printed photograph" boxes covering > 90 % of the frame are ignored, since they only say the image is a photo.
- **Verdict so far:** a weak standalone check. Its value is the labeled boxes (marks) for 13 (distillation), not the verdict.
