"""Approach 06: zero-shot, text-prompted detection on a server. Find a human face, then
check it isn't framed by a screen or print, and isn't a painting, statue or mannequin.

Models (Apache-2.0, loaded natively by `transformers`, no remote code):
  * OWLv2 base/16 ensemble  (google/owlv2-base-patch16-ensemble)   used by the service
  * Grounding DINO tiny     (IDEA-Research/grounding-dino-tiny)    CLI comparison only
    (`--param model=1`). On our smoke set its face score was 0.20-0.33 even on walls
    and every context prompt fired on every image, so it is not offered in the app.

Each prompt group is detected separately; the rule works on boxes:
  NO_FACE         no "human face" box scores >= min_face
  FACE_TOO_SMALL  the best face covers < min_area of the photo
  RECAPTURE       a screen / print / poster / ID-card box holds most of the face box
  NOT_REAL        a painting / statue / mannequin / cartoon box holds most of the face box
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from humandetect_server.contract import Mark, Result, Tunable, param  # noqa: E402

# (name, Hugging Face id, pinned commit)
MODELS = [
    ("OWLv2 base/16", "google/owlv2-base-patch16-ensemble", "cfd3195ba4ea9592eec887ded089f4c08eff231d"),
    ("Grounding DINO tiny", "IDEA-Research/grounding-dino-tiny", "a2bb814dd30d776dcf7e30523b00659f4f141c71"),
]
FACE = ["a human face"]
CONTAINERS = ["a phone screen", "a computer monitor", "a television", "a printed photograph", "a poster", "an identity card"]
NOT_REAL = ["a painting", "a statue", "a mannequin", "a cartoon"]
PROMPTS = FACE + CONTAINERS + NOT_REAL

MODEL = Tunable("model", "Model: 0 = OWLv2, 1 = Grounding DINO (CLI only)", 0, 1, 0, 0)
MIN_FACE = Tunable("min_face", "Min face score", 0.05, 0.9, 0.15, 2)
MIN_AREA = Tunable("min_area", "Min face area (share of photo)", 0.002, 0.2, 0.01, 3)
MIN_CONTEXT = Tunable("min_context", "Min score of a screen / print / not-real box", 0.1, 0.9, 0.35, 2)
MIN_INSIDE = Tunable("min_inside", "Share of the face inside such a box", 0.5, 1.0, 0.8, 2)
# Grounding DINO scores run much higher across the board; its own starting points.
GDINO_DEFAULTS = {"min_face": 0.45, "min_context": 0.5}
# A "printed photograph" box covering the whole frame only says "this is a photo".
WHOLE_FRAME = 0.9


def area(b) -> float:
    return max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])


def inside_share(inner, outer) -> float:
    x0, y0, x1, y1 = max(inner[0], outer[0]), max(inner[1], outer[1]), min(inner[2], outer[2]), min(inner[3], outer[3])
    a = area(inner)
    return area((x0, y0, x1, y1)) / a if a > 0 else 0.0


class ZeroShotDetection:
    id = "06"
    title = "Zero-shot detection"
    score_label = "face score"
    tunables = [MIN_FACE, MIN_AREA, MIN_CONTEXT, MIN_INSIDE]

    def __init__(self):
        self._models: dict[int, tuple] = {}

    def load(self) -> None:
        self._get(0)  # Grounding DINO loads on first request for it

    def _get(self, index: int):
        if index not in self._models:
            import torch
            from transformers import AutoModelForZeroShotObjectDetection, AutoProcessor

            from humandetect_server.device import torch_device

            _, model_id, revision = MODELS[index]
            device = torch_device()
            processor = AutoProcessor.from_pretrained(model_id, revision=revision)
            model = AutoModelForZeroShotObjectDetection.from_pretrained(model_id, revision=revision, use_safetensors=True)
            self._models[index] = (torch, processor, model.eval().to(device), device)
        return self._models[index]

    def detect(self, image: Image.Image, index: int, threshold: float = 0.05) -> list[tuple[str, float, tuple]]:
        """[(prompt, score, (x0, y0, x1, y1) normalized)] for boxes scoring >= threshold."""
        torch, processor, model, device = self._get(index)
        w, h = image.size
        with torch.no_grad():
            if index == 0:  # OWLv2: one query list, boxes on the image padded to a square
                inputs = processor(text=[PROMPTS], images=image, return_tensors="pt").to(device)
                outputs = model(**inputs)
                side = max(w, h)
                found = processor.post_process_grounded_object_detection(
                    outputs, threshold=threshold, target_sizes=[(side, side)])[0]
                labels = [PROMPTS[i] for i in found["labels"].tolist()]
            else:  # Grounding DINO: one period-separated caption
                caption = " ".join(p + "." for p in PROMPTS)
                inputs = processor(images=image, text=caption, return_tensors="pt").to(device)
                outputs = model(**inputs)
                found = processor.post_process_grounded_object_detection(
                    outputs, inputs.input_ids, threshold=threshold, text_threshold=threshold, target_sizes=[(h, w)])[0]
                labels = [_match_prompt(t) for t in found.get("text_labels", found["labels"])]
        out = []
        for label, score, box in zip(labels, found["scores"].tolist(), found["boxes"].tolist()):
            if label is None:
                continue
            x0, y0, x1, y1 = box
            out.append((label, score, (max(0, x0 / w), max(0, y0 / h), min(1, x1 / w), min(1, y1 / h))))
        return out

    def check(self, image: Image.Image, params: dict[str, float]) -> Result:
        index = int(round(param(params, MODEL)))
        if index == 1:
            params = {**GDINO_DEFAULTS, **params}
        min_face, min_area = param(params, MIN_FACE), param(params, MIN_AREA)
        min_context, min_inside = param(params, MIN_CONTEXT), param(params, MIN_INSIDE)

        found = self.detect(image, index)
        faces = sorted([d for d in found if d[0] in FACE], key=lambda d: -d[1])
        context = [d for d in found if d[0] not in FACE and d[1] >= min_context
                   and not (d[0] == "a printed photograph" and area(d[2]) > WHOLE_FRAME)]
        marks = [Mark((b[0], b[1], b[2] - b[0], b[3] - b[1]), f"{p.removeprefix('a ').removeprefix('an ')} {s:.2f}")
                 for p, s, b in faces[:3] + context if s >= min(min_face, min_context)]
        details = [("Model", MODELS[index][0]),
                   ("Best face score", f"{faces[0][1]:.2f}" if faces else "none"),
                   ("Context boxes", ", ".join(f"{p} {s:.2f}" for p, s, _ in context) or "none")]
        if not faces or faces[0][1] < min_face:
            return Result(False, faces[0][1] if faces else 0.0, ["NO_FACE"], details, marks)

        _, score, face = faces[0]
        reasons = []
        details.append(("Face area", f"{area(face) * 100:.1f} % of photo"))
        if area(face) < min_area:
            reasons.append("FACE_TOO_SMALL")
        for prompt, s, box in sorted(context, key=lambda d: -d[1]):
            if area(box) <= area(face) * 1.2:
                continue  # a box hugging the face itself says little about framing
            share = inside_share(face, box)
            if share >= min_inside:
                reasons.append("RECAPTURE" if prompt in CONTAINERS else "NOT_REAL")
                details.append(("Face inside", f"{prompt} {s:.2f} ({share * 100:.0f} % of the face)"))
                break
        return Result(not reasons, score, reasons, details, marks)


def _match_prompt(text: str) -> str | None:
    """Grounding DINO returns the matched words; map them back to a prompt."""
    text = text.strip().lower()
    for p in PROMPTS:
        if text and (text in p or p.removeprefix("a ").removeprefix("an ") in text):
            return p
    return None
