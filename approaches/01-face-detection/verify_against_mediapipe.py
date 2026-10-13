"""Checks our BlazeFace decoder (blazeface.py) against Google's mediapipe package.

Usage: uv run --group models python approaches/01-face-detection/verify_against_mediapipe.py IMAGE [IMAGE ...]

For each image, prints both detectors' faces and the largest box/keypoint difference.
Differences of about 1% of the image size are expected: the two resize images differently.
"""

import sys

import mediapipe as mp
import numpy as np
from PIL import Image

from blazeface import DEFAULT_MODEL, BlazeFace


def mediapipe_faces(path: str) -> list[tuple[float, np.ndarray, np.ndarray]]:
    vision = mp.tasks.vision
    options = vision.FaceDetectorOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(DEFAULT_MODEL)),
        min_detection_confidence=0.5,
    )
    # Load through Pillow: mediapipe's own loader keeps grayscale JPEGs single-channel.
    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.asarray(Image.open(path).convert("RGB")))
    with vision.FaceDetector.create_from_options(options) as detector:
        result = detector.detect(image)
    out = []
    for d in result.detections:
        b = d.bounding_box
        box = np.array([b.origin_x / image.width, b.origin_y / image.height, b.width / image.width, b.height / image.height])
        kps = np.array([(k.x, k.y) for k in d.keypoints])
        out.append((d.categories[0].score, box, kps))
    return out


def main(paths: list[str]) -> int:
    ours = BlazeFace()
    worst = 0.0
    for path in paths:
        faces = ours.detect(Image.open(path))
        reference = mediapipe_faces(path)
        print(f"{path}: ours={len(faces)} faces, mediapipe={len(reference)} faces")
        if len(faces) != len(reference):
            print("  MISMATCH in face count")
            worst = float("inf")
            continue
        for f in faces:
            # Pair each of our faces with the nearest reference face by box center.
            center = np.array([f.box[0] + f.box[2] / 2, f.box[1] + f.box[3] / 2])
            score, box, kps = min(reference, key=lambda r: np.linalg.norm(r[1][:2] + r[1][2:] / 2 - center))
            box_diff = float(np.abs(np.array(f.box) - box).max())
            kp_diff = float(np.abs(np.array(f.keypoints) - kps).max())
            worst = max(worst, box_diff, kp_diff)
            print(
                f"  ours score={f.score:.3f} box={np.round(f.box, 3).tolist()}\n"
                f"  mp   score={score:.3f} box={np.round(box, 3).tolist()}\n"
                f"  max |box diff|={box_diff:.4f}  max |keypoint diff|={kp_diff:.4f}"
            )
    print(f"worst difference: {worst:.4f}")
    return 0 if worst < 0.02 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
