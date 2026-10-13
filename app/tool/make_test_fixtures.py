"""Writes app/test/fixtures/parity.json: expected outputs of the Python reference
implementations on synthetic inputs, so the Dart tests can prove the app computes the
same thing. Inputs are generated from a formula (no images, no personal data).

Usage (from the repo root): uv run --group models python app/tool/make_test_fixtures.py
"""

import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
for sub in ("01-face-detection", "02-zero-shot-clip", "04-metadata-forensics", "05-active-liveness"):
    sys.path.insert(0, str(ROOT / "approaches" / sub))

import blazeface  # noqa: E402
import face_mesh  # noqa: E402
import forensics  # noqa: E402
import rules  # noqa: E402
import zero_shot  # noqa: E402
from PIL import Image  # noqa: E402


def formula_image(w: int, h: int) -> np.ndarray:
    """Same formula as formulaImage() in test/parity_test.dart."""
    y, x, c = np.mgrid[0:h, 0:w, 0:3]
    return (((x * 31 + y * 17 + c * 7) ^ (x * y)) & 255).astype(np.float32)


def stats(a: np.ndarray, step: int = 997) -> dict:
    flat = a.reshape(-1).astype(np.float64)
    return {"len": flat.size, "sum": float(flat.sum()), "sumsq": float((flat**2).sum()), "samples": {str(i): float(flat[i]) for i in range(0, flat.size, step)}}


def main() -> None:
    out: dict = {}

    # Shared bilinear resize.
    img = formula_image(37, 23)
    out["resize"] = {"in": [37, 23], "out": [16, 29], "values": [round(float(v), 4) for v in blazeface.resize_bilinear(img, 16, 29).reshape(-1)]}

    # 01 letterbox.
    tensor, lb = blazeface.letterbox(Image.fromarray(formula_image(50, 31).astype(np.uint8)))
    out["letterbox"] = {"in": [50, 31], "lb": [lb.scaled_w, lb.scaled_h, lb.off_x, lb.off_y], **stats(tensor)}

    # 01 decode + weighted NMS + undo letterbox, with planted detections.
    regressors = np.zeros((896, 16), dtype=np.float32)
    logits = np.full(896, -10.0, dtype=np.float32)
    rng = np.random.default_rng(7)
    planted = {300: 2.0, 301: 1.5, 333: 0.3, 700: 0.8}
    for i, logit in planted.items():
        logits[i] = logit
        regressors[i, :4] = rng.normal([1, -1, 30, 34], [2, 2, 3, 3])
        regressors[i, 4:] = rng.normal(0, 6, 12)
    lb = blazeface.Letterbox(128, 96, 0, 16)
    faces = blazeface.to_faces(blazeface.weighted_nms(blazeface.decode(regressors, logits)), lb)
    out["blazeface"] = {
        "planted": [{"index": i, "logit": float(logits[i]), "regressors": [float(v) for v in regressors[i]]} for i in planted],
        "lb": [lb.scaled_w, lb.scaled_h, lb.off_x, lb.off_y],
        "faces": [{"score": f.score, "box": list(map(float, f.box)), "keypoints": [list(map(float, k)) for k in f.keypoints]} for f in faces],
    }

    # 01 rules.
    face = blazeface.Face(0.9, (0.3, 0.2, 0.25, 0.3), [(0.38, 0.3), (0.5, 0.31), (0.47, 0.37), (0.44, 0.43), (0.3, 0.33), (0.55, 0.34)])
    small = blazeface.Face(0.8, (0.7, 0.7, 0.1, 0.1), [(0.72, 0.72)] * 6)
    verdict = rules.judge([face, small], 0.75)
    out["rules"] = {"yaw": rules.estimate_yaw(face, 0.75), "passed": verdict.passed, "reasons": verdict.reasons, "score": verdict.score}

    # 02 preprocessing (with and without box downsampling) and scoring.
    out["clip"] = {}
    for w, h in ((700, 500), (1000, 950)):
        x = zero_shot.preprocess(Image.fromarray(formula_image(w, h).astype(np.uint8)))
        out["clip"][f"{w}x{h}"] = stats(x)
    rng = np.random.default_rng(3)
    emb = rng.normal(size=(6, 8)).astype(np.float32)
    emb /= np.linalg.norm(emb, axis=1, keepdims=True)
    buckets = ["genuine", "genuine", "no_human", "no_human", "recapture", "recapture"]
    prompts = zero_shot.PromptSet("test", [f"p{i}" for i in range(6)], buckets, emb, 5.0, {"no_human": "NO_HUMAN", "recapture": "RECAPTURE"})
    cases = []
    for near in (0, 4):  # close to a genuine prompt, then close to a recapture prompt
        image_emb = emb[near] + 0.6 * rng.normal(size=8).astype(np.float32)
        image_emb /= np.linalg.norm(image_emb)
        v = zero_shot.judge(image_emb, prompts, 0.6)
        cases.append({"image": image_emb.tolist(), "passed": v.passed, "score": v.score, "reasons": v.reasons, "bucket_scores": v.bucket_scores})
    out["zero_shot"] = {"embeddings": emb.tolist(), "buckets": buckets, "logit_scale": 5.0, "threshold": 0.6, "cases": cases}

    # 04 forensic signals (small image, and one big enough to trigger box downsampling).
    out["forensics"] = {}
    for w, h in ((300, 260), (2100, 1300)):
        gray = forensics.luma(formula_image(w, h))
        small_copy = forensics.analysis_copy(gray)
        out["forensics"][f"{w}x{h}"] = {
            "sharpness": forensics.sharpness(small_copy), "glare": forensics.glare(small_copy),
            "contrast": forensics.contrast(small_copy), "moire": forensics.moire(gray),
        }

    # 05 face-mesh crop.
    crop = face_mesh.crop(formula_image(120, 90), face_mesh.Roi(50.3, 40.7, 70.2)) / 255.0
    out["mesh_crop"] = {"frame": [120, 90], "roi": [50.3, 40.7, 70.2], **stats(crop)}

    path = Path(__file__).resolve().parents[1] / "test/fixtures/parity.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(out, indent=1))
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
