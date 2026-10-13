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
