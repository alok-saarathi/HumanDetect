"""BlazeFace short-range face detector: reference implementation.

Mirrored line for line by app/lib/approaches/a01_face_detection/blazeface.dart, so
laptop and phone results come from identical logic. Follows MediaPipe's
face_detection_short_range graph:

    letterbox to 128x128 -> scale pixels to [-1, 1] -> run model
    -> decode against 896 SSD anchors -> sigmoid scores -> weighted NMS
    -> undo the letterbox

Model: MediaPipe BlazeFace short-range, Apache-2.0 (fetched by app/tool/fetch_models.sh).
"""

from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

INPUT_SIZE = 128
MIN_SCORE = 0.5
NMS_IOU = 0.3
DEFAULT_MODEL = Path(__file__).resolve().parents[2] / "app/assets/models/blaze_face_short_range.tflite"


@dataclass
class Face:
    score: float
    # xmin, ymin, width, height, normalized to the original image (0..1)
    box: tuple[float, float, float, float]
    # 6 keypoints (x, y), normalized to the original image. Order: eye on the image's left,
    # eye on the image's right, nose tip, mouth, ear tragion on the image's left, on the image's right.
    keypoints: list[tuple[float, float]]


@dataclass
class Letterbox:
    scaled_w: int  # image width after scaling into the 128x128 input
    scaled_h: int
    off_x: int  # padding on the left, in input pixels
    off_y: int


def make_anchors() -> np.ndarray:
    """896 anchor centers (x, y) in input-normalized coordinates.

    Stride 8 gives a 16x16 grid with 2 anchors per cell; stride 16 gives an 8x8 grid
    with 6 anchors per cell (three merged SSD layers). All anchors are 1.0 x 1.0.
    """
    out = []
    for stride, per_cell in ((8, 2), (16, 6)):
        n = INPUT_SIZE // stride
        for y in range(n):
            for x in range(n):
                for _ in range(per_cell):
                    out.append(((x + 0.5) / n, (y + 0.5) / n))
    return np.array(out, dtype=np.float32)


ANCHORS = make_anchors()


