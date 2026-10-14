# 04 · Recapture and metadata forensics

> Status and stages live in [plan.md](../../plan.md). A full work plan gets written here when this approach is next up. Every model or package used must be listed in [THIRD_PARTY_LICENSES.md](../../THIRD_PARTY_LICENSES.md) first.

**What it is:** rules written by us. No model is involved.

**Signals:**
- **EXIF:** camera make and model, and `DateTimeOriginal` compared with the upload time.
- **Screenshots:** usually have no camera EXIF, and their dimensions equal a screen resolution.
- **Screen moiré:** peaks in the image's FFT.
- **Quality:** blur, glare, flatness.

**Catches:** F3 and part of F2.

**Watch out:**
- EXIF is trivial to strip or forge, so treat it as a signal, never a verdict.
- If a learned moiré detector turns out to be needed, it gets trained on our own data in 12. The ones on Hugging Face have no clear license.

**Packages:** Pillow, exifread, numpy (all permissive).

## Implementation (lab app 0.1.0)

**Status:** prototype in Python and in the app (tile 04). Thresholds need calibrating on the dataset's dev split.

| Part | Where |
|---|---|
| Signals + decision (reference) | `forensics.py` (also a CLI: `forensics.py IMAGE…`) |
| Same signals in the app, including a radix-2 FFT | `app/lib/approaches/a04_forensics/forensics.dart` |
| Check shown in the app | `forensics_check.dart` (EXIF through the `exif` package, MIT) |

**Signals:**

| Signal | How it's computed | Default limit | Reason code |
|---|---|---|---|
| Sharpness | variance of the Laplacian on a 512-px grayscale copy | ≥ 40 | `BLURRY` |
| Glare | share of pixels with luma ≥ 250 | ≤ 5 % | `GLARE` |
| Contrast | 99th − 1st luma percentile | ≥ 60 | `LOW_CONTRAST` |
| Moiré | 512² full-resolution center patch, Hann window, 2-D FFT, log magnitude; mean of the 8 largest excesses over each frequency ring's median (band 0.15–0.95 of Nyquist) | ≤ 3.5 | `MOIRE` |
| EXIF | camera make/model present; `DateTimeOriginal` within 600 s of capture. A hard check for an in-app camera photo only. On a gallery file the values are shown and do not fail the check. | — | `METADATA_MISSING`, `TIME_MISMATCH` |

**Findings** (about 25 public images plus simulated recaptures):
- **Moiré on normal photos:** 1.3–3.2. The high end is regular structures: rows of desks, wood grain.
- **Moiré on simulated close-up phone-screen photos** (pixel grid resolved by the camera): 4.9–6.3.
- **Missed:** a simulated screen photo whose grid aliased away scored only 1.85. Moiré only catches screens photographed close enough to resolve the pixel grid.
- **Glare:** a bathroom mirror selfie reached 3.9 %, so the glare limit was raised from 3 % to 5 %.
- **Parity:** the Dart signals match Python on synthetic inputs, and the FFT matches a direct DFT (`app/test/parity_test.dart`).
