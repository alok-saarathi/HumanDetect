"""Checks our Face Mesh pipeline (face_mesh.py) against Google's mediapipe FaceLandmarker.

Usage: uv run --group models python approaches/05-active-liveness/verify_against_mediapipe.py FACE_LANDMARKER_TASK IMAGE [IMAGE ...]

FACE_LANDMARKER_TASK is face_landmarker.task (app/tool/fetch_models.sh downloads it to a temp
folder; download it again from the URL in that script to keep a copy). For each image with a
face, prints the mean landmark error as a share of face width, and both pipelines' eye
aspect ratios and yaw signals.
"""

import sys

import mediapipe as mp
import numpy as np
from PIL import Image

from face_mesh import EYE_A, EYE_B, FaceMesh, eye_aspect_ratio, yaw_signal

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1] / "01-face-detection"))
from blazeface import BlazeFace  # noqa: E402


def main(task: str, paths: list[str]) -> int:
    detector, mesh = BlazeFace(), FaceMesh()
    vision = mp.tasks.vision
    options = vision.FaceLandmarkerOptions(base_options=mp.tasks.BaseOptions(model_asset_path=task), num_faces=1)
    worst = 0.0
    with vision.FaceLandmarker.create_from_options(options) as landmarker:
        for path in paths:
            img = Image.open(path).convert("RGB")
            w, h = img.size
            faces = detector.detect(img)
            ref = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.asarray(img))).face_landmarks
            if not faces or not ref:
                print(f"{path}: skipped (ours found {len(faces)} faces, mediapipe {len(ref)})")
                continue
            face = max(faces, key=lambda f: f.box[2] * f.box[3])
            lm, presence = mesh.landmarks(img, face)
            r = np.array([(p.x * w, p.y * h) for p in ref[0]])
            err = float(np.abs(lm[:, :2] - r).mean() / (face.box[2] * w))
            worst = max(worst, err)
            print(
                f"{path}: presence {presence:.2f}, mean landmark error {err * 100:.2f}% of face width, "
                f"EAR {eye_aspect_ratio(lm, EYE_A):.3f}/{eye_aspect_ratio(lm, EYE_B):.3f} "
                f"(mediapipe {eye_aspect_ratio(r, EYE_A):.3f}/{eye_aspect_ratio(r, EYE_B):.3f}), "
                f"yaw {yaw_signal(lm):.3f} (mediapipe {yaw_signal(r):.3f})"
            )
    return 0 if worst < 0.02 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
