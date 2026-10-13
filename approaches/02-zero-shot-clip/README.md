# 02 · Zero-shot image classification (CLIP family)

**Ladder position:** 2 of 15
**Status:** see [plan.md](../../plan.md)
**Build:** ~5 prompts
**In the app:** tile 02 of the lab app (versions `0.1.x`)

## Goal

Find out two things:
- Can an open vision-language model separate genuine captures from **all** the fake types, not just F1, using only text prompts and no training?
- Can a phone-sized version of it run in the app?

This is where we expect to first beat 01 on F2 (screens and printouts), F3 (screenshots) and F5 (cartoons, AI faces).

## How it works

CLIP-style models turn an image and a piece of text into vectors in the same space. If the image matches the text, the two vectors point in a similar direction. So we:
1. Score the photo against a set of text prompts.
2. Group the prompts into a **genuine** bucket and several **fake** buckets.
3. Let the photo pass when the genuine bucket wins by a margin.

The prompt vectors are computed once, ahead of time. On the phone, only the image half of the model runs, followed by a dot product.

## Variants

| ID | Model | License | Role |
|---|---|---|---|
| 02a | **SigLIP 2 base** (`google/siglip2-base-patch16-224`) | Apache-2.0 | likely the most accurate. Its ~90M-parameter image half is probably too big for budget phones, so it's for a server or as a teacher for 13 |
| 02b | **TinyCLIP** (start with `wkcn/TinyCLIP-ViT-8M-16-Text-3M-YFCC15M`) | MIT, per its model card | **the on-device candidate**: tiny, and trained on Creative Commons images (YFCC) |
| 02c | OpenAI CLIP ViT-B/32 | MIT | **reference only**: its model card says deployed use is out of scope, so we compare against it but don't ship it |
| 02x | 01's face gate **and** the best 02 variant | — | combination: needs a face from 01 **and** a genuine verdict from 02 |

## Prompt set v0

Each prompt is also wrapped in templates ("a photo of {}", "a blurry photo of {}", "a low-light photo of {}"), and the resulting vectors are averaged. This is called prompt ensembling.

| Bucket | Prompts (v0; tune on the dev split only) |
|---|---|
| genuine | a person's face photographed with a phone camera · a selfie of a person · a portrait of a man · a portrait of a woman · an elderly person facing the camera |
| F1 · no human | a wall · a floor · a table · an empty room · a landscape · a dark blurry photo · an everyday object |
| F2 · recapture | a phone screen showing a person's face · a computer monitor showing a photo · a printed photograph held in a hand · a poster of a person · an identity card with a photo |
| F3 · screenshot | a screenshot of a phone screen · a screenshot of a chat app |
| F5 · not real | a cartoon of a person · a drawing of a face · a mannequin · a statue · a computer-generated face |

Prompts live in `prompts/v<N>.yaml`, and every result row records which version produced it.

## Decision rule

- **TinyCLIP and CLIP** (probabilities across all prompts add up to 1):
  - `score` = the summed probability of the genuine prompts.
  - Pass when `score ≥ T`.
- **SigLIP 2** (each prompt scored on its own):
  - `score` = the best genuine prompt's score minus the best fake prompt's score.
  - Pass when `score ≥ T`.
- **On failure**, the reason code is the winning fake bucket: `NO_HUMAN`, `RECAPTURE`, `SCREENSHOT` or `NOT_REAL`.
- **Choosing `T`:** sweep it on the dev split and pick the value that meets the genuine-reject target.

## Folder layout

```
approaches/02-zero-shot-clip/
  README.md                this plan, then findings
  prompts/
    v0.yaml
  models.py                loads 02a–02c behind one embed_image / embed_text API
  classify.py              buckets, scoring, decision rule
  run_eval.py              → results/<variant>-<prompts>-<split>.csv
  export/
    export_tinyclip.py     image encoder → LiteRT; prompt vectors → app assets
    check_parity.py        compares PyTorch and LiteRT vectors
  notebooks/
    prompt_lab.ipynb       per-prompt confusion, failure gallery
  results/
    summary.md
```

The app side lives at `app/lib/approaches/a02_zero_shot/`. The model and prompt vectors go in `app/assets/a02/`, bundled into the `a02` flavor only.

## Work plan

### Prompts (my part)
1. **Python prototype:**
   - Register the licenses.
   - `models.py`, `prompts/v0.yaml`, `classify.py` and `run_eval.py`.
   - A sanity run on a handful of images per bucket.
2. **Evaluate:**
   - Run every variant on dev and build a confusion matrix per bucket.
   - Iterate on the prompts (v1, v2, …), then freeze the best variant, prompt version and `T`.
   - Run once on test, and evaluate 02x.
   - Fill in `summary.md` and the scoreboard.
3. **Export:**
   - Convert the TinyCLIP image encoder to LiteRT (FP16, then INT8).
   - Run `check_parity.py`: vectors must agree with PyTorch (cosine similarity ≥ 0.99).
   - Write the prompt vectors to `prompts.json`.
   - This is the step most likely to need an extra round.
