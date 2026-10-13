"""Face Mesh V2 landmarks + blink and head-turn signals: reference implementation.

Mirrored by app/lib/approaches/a05_active_liveness/. Pipeline:
    BlazeFace (approach 01) -> square ROI around the face, 1.5x the box (25% margin per side)
    -> crop to 256x256, pixels in [0, 1] -> Face Mesh V2 -> 478 landmarks
    -> eye aspect ratio (blink) and yaw (head turn)

Model: MediaPipe Face Mesh V2 (face_landmarks_detector.tflite), Apache-2.0.
"""

import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-face-detection"))
from blazeface import Face, resize_bilinear  # noqa: E402

MESH_SIZE = 256
ROI_SCALE = 1.5
DEFAULT_MODEL = Path(__file__).resolve().parents[2] / "app/assets/models/face_landmarks_detector.tflite"

# Eye landmark indices in the 478-point mesh, ordered p1..p6 for the eye aspect ratio:
# p1/p4 are the eye corners, p2/p6 and p3/p5 are upper/lower lid pairs.
EYE_A = (33, 160, 158, 133, 153, 144)
EYE_B = (362, 385, 387, 263, 373, 380)
NOSE_TIP = 1
# Face-oval extremes, used for yaw: left/right cheek edge.
CHEEK_A, CHEEK_B = 234, 454


@dataclass
class Roi:
    """Square region in original-image pixels."""

    cx: float
    cy: float
    size: float


def roi_from_face(face: Face, width: int, height: int) -> Roi:
    x, y, w, h = face.box
    cx, cy = (x + w / 2) * width, (y + h / 2) * height
    return Roi(cx, cy, max(w * width, h * height) * ROI_SCALE)


def crop(pixels: np.ndarray, roi: Roi) -> np.ndarray:
    """Bilinear-sample the ROI into a MESH_SIZE x MESH_SIZE crop (zero outside the image)."""
    h, w = pixels.shape[:2]
    step = roi.size / MESH_SIZE
    xs = roi.cx - roi.size / 2 + (np.arange(MESH_SIZE) + 0.5) * step - 0.5
    ys = roi.cy - roi.size / 2 + (np.arange(MESH_SIZE) + 0.5) * step - 0.5
    padded = np.zeros((h + 2, w + 2, 3), dtype=np.float32)
    padded[1:-1, 1:-1] = pixels
    xs, ys = np.clip(xs + 1, 0, w + 1), np.clip(ys + 1, 0, h + 1)
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    x1, y1 = np.minimum(x0 + 1, w + 1), np.minimum(y0 + 1, h + 1)
    fx, fy = (xs - x0)[None, :, None], (ys - y0)[:, None, None]
    top = padded[y0][:, x0] * (1 - fx) + padded[y0][:, x1] * fx
    bottom = padded[y1][:, x0] * (1 - fx) + padded[y1][:, x1] * fx
    return top * (1 - fy) + bottom * fy


def eye_aspect_ratio(lm: np.ndarray, idx: tuple[int, ...]) -> float:
    p = lm[list(idx), :2]
    vertical = np.linalg.norm(p[1] - p[5]) + np.linalg.norm(p[2] - p[4])
    return float(vertical / (2 * np.linalg.norm(p[0] - p[3])))


def yaw_signal(lm: np.ndarray) -> float:
    """Nose position between the two cheek edges, -1..1 (0 = frontal, sign = image side)."""
    a, b, nose = lm[CHEEK_A, 0], lm[CHEEK_B, 0], lm[NOSE_TIP, 0]
    left, right = min(a, b), max(a, b)
    if right - left < 1e-6:
        return 0.0
    return float(2 * (nose - left) / (right - left) - 1)


class FaceMesh:
    def __init__(self, model_path: Path | str = DEFAULT_MODEL, input_range: tuple[float, float] = (0.0, 1.0)):
        from ai_edge_litert.interpreter import Interpreter

        self.interpreter = Interpreter(model_path=str(model_path))
        self.interpreter.allocate_tensors()
        self.input = self.interpreter.get_input_details()[0]["index"]
        self.outputs = [d["index"] for d in self.interpreter.get_output_details()]
        self.lo, self.hi = input_range

    def landmarks(self, img: Image.Image, face: Face) -> tuple[np.ndarray, float]:
        """Returns (478, 3) landmarks in original-image pixels and the face-presence score."""
        pixels = np.asarray(img.convert("RGB"), dtype=np.float32)
        roi = roi_from_face(face, pixels.shape[1], pixels.shape[0])
        patch = crop(pixels, roi) / 255.0 * (self.hi - self.lo) + self.lo
        self.interpreter.set_tensor(self.input, patch[None].astype(np.float32))
        self.interpreter.invoke()
        raw = self.interpreter.get_tensor(self.outputs[0]).reshape(-1, 3)
        presence = float(1 / (1 + np.exp(-self.interpreter.get_tensor(self.outputs[1]).reshape(-1)[0])))
        scale = roi.size / MESH_SIZE
        lm = raw.copy()
        lm[:, 0] = roi.cx - roi.size / 2 + raw[:, 0] * scale
        lm[:, 1] = roi.cy - roi.size / 2 + raw[:, 1] * scale
        lm[:, 2] = raw[:, 2] * scale
        return lm, presence


__all__ = ["FaceMesh", "eye_aspect_ratio", "yaw_signal", "EYE_A", "EYE_B", "resize_bilinear"]
