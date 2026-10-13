# 12 · Anti-spoof classifier (our own passive liveness)

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**Why it exists:** there's no pretrained anti-spoofing model we can use.
- The popular ones (Silent-Face / MiniFASNet and their ONNX ports) were trained on CelebA-Spoof, which is licensed non-commercial.
- So we train our own on the recapture data from the dataset track.

**Idea:**
1. Crop the face with 01's detector.
2. Classify the crop as live vs. recaptured with a small CNN: MobileNetV3-small through `timm` (Apache-2.0). Optionally add a second input for full-frame cues like screen borders, moiré and glare.
3. Export to LiteRT and run it in flavor `a12`.

**Catches:** F2 (printouts and screen replays).

**What makes it work:** variety in our own recaptures. That means many screens (phones, laptops, TVs), printers, papers, angles and lighting, captured on the same low-end phones the field team uses.
