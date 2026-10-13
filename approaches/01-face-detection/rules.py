"""Decision rule for approach 01, shared by every detector variant.

Mirrored by app/lib/approaches/a01_face_detection/face_rules.dart.
Defaults are starting points only; tune them on the dev split.
"""

import math
from dataclasses import dataclass, field

from blazeface import Face

# Nose protrusion in front of the eye line, as a fraction of the distance between the
# eyes. Used to turn the nose's sideways offset into an approximate yaw angle.
NOSE_DEPTH_RATIO = 0.55


@dataclass
class FaceRules:
    min_confidence: float = 0.6  # T_conf
    min_face_area: float = 0.04  # A_min: largest face box / image area
    min_dominance: float = 2.0  # R_dom: largest face area / second largest
    max_yaw_deg: float = 35.0  # P_max


@dataclass
class Verdict:
    passed: bool
    score: float
    reasons: list[str] = field(default_factory=list)
    yaw_deg: float | None = None


def estimate_yaw(face: Face, aspect: float) -> float:
    """Approximate head yaw in degrees from the eye and nose keypoints (0 = frontal).

    `aspect` = image width / height, so the math happens in square pixels.
    """
    (lx, ly), (rx, ry), (nx, ny) = face.keypoints[0], face.keypoints[1], face.keypoints[2]
    ex, ey = (rx - lx) * aspect, ry - ly
    eye_dist2 = ex * ex + ey * ey
    if eye_dist2 == 0:
        return 90.0
    mx, my = (lx + rx) / 2, (ly + ry) / 2
    offset = ((nx - mx) * aspect * ex + (ny - my) * ey) / eye_dist2
    return math.degrees(math.atan(offset / NOSE_DEPTH_RATIO))


def judge(faces: list[Face], aspect: float, rules: FaceRules = FaceRules()) -> Verdict:
    """`aspect` = image width / height. Box width and height are normalized to their own
    image side, so width * height is the fraction of the image area the face covers."""
    confident = [f for f in faces if f.score >= rules.min_confidence]
    if not faces:
        return Verdict(False, 0.0, ["NO_FACE"])
    if not confident:
        return Verdict(False, max(f.score for f in faces), ["LOW_CONFIDENCE"])

    by_area = sorted(confident, key=lambda f: f.box[2] * f.box[3], reverse=True)
    top = by_area[0]
    reasons = []
    if top.box[2] * top.box[3] < rules.min_face_area:
        reasons.append("FACE_TOO_SMALL")
    if len(by_area) > 1:
        second = by_area[1].box[2] * by_area[1].box[3]
        if second > 0 and (top.box[2] * top.box[3]) / second < rules.min_dominance:
            reasons.append("NO_DOMINANT_FACE")
    yaw = estimate_yaw(top, aspect)
    if abs(yaw) > rules.max_yaw_deg:
        reasons.append("FACE_NOT_FRONTAL")
    return Verdict(not reasons, top.score, reasons, yaw)