4. **App:**
   - `ZeroShotCheck` in Dart, with preprocessing (resize, crop, normalize) that exactly matches Python.
   - Run the on-device batch eval and compare it with Python.
   - Build `humandetect-a02-0.2.0.apk`, plus a variant with 01's face gate.
5. **Buffer and decision:**
   - Fix whatever the phone run exposed.
   - Record the verdict: **adopt on-device**, **server only**, **teacher for 13**, or **drop**.

### Needs from you
- [ ] Dataset v0 with **every** fake class. Unlike 01, this approach can't be judged on `live/` and `no_human/` alone.
- [ ] 01 finished. It provides the baseline and the face gate.
- [ ] The same phone and testers as 01.

## Exit criteria

These are placeholders until the business targets are agreed:
- At the same genuine-reject rate as 01, F2, F3 and F5 accept rates at most half of 01's.
- F1 accept rate no worse than 01's.
- On-device p95 latency ≤ 300 ms.
- APK size increase ≤ 30 MB.

## Risks

- **Overfitting the prompts.** It's easy to tweak prompts until the dev split looks perfect. The test split is frozen and run only once to guard against this.
- **TinyCLIP may be too weak.** If so, SigLIP 2 moves to a server (built in 06), or becomes the teacher for a small model (13).
- **Screens and printouts.** CLIP-style models may have a weak sense of "a photo of a screen showing a person" vs. "a photo of a person", so F2 may stay hard. The anti-spoof classifier (12) exists for that.
- **Preprocessing mismatch.** A small difference between Python and Dart preprocessing silently shifts scores, which is why the parity check is mandatory.

## Resources

- SigLIP 2: https://huggingface.co/google/siglip2-base-patch16-224
- TinyCLIP: https://huggingface.co/wkcn/TinyCLIP-ViT-8M-16-Text-3M-YFCC15M
- CLIP: https://huggingface.co/openai/clip-vit-base-patch32

## Implementation (lab app 0.1.0)

**Status:** Stage 2 · Prototype done, both in Python and in the app. Stage 3 waits for dataset v0; Stage 4 waits for a phone test.

| Part | Where |
|---|---|
| Preprocessing, prompt set loading, bucket scoring | `zero_shot.py` → mirrored in `app/lib/approaches/a02_zero_shot/zero_shot_check.dart` |
| Prompts | `prompts/v0.yaml` (25 prompts, 5 buckets, 4 templates) |
| Export to LiteRT + int8 + parity check | `export_tinyclip.py` (`--model tinyclip-39m` by default) |
| Run the exported model on images, as the app does | `classify.py IMAGE…` |
| Compare candidate models on a labeled folder | `compare_models.py DIR MODEL…` |

**What changed from the plan:**
- **Shipped TinyCLIP ViT-39M/16 (YFCC15M), not 8M:** 8M was too weak; it ranked "a floor" above "a person's face" on a studio portrait.
- **Weights in int8** (dynamic range): 40 MB, cosine 0.9993 vs PyTorch.
- **Scoring changed:** each bucket now scores by its **best prompt**, not the sum of its prompts. Summing favoured buckets with more prompts.
- **Exporter:** `litert-torch` replaces `ai-edge-torch`, which needs Linux-only `torch-xla`.

## Findings

**Model comparison.** This is a 25-image smoke test, not an evaluation:
- 5 genuine photos and 20 fakes (scenes, statues, mannequins, paintings, drawings, old prints, a simulated screen).
- All images are CC0/public domain, plus the MediaPipe test portrait.

| Model | Image tower | AUC | Correct at 0.5 |
|---|---|---|---|
| TinyCLIP ViT-8M/16 (YFCC) | 8M | 0.88–0.90 | 21/25 |
| **TinyCLIP ViT-39M/16 (YFCC), shipped** | 38M | 0.93–0.94 | 22/25 |
| TinyCLIP ViT-40M/32 (LAION) | 39M | 0.92–0.93 | 22/25 |
| TinyCLIP ViT-61M/32 (LAION) | 61M | 0.91–0.93 | 22/25 |
| SigLIP 2 base/32-256 | 95M | 0.98 | 22–23/25 |

**Exported int8 TinyCLIP-39M on the same images:**
- **Rejected:** every scene (NO_HUMAN), statue, mannequin, painting and drawing (NOT_REAL), and the simulated phone screen (RECAPTURE).
- **Passed:** 4 of 5 genuine photos. The miss was a full-body mirror selfie with a tiny face.
- **Wrongly passed:** 2 old printed portrait photographs, scored as genuine. As expected, F2 stays hard for zero-shot.

**Model choice:**
- SigLIP 2 is clearly the strongest, but too big for budget phones. Keep it as the server or teacher option (06/13).
- **LAION-trained TinyCLIPs were avoided** in favour of the Creative Commons-trained one.
