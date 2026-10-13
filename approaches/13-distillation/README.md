# 13 · Distill an open foundation model into a tiny model

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Idea:**
1. Let a big open model label large dumps of unlabeled photos. Candidates: SigLIP 2 (02), OWLv2 (06), or an open VLM (09).
2. Train 14's small classifier on those labels.

**Tooling:** `autodistill`'s core is Apache-2.0, but its YOLO student plugins are AGPL, so we use our own student.

**Watch out:** label noise from weak prompts carries straight into the student. Spot-check labels by hand.
