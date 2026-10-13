// Decision rule for approach 01. Mirrors approaches/01-face-detection/rules.py.

import 'dart:math' as math;

import 'blazeface.dart';

/// Nose protrusion in front of the eye line, as a fraction of the distance between the
/// eyes; turns the nose's sideways offset into an approximate yaw angle.
const noseDepthRatio = 0.55;

class FaceRules {
  FaceRules({
    this.minConfidence = 0.6,
    this.minFaceArea = 0.04,
    this.minDominance = 2.0,
    this.maxYawDeg = 35.0,
  });

  double minConfidence; // T_conf
  double minFaceArea; // A_min: largest face box / image area
  double minDominance; // R_dom: largest face area / second largest
  double maxYawDeg; // P_max
}

class FaceVerdict {
  const FaceVerdict(
    this.passed,
    this.score,
    this.reasons, {
    this.top,
    this.yawDeg,
  });

  final bool passed;
  final double score;
  final List<String> reasons;
  final Face? top;
  final double? yawDeg;
}

/// Approximate head yaw in degrees from the eye and nose keypoints (0 = frontal).
/// [aspect] = image width / height, so the math happens in square pixels.
double estimateYaw(Face face, double aspect) {
  final (lx, ly) = face.keypoints[0];
  final (rx, ry) = face.keypoints[1];
  final (nx, ny) = face.keypoints[2];
  final ex = (rx - lx) * aspect, ey = ry - ly;
  final eyeDist2 = ex * ex + ey * ey;
  if (eyeDist2 == 0) return 90;
  final mx = (lx + rx) / 2, my = (ly + ry) / 2;
  final offset = ((nx - mx) * aspect * ex + (ny - my) * ey) / eyeDist2;
  return math.atan(offset / noseDepthRatio) * 180 / math.pi;
}

FaceVerdict judgeFaces(List<Face> faces, double aspect, FaceRules rules) {
  if (faces.isEmpty) return const FaceVerdict(false, 0, ['NO_FACE']);
  final confident = faces.where((f) => f.score >= rules.minConfidence).toList();
  if (confident.isEmpty) {
    return FaceVerdict(
      false,
      faces.map((f) => f.score).reduce(math.max),
      const ['LOW_CONFIDENCE'],
    );
  }
  confident.sort((a, b) => b.area.compareTo(a.area));
  final top = confident.first;
  final reasons = <String>[];
  if (top.area < rules.minFaceArea) reasons.add('FACE_TOO_SMALL');
  if (confident.length > 1) {
    final second = confident[1].area;
    if (second > 0 && top.area / second < rules.minDominance) {
      reasons.add('NO_DOMINANT_FACE');
    }
  }
  final yaw = estimateYaw(top, aspect);
  if (yaw.abs() > rules.maxYawDeg) reasons.add('FACE_NOT_FRONTAL');
  return FaceVerdict(
    reasons.isEmpty,
    top.score,
    reasons,
    top: top,
    yawDeg: yaw,
  );
}