def resize_bilinear(pixels: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    """Plain bilinear resize with half-pixel centers and no antialiasing (OpenCV's
    INTER_LINEAR, which MediaPipe uses). The Dart port does exactly the same."""
    in_h, in_w = pixels.shape[:2]
    xs = np.clip((np.arange(out_w) + 0.5) * (in_w / out_w) - 0.5, 0, in_w - 1)
    ys = np.clip((np.arange(out_h) + 0.5) * (in_h / out_h) - 0.5, 0, in_h - 1)
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    x1, y1 = np.minimum(x0 + 1, in_w - 1), np.minimum(y0 + 1, in_h - 1)
    fx, fy = (xs - x0)[None, :, None], (ys - y0)[:, None, None]
    top = pixels[y0][:, x0] * (1 - fx) + pixels[y0][:, x1] * fx
    bottom = pixels[y1][:, x0] * (1 - fx) + pixels[y1][:, x1] * fx
    return top * (1 - fy) + bottom * fy


def letterbox(img: Image.Image) -> tuple[np.ndarray, Letterbox]:
    """Fit the image into 128x128 keeping its aspect ratio, padded with black.

    Returns the model input (1, 128, 128, 3) scaled to [-1, 1] and the letterbox geometry.
    """
    img = img.convert("RGB")
    w, h = img.size
    scale = INPUT_SIZE / max(w, h)
    sw, sh = max(1, int(w * scale + 0.5)), max(1, int(h * scale + 0.5))  # round half up, as in Dart
    lb = Letterbox(sw, sh, (INPUT_SIZE - sw) // 2, (INPUT_SIZE - sh) // 2)
    canvas = np.zeros((INPUT_SIZE, INPUT_SIZE, 3), dtype=np.float32)
    canvas[lb.off_y : lb.off_y + sh, lb.off_x : lb.off_x + sw] = resize_bilinear(
        np.asarray(img, dtype=np.float32), sw, sh
    )
    return (canvas / 127.5 - 1.0)[None], lb


def decode(regressors: np.ndarray, logits: np.ndarray) -> list[tuple[float, np.ndarray]]:
    """Raw model outputs -> candidates as (score, values).

    `values` holds 16 numbers in input-normalized coordinates:
    [xmin, ymin, xmax, ymax, kp0x, kp0y, ..., kp5x, kp5y].
    """
    regressors = regressors.reshape(-1, 16)
    scores = 1.0 / (1.0 + np.exp(-np.clip(logits.reshape(-1).astype(np.float64), -100.0, 100.0)))
    out = []
    for i in np.nonzero(scores >= MIN_SCORE)[0]:
        r = regressors[i] / INPUT_SIZE
        ax, ay = ANCHORS[i]
        xc, yc, w, h = r[0] + ax, r[1] + ay, r[2], r[3]
        values = np.empty(16, dtype=np.float32)
        values[0:4] = (xc - w / 2, yc - h / 2, xc + w / 2, yc + h / 2)
        values[4::2] = r[4::2] + ax
        values[5::2] = r[5::2] + ay
        out.append((float(scores[i]), values))
    return out


def iou(a: np.ndarray, b: np.ndarray) -> float:
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return float(inter / union) if union > 0 else 0.0


def weighted_nms(candidates: list[tuple[float, np.ndarray]]) -> list[tuple[float, np.ndarray]]:
    """MediaPipe's weighted NMS: overlapping candidates are merged into a score-weighted
    average of their boxes and keypoints; the merged detection keeps the top score."""
    remaining = sorted(candidates, key=lambda c: c[0], reverse=True)
    out = []
    while remaining:
        top_score, top = remaining[0]
        cluster = [c for c in remaining if iou(top, c[1]) >= NMS_IOU]
        remaining = [c for c in remaining if iou(top, c[1]) < NMS_IOU]
        weights = np.array([s for s, _ in cluster], dtype=np.float32)
        merged = (np.stack([v for _, v in cluster]) * weights[:, None]).sum(0) / weights.sum()
        out.append((top_score, merged))
    return out


def to_faces(detections: list[tuple[float, np.ndarray]], lb: Letterbox) -> list[Face]:
    """Undo the letterbox: input-normalized -> original-image-normalized coordinates."""

    def ux(x: float) -> float:
        return (x * INPUT_SIZE - lb.off_x) / lb.scaled_w

    def uy(y: float) -> float:
        return (y * INPUT_SIZE - lb.off_y) / lb.scaled_h

    faces = []
    for score, v in detections:
        x0, y0, x1, y1 = ux(v[0]), uy(v[1]), ux(v[2]), uy(v[3])
        kps = [(ux(v[4 + 2 * k]), uy(v[5 + 2 * k])) for k in range(6)]
        faces.append(Face(score, (x0, y0, x1 - x0, y1 - y0), kps))
    return faces


class BlazeFace:
    def __init__(self, model_path: Path | str = DEFAULT_MODEL):
        from ai_edge_litert.interpreter import Interpreter

        self.interpreter = Interpreter(model_path=str(model_path))
        self.interpreter.allocate_tensors()
        self.input = self.interpreter.get_input_details()[0]["index"]
        outputs = {d["name"]: d["index"] for d in self.interpreter.get_output_details()}
        self.regressors, self.classificators = outputs["regressors"], outputs["classificators"]

    def raw(self, img: Image.Image) -> tuple[np.ndarray, np.ndarray, Letterbox]:
        tensor, lb = letterbox(img)
        self.interpreter.set_tensor(self.input, tensor)
        self.interpreter.invoke()
        return (
            self.interpreter.get_tensor(self.regressors)[0],
            self.interpreter.get_tensor(self.classificators)[0],
            lb,
        )

    def detect(self, img: Image.Image) -> list[Face]:
        regressors, logits, lb = self.raw(img)
        return to_faces(weighted_nms(decode(regressors, logits)), lb)
