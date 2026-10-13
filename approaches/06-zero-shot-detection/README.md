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
