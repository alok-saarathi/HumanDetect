"""Compares zero-shot models on a folder of labeled images (PyTorch, laptop only).

Usage: uv run --group models python approaches/02-zero-shot-clip/compare_models.py DIR MODEL [MODEL ...]

DIR holds one sub-folder per label, as in data/eval/<split>/ (live, no_human, recapture,
screenshot, not_real). "live" is genuine; everything else is fake. MODEL is a Hugging Face id:
a TinyCLIP checkpoint (wkcn/...) or a SigLIP 2 checkpoint (google/siglip2-...).

Prints, per model, the share of images judged correctly at threshold 0.5 and the ROC-AUC
of the genuine score. Run one model per process if memory is tight.
"""

import sys
from pathlib import Path

import numpy as np
import torch
import yaml
from PIL import Image, ImageOps

from zero_shot import CLIP_MEAN, CLIP_STD, DEFAULT_PROMPTS, GENUINE, preprocess

EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


def load_items(root: Path) -> list[tuple[Path, str]]:
    return sorted((p, p.parent.name) for p in root.rglob("*") if p.suffix.lower() in EXTENSIONS)


def genuine_score(sims: np.ndarray, buckets: list[str], scale: float, bias: float = 0.0) -> float:
    """Same rule as zero_shot.judge: best prompt per bucket, softmax across buckets."""
    logits = scale * sims + bias
    names = sorted(set(buckets))
    best = np.array([max(l for l, b in zip(logits, buckets) if b == n) for n in names])
    p = np.exp(best - best.max())
    p /= p.sum()
    return float(p[names.index(GENUINE)])


def auc(live: list[float], fake: list[float]) -> float:
    pairs = [(1.0 if a > b else 0.5 if a == b else 0.0) for a in live for b in fake]
    return float(np.mean(pairs)) if pairs else float("nan")


def main() -> None:
    root, model_ids = Path(sys.argv[1]), sys.argv[2:]
    items = load_items(root)
    spec = yaml.safe_load(DEFAULT_PROMPTS.read_text())
    prompts = [(b, p) for b, ps in spec["buckets"].items() for p in ps]
    buckets = [b for b, _ in prompts]
    texts = [[t.format(p) for t in spec["templates"]] for _, p in prompts]

    for model_id in model_ids:
        with torch.no_grad():
            if model_id.startswith("google/siglip"):
                from transformers import AutoModel, AutoProcessor

                m, proc = AutoModel.from_pretrained(model_id).eval(), AutoProcessor.from_pretrained(model_id)

                def text_emb(tt):
                    e = m.get_text_features(**proc(text=tt, padding="max_length", max_length=64, return_tensors="pt"))
                    return e if torch.is_tensor(e) else e.pooler_output

                def image_emb(img):
                    e = m.get_image_features(**proc(images=img, return_tensors="pt"))
                    return (e if torch.is_tensor(e) else e.pooler_output)[0]

                scale, bias = m.logit_scale.exp().item(), m.logit_bias.item()
            else:
                from transformers import CLIPModel, CLIPTokenizerFast

                m = CLIPModel.from_pretrained(model_id, use_safetensors=True).eval()
                tok = CLIPTokenizerFast.from_pretrained(model_id)
                mean, std = torch.tensor(CLIP_MEAN).view(1, 3, 1, 1), torch.tensor(CLIP_STD).view(1, 3, 1, 1)

                def text_emb(tt):
                    return m.text_projection(m.text_model(**tok(tt, padding=True, return_tensors="pt")).pooler_output)

                def image_emb(img):
                    x = (torch.from_numpy(preprocess(img)).permute(0, 3, 1, 2) - mean) / std
                    return m.visual_projection(m.vision_model(pixel_values=x).pooler_output)[0]

                scale, bias = m.logit_scale.exp().item(), 0.0

            T = []
            for tt in texts:
                e = text_emb(tt)
                e = (e / e.norm(dim=-1, keepdim=True)).mean(0)
                T.append((e / e.norm()).numpy())
            T = np.stack(T)
            live, fake, correct = [], [], 0
            for path, label in items:
                e = image_emb(ImageOps.exif_transpose(Image.open(path)).convert("RGB"))
                g = genuine_score(T @ (e / e.norm()).numpy(), buckets, scale, bias)
                (live if label == "live" else fake).append(g)
                correct += (g >= 0.5) == (label == "live")
        params = sum(p.numel() for p in m.vision_model.parameters()) / 1e6
        print(f"{model_id} (image tower {params:.0f}M): correct@0.5 {correct}/{len(items)}  AUC {auc(live, fake):.2f}")


if __name__ == "__main__":
    main()
