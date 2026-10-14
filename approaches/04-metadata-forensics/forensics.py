"""Recapture and metadata forensics: reference implementation of approach 04.

Mirrored by app/lib/approaches/a04_forensics/forensics.dart. No model: hand-written signals.

  sharpness   variance of the Laplacian on a 512-px grayscale copy     -> BLURRY
  glare       share of near-white pixels (luma >= 250)                  -> GLARE
  contrast    luma spread, 99th minus 1st percentile                    -> LOW_CONTRAST
  moire       sharp isolated peaks in the frequency spectrum of a       -> MOIRE
              full-resolution center patch (screens and halftone prints
              produce periodic patterns that natural scenes don't)
  exif        camera make/model present; capture time close to "now"    -> METADATA_MISSING, TIME_MISMATCH

Default thresholds are rough starting points from a handful of images. Calibrate them on
the dataset's dev split before trusting any verdict.
"""

from dataclasses import dataclass, field
from datetime import datetime

import numpy as np
from PIL import Image, ImageOps

ANALYSIS_SIZE = 512  # long side of the copy used for sharpness, glare and contrast
PATCH_SIZE = 512  # side of the full-resolution center patch used for the spectrum
MIN_RADIUS, MAX_RADIUS = 0.15, 0.95  # spectrum band examined, as a fraction of Nyquist
TOP_PEAKS = 8


@dataclass
class Thresholds:
    min_sharpness: float = 40.0
    max_glare: float = 0.05
    min_contrast: float = 60.0
    max_moire: float = 3.5
    max_time_skew_s: float = 600.0


@dataclass
class Report:
    sharpness: float
    glare: float
    contrast: float
    moire: float
    exif_make: str | None
    exif_model: str | None
    exif_time: datetime | None
    passed: bool = True
    reasons: list[str] = field(default_factory=list)


def luma(pixels: np.ndarray) -> np.ndarray:
    return pixels[..., 0] * 0.299 + pixels[..., 1] * 0.587 + pixels[..., 2] * 0.114


def resize_bilinear(pixels: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    """2-D version of the shared bilinear resize (OpenCV INTER_LINEAR)."""
    in_h, in_w = pixels.shape[:2]
    xs = np.clip((np.arange(out_w) + 0.5) * (in_w / out_w) - 0.5, 0, in_w - 1)
    ys = np.clip((np.arange(out_h) + 0.5) * (in_h / out_h) - 0.5, 0, in_h - 1)
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    x1, y1 = np.minimum(x0 + 1, in_w - 1), np.minimum(y0 + 1, in_h - 1)
    fx, fy = (xs - x0)[None, :], (ys - y0)[:, None]
    top = pixels[y0][:, x0] * (1 - fx) + pixels[y0][:, x1] * fx
    bottom = pixels[y1][:, x0] * (1 - fx) + pixels[y1][:, x1] * fx
    return top * (1 - fy) + bottom * fy


def box_downsample(gray: np.ndarray, factor: int) -> np.ndarray:
    if factor <= 1:
        return gray
    h, w = (gray.shape[0] // factor) * factor, (gray.shape[1] // factor) * factor
    return gray[:h, :w].reshape(h // factor, factor, w // factor, factor).mean(axis=(1, 3))


def analysis_copy(gray: np.ndarray) -> np.ndarray:
    """Grayscale copy with long side ANALYSIS_SIZE (box-averaged first to avoid aliasing)."""
    h, w = gray.shape
    gray = box_downsample(gray, max(h, w) // (2 * ANALYSIS_SIZE))
    h, w = gray.shape
    scale = ANALYSIS_SIZE / max(h, w)
    return resize_bilinear(gray, max(1, int(w * scale + 0.5)), max(1, int(h * scale + 0.5)))


def sharpness(small: np.ndarray) -> float:
    lap = small[1:-1, :-2] + small[1:-1, 2:] + small[:-2, 1:-1] + small[2:, 1:-1] - 4 * small[1:-1, 1:-1]
    return float(lap.var())


def glare(small: np.ndarray) -> float:
    return float((small >= 250).mean())


def contrast(small: np.ndarray) -> float:
    lo, hi = np.percentile(small, [1, 99])
    return float(hi - lo)


def moire(gray: np.ndarray) -> float:
    """Mean of the TOP_PEAKS largest spectrum excesses over the per-radius median (log units)."""
    h, w = gray.shape
    n = PATCH_SIZE
    while n > 8 and n > min(h, w):  # largest power of two that fits, down to 8
        n //= 2
    if n > min(h, w):
        return 0.0  # image too small to analyse
    y0, x0 = (h - n) // 2, (w - n) // 2
    patch = gray[y0 : y0 + n, x0 : x0 + n]
    patch = patch - patch.mean()
    window = np.hanning(n)
    spectrum = np.log1p(np.abs(np.fft.fftshift(np.fft.fft2(patch * np.outer(window, window)))))
    yy, xx = np.mgrid[0:n, 0:n] - n // 2
    radius = np.sqrt(xx**2 + yy**2) / (n / 2)
    ring = np.round(np.sqrt(xx**2 + yy**2)).astype(int)
    band = (radius >= MIN_RADIUS) & (radius <= MAX_RADIUS)
    excess = np.zeros_like(spectrum)
    for r in np.unique(ring[band]):
        sel = band & (ring == r)
        excess[sel] = spectrum[sel] - np.median(spectrum[sel])
    return float(np.sort(excess[band])[-TOP_PEAKS:].mean())


def read_exif(img: Image.Image) -> tuple[str | None, str | None, datetime | None]:
    exif = img.getexif()
    make, model = exif.get(0x010F), exif.get(0x0110)
    raw_time = exif.get_ifd(0x8769).get(0x9003) or exif.get(0x0132)  # DateTimeOriginal, else DateTime
    when = None
    if raw_time:
        try:
            when = datetime.strptime(str(raw_time).strip("\x00 "), "%Y:%m:%d %H:%M:%S")
        except ValueError:
            pass
    return (str(make).strip("\x00 ") or None) if make else None, (str(model).strip("\x00 ") or None) if model else None, when


def analyze(img: Image.Image, now: datetime | None = None, t: Thresholds = Thresholds()) -> Report:
    make, model, when = read_exif(img)
    gray = luma(np.asarray(ImageOps.exif_transpose(img).convert("RGB"), dtype=np.float32))
    small = analysis_copy(gray)
    r = Report(sharpness(small), glare(small), contrast(small), moire(gray), make, model, when)
    if r.sharpness < t.min_sharpness:
        r.reasons.append("BLURRY")
    if r.glare > t.max_glare:
        r.reasons.append("GLARE")
    if r.contrast < t.min_contrast:
        r.reasons.append("LOW_CONTRAST")
    if r.moire > t.max_moire:
        r.reasons.append("MOIRE")
    if not (make or model):
        r.reasons.append("METADATA_MISSING")
    if now is not None and when is not None and abs((now - when).total_seconds()) > t.max_time_skew_s:
        r.reasons.append("TIME_MISMATCH")
    r.passed = not r.reasons
    return r


if __name__ == "__main__":
    import sys

    for path in sys.argv[1:]:
        rep = analyze(Image.open(path))
        print(
            f"{path.split('/')[-1][:40]:40s} sharp={rep.sharpness:7.1f} glare={rep.glare:.3f} "
            f"contrast={rep.contrast:5.1f} moire={rep.moire:4.2f} exif={rep.exif_make}/{rep.exif_model} "
            f"{'PASS' if rep.passed else 'FAIL ' + ','.join(rep.reasons)}"
        )
