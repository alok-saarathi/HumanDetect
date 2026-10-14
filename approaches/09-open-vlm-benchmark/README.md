# 09 · Self-hosted open VLM (benchmark and labeler)

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Idea:** run an open-weights vision-language model on our own machine and ask it: "Is this a live photo of a real person, not a screen, print or object? Answer in JSON." Because it's self-hosted, images never leave our machines.

**Candidates:**
- SmolVLM2 (Apache-2.0)
- Florence-2 (MIT)
- Qwen2.5-VL-7B-Instruct (Apache-2.0). Other Qwen sizes have different licenses, so check before switching.

**Roles:**
- **Accuracy ceiling:** shows how far a big general model gets on our eval set.
- **Labeler:** labels images for the Tier 3 training approaches.

**Not a production candidate:** too heavy for a per-upload check.

## Implementation (server 0.2.0)

**Status:** Stage 2 · Prototype, in the Tier 2 server and the app (tile 09).

Code: `vlm_judge.py` (class `VlmJudge`): SmolVLM2-500M, pinned commit, bf16 on the Apple GPU. A five-option multiple-choice question (real person / person on a screen / printed photo or ID / painting, statue, mannequin, cartoon / no person). The score is the model's probability of "A", read from the logits, not from generated text.

**Findings** (26-image smoke test, not an evaluation): **23/26 correct, ROC-AUC 0.92**, the best of Tier 2.
- All scenes, all 8 recaptures and all 6 not-real photos rejected, each with a sensible reason.
- It is also cautious about real people: 3 of 7 genuine photos rejected (person in front of a TV, crowded selfie, stylised portrait).
- 0.5–4 s per photo; the model is about 1 GB.

**Use:** accuracy ceiling to compare other approaches against, and a labeler for the training approaches (10–14). Not a production check.

**License flag:** the processor needs `num2words` (LGPL). See THIRD_PARTY_LICENSES.md.
