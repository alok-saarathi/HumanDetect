# D · Our own open dataset

**Goal:** a license-clean image set we fully control. It has two jobs:
- **Score** every approach.
- **Train** the dataset-based approaches (10–14).

**Status:** see [plan.md](../plan.md#4-dataset-track).

## Why we build it

- **Public data is off-limits.** Almost every public anti-spoofing and face dataset is non-commercial (CelebA-Spoof, Replay-Attack, FFHQ, …).
- **Our problem is specific.** Field agents photograph screens, printouts and walls on budget phones. Our own captures will match that better than any public set.

## Layout

```
data/                         git-ignored; never committed
  raw/                        everything as collected, never edited
  eval/
    dev/                      for tuning thresholds and prompts
      live/  no_human/  recaptured/  screenshot/  not_real/
    test/                     frozen from v1 onward; each approach runs on it once
      (same classes)
  train/                      for 10–14; never overlaps eval/
    (same classes)
  duplicate/                  F4 pairs, used only by 07
  manifest.csv                one row per image
```

**Split rules**
- Split by **person and session**, so the same volunteer or customer never appears in both dev and test.
- **Test looks like production:** only our own captures and production data. Public and generated images go to `train/` and `dev/` only.
- **Anonymized filenames** (`0001.jpg`), never names or IDs. That keeps results CSVs safe to commit.

## Manifest

`manifest.csv` columns:

| Column | Values / meaning |
|---|---|
| `path` | relative to `data/` |
| `label` | `live`, `no_human`, `recaptured`, `screenshot`, `not_real` |
| `split` | `dev`, `test`, `train` |
| `source` | `own-staged`, `prod-flagged`, `prod-genuine`, `openimages`, `wikimedia`, `unsplash-lite`, `generated` |
| `license` | `own`, `CC0`, `CC-BY-4.0`, `CC-BY-2.0`, `unsplash-lite`, `private` |
| `source_url`, `attribution` | required for anything not `own` or `private` |
| `consent_id` | required for any image showing a person we photographed |
| `generated_from` | for generated fakes: the source image's `path` |
| `camera`, `device`, `light` | `front`/`back`; phone model; `good`/`low` |
| `notes` | free text, e.g. "spectacles, dupatta" |

The validator rejects rows with a missing license, missing consent or attribution, or a test-split leak.

## Sources

### 1. Own staged captures (the core)
Volunteers sign a consent form covering ML training and, optionally, publication. Under India's DPDP Act, consent should be specific and withdrawable, so check the form with legal.

Shot list per volunteer, using the **field team's actual phone models**:

| Class | What to shoot |
|---|---|
| `live` | front and back camera; indoor, outdoor, low light; with and without spectacles and head coverings; close and arm's length |
| `recaptured` | the same live photos shown on phones, laptops and a TV; printed on plain and glossy paper; shot straight, at angles, with glare, and cropped tight so screen edges don't show |
| `screenshot` | screenshots of those photos in gallery and chat apps on the team's phones |
| `no_human` | walls, floors, desks, vehicles, documents, shop fronts: what agents actually see in the field |
| `not_real` | posters, mannequins, statues, printed cartoons (only our own photos of them) |

### 2. Production data (private)
- Fakes that ops has flagged, plus consented genuine captures.
- Internal use only: never committed, never published, never sent to a third party.

### 3. Open-licensed public images
Used mostly for `no_human` and for variety in `train/`.
- **Open Images V7:** keep only images listed as CC BY 2.0, and record attribution. Google doesn't warrant image licenses, so we keep each image's source URL.
- **Wikimedia Commons:** CC0, public domain or CC BY only. No share-alike, no non-commercial.
- **Unsplash Lite:** allowed for training, but not redistributable, so it's never published.

### 4. Generated fakes (`dataset/generators/`, our own code)
Turns sources 1 and 3 into extra training fakes:
- **Screenshot:** puts the photo inside a phone status bar, chat bubble or gallery frame drawn by our code.
- **Screen:** moiré, RGB subpixel pattern, bezel, reflection.
- **Print:** halftone, paper texture, color shift, curl warp, glare.
- **All of the above:** perspective warp, blur, JPEG recompression.

Generated images go to `train/` only.

### 5. Labeling
- Open models (02, 06, 09) pre-label public and unlabeled images.
- People confirm the labels in Label Studio (Apache-2.0).
- 10 % of labels get double-checked.

## Versions

| Version | Contents | Size | Unblocks |
|---|---|---|---|
| v0 | own staged captures only | ~50 per class per split | 01, 02 |
| v1 | + flagged fakes and consented genuine captures from production | 200+ per class per split; test frozen | fair comparison of every approach |
| train-v1 | + public + generated + auto-labeled | a few thousand total | 10–14 |

## Publishing

- The repo is public, so images never go into git.
- Later we can publish an open subset separately, with an `ATTRIBUTION` file. Only images whose license and consent allow redistribution can go in.

## Work plan

### Prompts (my part)
1. **Tooling:** manifest schema, validator (license, consent and leak checks), folder bootstrapper.
2. **Public sources:** Open Images downloader filtered by label and license, and a Wikimedia downloader (CC0 / CC BY only). Both write attribution.
3. **Fake generators:** screenshot, screen and print, plus a preview sheet to check they look right.
4. **Labeling:** auto-label pass and Label Studio config. Runs once 02 or 06 exists.

### Needs from you
- [ ] Consent form, checked by legal
- [ ] One staged capture session (v0): 5–10 volunteers, the field team's phone models, a few screens and a printer. About half a day.
- [ ] From ops: counts and examples of flagged fake uploads, and confirmation they can be used internally
- [ ] Copy the photos into `data/raw/`. I'll organize, register and split them.
