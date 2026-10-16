"""Final capture: is a person visible?

The phone asks BlazeFace the same question first and only uploads when that
passes. This module is the server copy of that check. A gallery file, a photo
of a screen, and a photo of a printed photograph all pass when a face is
visible. Duplicates are allowed. There is no liveness, recapture, or
duplicate step.

The detector is approaches/01-face-detection/blazeface.py (MediaPipe BlazeFace
short-range). The rule is narrower than approach 01: one confident face, large
enough to be the subject. Head turn and a second face do not fail the photo.
"""

from __future__ import annotations

import importlib.util
import sys
import threading
from pathlib import Path

from PIL import Image

from .contract import Mark, Result, Tunable, param

ROOT = Path(__file__).resolve().parents[2]
_BLAZEFACE = ROOT / "approaches" / "01-face-detection" / "blazeface.py"

MIN_CONFIDENCE = Tunable("min_confidence", "Min confidence", 0.5, 0.95, 0.6, 2)
MIN_FACE_AREA = Tunable(
    "min_face_area", "Min face area (share of photo)", 0.005, 0.2, 0.04, 3
)

_lock = threading.Lock()
_checker: FacePresence | None = None


def judge_presence(faces: list, min_confidence: float, min_face_area: float) -> Result:
    """`faces` are BlazeFace detections: `.score` and `.box` as (x, y, w, h)."""
    details = [("Faces found", str(len(faces))), ("Model", "BlazeFace short-range")]
    marks = [
        Mark(tuple(face.box), f"{face.score:.2f}")
        for face in faces
    ]
    if not faces:
        return Result(False, 0.0, ["NO_FACE"], details, marks)
    confident = [face for face in faces if face.score >= min_confidence]
    if not confident:
        return Result(
            False, max(face.score for face in faces), ["LOW_CONFIDENCE"], details, marks
        )
    top = max(confident, key=lambda face: face.box[2] * face.box[3])
    area = top.box[2] * top.box[3]
    details.insert(1, ("Largest face area", f"{area * 100:.1f} % of photo"))
    reasons = ["FACE_TOO_SMALL"] if area < min_face_area else []
    return Result(not reasons, top.score, reasons, details, marks)


class FacePresence:
    """Loads BlazeFace once and judges one upright RGB image."""

    def load(self) -> None:
        if getattr(self, "_detector", None) is not None:
            return
        name = "humandetect_blazeface"
        if name in sys.modules:
            module = sys.modules[name]
        else:
            spec = importlib.util.spec_from_file_location(name, _BLAZEFACE)
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            spec.loader.exec_module(module)
        self._detector = module.BlazeFace()

    def check(self, image: Image.Image, params: dict[str, float]) -> Result:
        faces = self._detector.detect(image)
        return judge_presence(
            faces, param(params, MIN_CONFIDENCE), param(params, MIN_FACE_AREA)
        )


def describe() -> dict:
    """What the route checks. Does not load the model."""
    return {
        "id": "final-capture",
        "title": "Final capture",
        "question": "Is a person visible in this photo?",
        "phone": "BlazeFace short-range on the device. One confident face, large enough.",
        "server": "The same BlazeFace check. This result is the decision.",
        "passes_when": [
            "a face is visible, including from the gallery",
            "a photo of a screen or of a printed photograph",
            "the same photo uploaded again",
        ],
        "tunables": [MIN_CONFIDENCE.json(), MIN_FACE_AREA.json()],
    }


def get_checker() -> FacePresence:
    """The shared checker, created and loaded on first call."""
    global _checker
    with _lock:
        if _checker is None:
            checker = FacePresence()
            checker.load()
            _checker = checker
        return _checker
