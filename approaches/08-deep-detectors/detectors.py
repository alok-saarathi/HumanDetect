"""Approach 08: open COCO detectors on a server. Is there one clear person, and are they
not shown on a TV, monitor, laptop or phone screen?

Models (both Apache-2.0, loaded natively by `transformers`, no remote code):
  * RT-DETRv2 R18  (PekingU/rtdetr_v2_r18vd)          default
  * D-FINE small   (ustc-community/dfine-small-coco)  pass ?model=1

Rule, on the largest confident person box:
  NO_PERSON          no person scores >= min_person
  PERSON_TOO_SMALL   largest person covers < min_area of the photo
  NO_DOMINANT_PERSON a second person is nearly as big (< min_dominance x smaller)
  RECAPTURE          the person box lies mostly inside a detected screen or print
                     (tvmonitor / laptop / cell phone / book): a person shown on a
                     device, a printout or a magazine page. Phone frames are often
                     detected as "book", which also covers printed photos.
Ultralytics YOLO is excluded (AGPL-3.0): see THIRD_PARTY_LICENSES.md.
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
    ("RT-DETRv2 R18", "PekingU/rtdetr_v2_r18vd", "5650961749fa93567c0d46fc7f43ea4f9e914107"),
    ("D-FINE small", "ustc-community/dfine-small-coco", "f79e65b5fbb33ceb9d3ebba042955d7410c608f8"),
]
CONTAINERS = {"tvmonitor", "laptop", "cell phone", "book"}  # screens and prints

MODEL = Tunable("model", "Model: 0 = RT-DETRv2, 1 = D-FINE", 0, 1, 0, 0)
MIN_PERSON = Tunable("min_person", "Min person confidence", 0.3, 0.95, 0.6, 2)
MIN_AREA = Tunable("min_area", "Min person area (share of photo)", 0.01, 0.5, 0.08, 2)
MIN_DOMINANCE = Tunable("min_dominance", "Min size ratio, largest / 2nd person", 1.0, 4.0, 2.0, 1)
MIN_SCREEN = Tunable("min_screen", "Min screen / print confidence", 0.15, 0.9, 0.3, 2)
MIN_INSIDE = Tunable("min_inside", "Share of person box inside a screen / print = recapture", 0.5, 1.0, 0.7, 2)


def area(b: tuple[float, float, float, float]) -> float:
    return max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])


def inside_share(inner, outer) -> float:
    """Share of `inner`'s area that lies inside `outer` (boxes as x0, y0, x1, y1)."""
    x0, y0 = max(inner[0], outer[0]), max(inner[1], outer[1])
    x1, y1 = min(inner[2], outer[2]), min(inner[3], outer[3])
    a = area(inner)
    return area((x0, y0, x1, y1)) / a if a > 0 else 0.0


class DeepDetector:
    id = "08"
    title = "Open deep detectors"
    score_label = "person confidence"
    tunables = [MODEL, MIN_PERSON, MIN_AREA, MIN_DOMINANCE, MIN_SCREEN, MIN_INSIDE]

    def __init__(self):
        self._models: dict[int, tuple] = {}

    def load(self) -> None:
        self._get(0)  # D-FINE loads on first request for it

    def _get(self, index: int):
        if index not in self._models:
            import torch
            from transformers import AutoImageProcessor, AutoModelForObjectDetection

            from humandetect_server.device import torch_device

            _, model_id, revision = MODELS[index]
            device = torch_device()
            processor = AutoImageProcessor.from_pretrained(model_id, revision=revision)
            model = AutoModelForObjectDetection.from_pretrained(model_id, revision=revision, use_safetensors=True)
            model.eval().to(device)
            self._models[index] = (torch, processor, model, device)
        return self._models[index]

    def detect(self, image: Image.Image, index: int, threshold: float = 0.2) -> list[tuple[str, float, tuple]]:
        """[(label, score, (x0, y0, x1, y1) normalized)] for every detection >= threshold."""
        torch, processor, model, device = self._get(index)
        w, h = image.size
        with torch.no_grad():
            inputs = processor(images=image, return_tensors="pt").to(device)
            outputs = model(**inputs)
        found = processor.post_process_object_detection(outputs, target_sizes=[(h, w)], threshold=threshold)[0]
        out = []
        for score, label, box in zip(found["scores"].tolist(), found["labels"].tolist(), found["boxes"].tolist()):
            x0, y0, x1, y1 = box
            out.append((model.config.id2label[label], score,
                        (max(0, x0 / w), max(0, y0 / h), min(1, x1 / w), min(1, y1 / h))))
        return out

    def check(self, image: Image.Image, params: dict[str, float]) -> Result:
        index = int(round(param(params, MODEL)))
        min_person, min_area = param(params, MIN_PERSON), param(params, MIN_AREA)
        min_dom, min_screen, min_inside = param(params, MIN_DOMINANCE), param(params, MIN_SCREEN), param(params, MIN_INSIDE)

        found = self.detect(image, index)
        persons = sorted([d for d in found if d[0] == "person" and d[1] >= min_person], key=lambda d: -area(d[2]))
        screens = [d for d in found if d[0] in CONTAINERS and d[1] >= min_screen]
        marks = [Mark((b[0], b[1], b[2] - b[0], b[3] - b[1]), f"{label} {s:.2f}")
                 for label, s, b in found if (label == "person" and s >= min_person) or (label in CONTAINERS and s >= min_screen)]
        details = [("Model", MODELS[index][0]),
                   ("People found", str(len(persons))),
                   ("Screens / prints found", ", ".join(f"{l} {s:.2f}" for l, s, _ in screens) or "none")]
        if not persons:
            best = max((s for l, s, _ in found if l == "person"), default=0.0)
            return Result(False, best, ["NO_PERSON"], details, marks)

        _, score, box = persons[0]
        reasons = []
        details.append(("Largest person area", f"{area(box) * 100:.1f} % of photo"))
        if area(box) < min_area:
            reasons.append("PERSON_TOO_SMALL")
        if len(persons) > 1 and area(persons[1][2]) > 0 and area(box) / area(persons[1][2]) < min_dom:
            reasons.append("NO_DOMINANT_PERSON")
        for label, s, screen in screens:
            share = inside_share(box, screen)
            if share >= min_inside:
                reasons.append("RECAPTURE")
                details.append(("Person inside", f"{label} ({share * 100:.0f} % of the person box)"))
                break
        return Result(not reasons, score, reasons, details, marks)
