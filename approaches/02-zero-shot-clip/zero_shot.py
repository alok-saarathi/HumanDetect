"""Zero-shot genuine-vs-fake classification with TinyCLIP: reference implementation.

Mirrored by app/lib/approaches/a02_zero_shot/ (preprocessing in image_ops.dart, scoring in
zero_shot_check.dart). The exported image encoder takes NHWC RGB in [0, 1]; CLIP's
mean/std normalization happens inside the model, so the app only resizes and crops.

Models: TinyCLIP checkpoints trained on YFCC15M (Creative Commons images), MIT license.
The app ships ViT-39M/16; ViT-8M/16 is smaller but clearly weaker (see README findings).
"""

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
import yaml
from PIL import Image

# Pinned Hugging Face commits.
MODELS = {
    "tinyclip-39m": ("wkcn/TinyCLIP-ViT-39M-16-Text-19M-YFCC15M", "07a4b0bc751cb64fecd2b661c048c1dd98d69444"),
    "tinyclip-8m": ("wkcn/TinyCLIP-ViT-8M-16-Text-3M-YFCC15M", "a2a8c6eaa2549ad66eb7c31b85022bf58273a26c"),
}
DEFAULT_MODEL = "tinyclip-39m"
IMAGE_SIZE = 224
CLIP_MEAN = (0.48145466, 0.4578275, 0.40821073)
CLIP_STD = (0.26862954, 0.26130258, 0.27577711)
HERE = Path(__file__).resolve().parent
DEFAULT_PROMPTS = HERE / "prompts/v0.yaml"
GENUINE = "genuine"


def load_clip(name: str = DEFAULT_MODEL):
    from transformers import CLIPModel, CLIPTokenizerFast

    model_id, revision = MODELS[name]
    model = CLIPModel.from_pretrained(model_id, revision=revision, use_safetensors=True).eval()
    tokenizer = CLIPTokenizerFast.from_pretrained(model_id, revision=revision)
    return model, tokenizer


# --- preprocessing (mirrored in Dart) -------------------------------------------------


def box_downsample(pixels: np.ndarray, factor: int) -> np.ndarray:
    """Average non-overlapping factor x factor blocks; leftover edge rows/columns are dropped."""
    if factor <= 1:
        return pixels
    h, w = (pixels.shape[0] // factor) * factor, (pixels.shape[1] // factor) * factor
    blocks = pixels[:h, :w].reshape(h // factor, factor, w // factor, factor, -1)
    return blocks.mean(axis=(1, 3))


def resize_bilinear(pixels: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    """Same function as approaches/01-face-detection/blazeface.py (OpenCV INTER_LINEAR)."""
    in_h, in_w = pixels.shape[:2]
    xs = np.clip((np.arange(out_w) + 0.5) * (in_w / out_w) - 0.5, 0, in_w - 1)
    ys = np.clip((np.arange(out_h) + 0.5) * (in_h / out_h) - 0.5, 0, in_h - 1)
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    x1, y1 = np.minimum(x0 + 1, in_w - 1), np.minimum(y0 + 1, in_h - 1)
    fx, fy = (xs - x0)[None, :, None], (ys - y0)[:, None, None]
    top = pixels[y0][:, x0] * (1 - fx) + pixels[y0][:, x1] * fx
    bottom = pixels[y1][:, x0] * (1 - fx) + pixels[y1][:, x1] * fx
    return top * (1 - fy) + bottom * fy


def preprocess(img: Image.Image) -> np.ndarray:
    """Shorter side -> 224, center crop 224x224, scale to [0, 1]. Returns (1, 224, 224, 3).

    Large photos are first box-averaged by an integer factor (so the shorter side stays
    >= 2 x 224) to avoid aliasing, then bilinear-resized. Plain bilinear on a 12 MP photo
    would alias badly; CLIP was trained on smoothly downscaled images.
    """
    pixels = np.asarray(img.convert("RGB"), dtype=np.float32)
    factor = min(pixels.shape[:2]) // (2 * IMAGE_SIZE)
    pixels = box_downsample(pixels, factor)
    h, w = pixels.shape[:2]
    scale = IMAGE_SIZE / min(w, h)
    rw, rh = max(IMAGE_SIZE, int(w * scale + 0.5)), max(IMAGE_SIZE, int(h * scale + 0.5))
    pixels = resize_bilinear(pixels, rw, rh)
    x0, y0 = (rw - IMAGE_SIZE) // 2, (rh - IMAGE_SIZE) // 2
    return (pixels[y0 : y0 + IMAGE_SIZE, x0 : x0 + IMAGE_SIZE] / 255.0)[None].astype(np.float32)


# --- model pieces ----------------------------------------------------------------------


class ImageEncoder(torch.nn.Module):
    """NHWC [0, 1] image -> L2-normalized 512-d embedding. This is what gets exported."""

    def __init__(self, clip):
        super().__init__()
        self.vision = clip.vision_model
        self.projection = clip.visual_projection
        self.register_buffer("mean", torch.tensor(CLIP_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(CLIP_STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x.permute(0, 3, 1, 2) - self.mean) / self.std
        embedding = self.projection(self.vision(pixel_values=x).pooler_output)
        return embedding / embedding.norm(dim=-1, keepdim=True)


@dataclass
class PromptSet:
    version: str
    texts: list[str]  # one per prompt (template-free text, for display)
    buckets: list[str]  # bucket of each prompt
    embeddings: np.ndarray  # (n_prompts, 512), L2-normalized, templates averaged
    logit_scale: float
    reasons: dict[str, str]


def build_prompt_set(clip, tokenizer, path: Path = DEFAULT_PROMPTS) -> PromptSet:
    spec = yaml.safe_load(path.read_text())
    texts, buckets, embeddings = [], [], []
    with torch.no_grad():
        for bucket, prompts in spec["buckets"].items():
            for prompt in prompts:
                filled = [t.format(prompt) for t in spec["templates"]]
                tokens = tokenizer(filled, padding=True, return_tensors="pt")
                out = clip.text_model(**tokens).pooler_output
                e = clip.text_projection(out)
                e = e / e.norm(dim=-1, keepdim=True)
                e = e.mean(0)
                embeddings.append((e / e.norm()).numpy())
                texts.append(prompt)
                buckets.append(bucket)
    return PromptSet(
        spec["version"], texts, buckets, np.stack(embeddings), clip.logit_scale.exp().item(), spec["reasons"]
    )


@dataclass
class Verdict:
    passed: bool
    score: float  # probability of the genuine bucket
    reasons: list[str]
    bucket_scores: dict[str, float]


def judge(image_embedding: np.ndarray, prompts: PromptSet, threshold: float = 0.5) -> Verdict:
    """Each bucket is scored by its best-matching prompt, then softmax across buckets.

    Taking the max (not the sum) per bucket keeps buckets with more prompts from winning
    just because they have more prompts.
    """
    logits = prompts.logit_scale * (prompts.embeddings @ image_embedding.reshape(-1))
    best: dict[str, float] = {}
    for bucket, logit in zip(prompts.buckets, logits):
        best[bucket] = max(best.get(bucket, -np.inf), float(logit))
    names = list(best)
    values = np.array([best[n] for n in names])
    probs = np.exp(values - values.max())
    probs /= probs.sum()
    bucket_scores = dict(zip(names, probs.tolist()))
    score = bucket_scores.get(GENUINE, 0.0)
    if score >= threshold:
        return Verdict(True, score, [], bucket_scores)
    worst = max((b for b in bucket_scores if b != GENUINE), key=bucket_scores.get)
    return Verdict(False, score, [prompts.reasons[worst]], bucket_scores)
