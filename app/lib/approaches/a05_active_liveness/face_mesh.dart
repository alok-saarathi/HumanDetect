// Face Mesh V2 landmarks plus blink and head-turn signals. Mirrors
// approaches/05-active-liveness/face_mesh.py.
//
// Model: MediaPipe Face Mesh V2 (face_landmarks_detector.tflite), Apache-2.0.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/image_ops.dart';
import '../../core/models.dart';
import '../a01_face_detection/blazeface.dart';

const meshSize = 256;
const roiScale = 1.5; // 25 % margin on each side of the face box

/// Eye landmarks ordered p1..p6 for the eye aspect ratio (p1/p4 corners, p2/p6 and
/// p3/p5 upper/lower lid pairs).
const eyeA = [33, 160, 158, 133, 153, 144];
const eyeB = [362, 385, 387, 263, 373, 380];
const noseTip = 1;
const cheekA = 234, cheekB = 454;

class MeshResult {
  const MeshResult(this.landmarks, this.presence);

  /// 478 x (x, y, z), x and y in frame pixels.
  final Float32List landmarks;
  final double presence;
}

class FaceMesh {
  FaceMesh._(this._interpreter);

  final Interpreter _interpreter;

  static Future<FaceMesh> load() async =>
      FaceMesh._(await ModelStore.load(ModelAssets.faceMesh));

  MeshResult run(RgbImage frame, Face face) {
    final w = frame.width, h = frame.height;
    final cx = (face.x + face.w / 2) * w, cy = (face.y + face.h / 2) * h;
    final size = math.max(face.w * w, face.h * h) * roiScale;
    final input = meshCrop(frame, cx, cy, size);
    _interpreter
      ..setFloatInput(0, input)
      ..invoke();
    final raw = _interpreter.floatOutput('Identity');
    final presenceLogit = _interpreter.floatOutput('Identity_1')[0];
    final scale = size / meshSize;
    final lm = Float32List(raw.length);
    for (var i = 0; i < raw.length; i += 3) {
      lm[i] = cx - size / 2 + raw[i] * scale;
      lm[i + 1] = cy - size / 2 + raw[i + 1] * scale;
      lm[i + 2] = raw[i + 2] * scale;
    }
    return MeshResult(lm, 1 / (1 + math.exp(-presenceLogit)));
  }
}

/// Bilinear crop of a square ROI (center [cx], [cy], side [size], frame pixels) into
/// meshSize x meshSize, zero outside the frame, pixels scaled to [0, 1].
/// Mirrors `crop` in face_mesh.py (which returns 0..255; this divides by 255).
Float32List meshCrop(RgbImage frame, double cx, double cy, double size) {
  final w = frame.width, h = frame.height, rgb = frame.rgb;
  final step = size / meshSize;
  final out = Float32List(meshSize * meshSize * 3);
  // Sample a frame padded by one black pixel on every side.
  double px(int x, int y, int k) => (x <= 0 || y <= 0 || x > w || y > h)
      ? 0.0
      : rgb[((y - 1) * w + x - 1) * 3 + k].toDouble();
  var o = 0;
  for (var j = 0; j < meshSize; j++) {
    final sy = (cy - size / 2 + (j + 0.5) * step - 0.5 + 1).clamp(0.0, h + 1.0);
    final y0 = sy.floor(), y1 = math.min(y0 + 1, h + 1);
    final fy = sy - y0;
    for (var i = 0; i < meshSize; i++) {
      final sx = (cx - size / 2 + (i + 0.5) * step - 0.5 + 1).clamp(
        0.0,
        w + 1.0,
      );
      final x0 = sx.floor(), x1 = math.min(x0 + 1, w + 1);
      final fx = sx - x0;
      for (var k = 0; k < 3; k++) {
        final top = px(x0, y0, k) * (1 - fx) + px(x1, y0, k) * fx;
        final bottom = px(x0, y1, k) * (1 - fx) + px(x1, y1, k) * fx;
        out[o++] = (top * (1 - fy) + bottom * fy) / 255.0;
      }
    }
  }
  return out;
}

double eyeAspectRatio(Float32List lm, List<int> idx) {
  double dist(int a, int b) {
    final dx = lm[idx[a] * 3] - lm[idx[b] * 3],
        dy = lm[idx[a] * 3 + 1] - lm[idx[b] * 3 + 1];
    return math.sqrt(dx * dx + dy * dy);
  }

  return (dist(1, 5) + dist(2, 4)) / (2 * dist(0, 3));
}

/// Nose position between the two cheek edges, -1..1 (0 = frontal, sign = image side).
double yawSignal(Float32List lm) {
  final a = lm[cheekA * 3], b = lm[cheekB * 3], nose = lm[noseTip * 3];
  final left = math.min(a, b), right = math.max(a, b);
  if (right - left < 1e-6) return 0;
  return 2 * (nose - left) / (right - left) - 1;
}
