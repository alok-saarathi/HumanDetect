import 'dart:math' as math;
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
  return const AlignCue(true, 'Stay aligned');
}

/// Watches for one blink while the face stays inside the guide.
/// Leaving the guide before the blink clears the progress.
class HeldBlink {
  bool ready = false;
  double? baselineEar;
  double minEar = double.infinity;

  bool _closed = false;
  final _open = <double>[];
  DateTime? _since;

  static const settle = Duration(milliseconds: 400);

  void update({
    required bool aligned,
    required double? ear,
    required DateTime now,
    double closeRatio = 0.6,
    double reopenRatio = 0.85,
  }) {
    if (ready) return;
    if (!aligned || ear == null) {
      _clear();
      return;
    }
    _since ??= now;
    if (baselineEar == null) {
      _open.add(ear);
      if (_open.length >= 3 && now.difference(_since!) >= settle) {
        final sorted = [..._open]..sort();
        baselineEar = sorted[sorted.length ~/ 2];
      }
      return;
    }
    minEar = math.min(minEar, ear);
    if (ear < baselineEar! * closeRatio) _closed = true;
    if (_closed && ear > baselineEar! * reopenRatio) ready = true;
  }

  void reset() {
    ready = false;
    _clear();
  }

  void _clear() {
    baselineEar = null;
    minEar = double.infinity;
    _closed = false;
    _open.clear();
    _since = null;
  }
}
