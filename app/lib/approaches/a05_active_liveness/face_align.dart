import 'dart:ui';

import 'liveness_session.dart';

/// Where the face should sit, in the upright preview (0..1).
const alignGuide = Rect.fromLTRB(0.25, 0.18, 0.75, 0.78);

class AlignCue {
  const AlignCue(this.aligned, this.hint);

  final bool aligned;
  final String hint;
}

/// Red until the face is inside [alignGuide], large enough, and looking ahead.
AlignCue judgeAlignment(
  FrameObservation face, {
  double minFaceArea = 0.05,
  double maxYaw = 0.2,
}) {
  final x = face.centerX;
  final y = face.centerY;
  if (!face.hasFace || x == null || y == null) {
    return const AlignCue(false, 'Put your face in the box');
  }
  if (!alignGuide.contains(Offset(x, y))) {
    return const AlignCue(false, 'Move your face to the center');
  }
  if ((face.faceArea ?? 0) < minFaceArea) {
    return const AlignCue(false, 'Move closer');
  }
  if ((face.yaw?.abs() ?? 1) > maxYaw) {
    return const AlignCue(false, 'Look straight at the camera');
  }
  return const AlignCue(true, 'Hold still. You can start the check.');
}
