// BlazeFace short-range face detector. Mirrors approaches/01-face-detection/blazeface.py
// line for line: letterbox to 128x128 -> pixels to [-1, 1] -> model -> decode against
// 896 SSD anchors -> sigmoid scores -> weighted NMS -> undo the letterbox.
//
// Model: MediaPipe BlazeFace short-range, Apache-2.0.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/image_ops.dart';
import '../../core/models.dart';

const blazeInputSize = 128;
const blazeMinScore = 0.5;
const blazeNmsIou = 0.3;

class Face {
  const Face(this.score, this.x, this.y, this.w, this.h, this.keypoints);

  final double score;

  /// Box (xmin, ymin, width, height), normalized to the original image.
  final double x, y, w, h;

  /// 6 keypoints (x, y) normalized to the original image: eye on the image's left,
  /// eye on the image's right, nose tip, mouth, ear tragion on the image's left, on the right.
  final List<(double, double)> keypoints;

  double get area => w * h;
}

class Letterbox {
  const Letterbox(this.scaledW, this.scaledH, this.offX, this.offY);

  final int scaledW, scaledH, offX, offY;
}

/// 896 anchor centers (x, y), input-normalized. Stride 8: 16x16 grid, 2 per cell;
/// stride 16: 8x8 grid, 6 per cell. All anchors are 1.0 x 1.0.
final Float32List blazeAnchors = () {
  final out = <double>[];
  for (final (stride, perCell) in const [(8, 2), (16, 6)]) {
    final n = blazeInputSize ~/ stride;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        for (var k = 0; k < perCell; k++) {
          out
            ..add((x + 0.5) / n)
            ..add((y + 0.5) / n);
        }
      }
    }
  }
  return Float32List.fromList(out);
}();

/// Fits the image into 128x128 keeping its aspect ratio, padded with black.
/// Returns the model input (NHWC, values in [-1, 1]) and the letterbox geometry.
(Float32List, Letterbox) letterbox(List<num> rgb, int width, int height) {
  final scale = blazeInputSize / math.max(width, height);
  final sw = math.max(1, roundHalfUp(width * scale));
  final sh = math.max(1, roundHalfUp(height * scale));
  final lb = Letterbox(
    sw,
    sh,
    (blazeInputSize - sw) ~/ 2,
    (blazeInputSize - sh) ~/ 2,
  );
  final input = Float32List(blazeInputSize * blazeInputSize * 3)
    ..fillRange(0, blazeInputSize * blazeInputSize * 3, -1.0);
  final resized = resizeBilinear(rgb, width, height, 3, sw, sh);
  for (var y = 0; y < sh; y++) {
    final dst = ((y + lb.offY) * blazeInputSize + lb.offX) * 3;
    final src = y * sw * 3;
    for (var i = 0; i < sw * 3; i++) {
      input[dst + i] = resized[src + i] / 127.5 - 1.0;
    }
  }
  return (input, lb);
}

/// Raw outputs -> candidates (score, 16 values: xmin, ymin, xmax, ymax, kp0x, kp0y, ...),
/// in input-normalized coordinates.
List<(double, Float64List)> decode(Float32List regressors, Float32List logits) {
  final out = <(double, Float64List)>[];
  for (var i = 0; i < logits.length; i++) {
    final score = 1.0 / (1.0 + math.exp(-logits[i].clamp(-100.0, 100.0)));
    if (score < blazeMinScore) continue;
    final r = i * 16;
    final ax = blazeAnchors[i * 2], ay = blazeAnchors[i * 2 + 1];
    final xc = regressors[r] / blazeInputSize + ax;
    final yc = regressors[r + 1] / blazeInputSize + ay;
    final w = regressors[r + 2] / blazeInputSize;
    final h = regressors[r + 3] / blazeInputSize;
    final v = Float64List(16)
      ..[0] = xc - w / 2
      ..[1] = yc - h / 2
      ..[2] = xc + w / 2
      ..[3] = yc + h / 2;
    for (var k = 0; k < 6; k++) {
      v[4 + 2 * k] = regressors[r + 4 + 2 * k] / blazeInputSize + ax;
      v[5 + 2 * k] = regressors[r + 5 + 2 * k] / blazeInputSize + ay;
    }
    out.add((score, v));
  }
  return out;
}

double iou(Float64List a, Float64List b) {
  final ix = math.max(0.0, math.min(a[2], b[2]) - math.max(a[0], b[0]));
  final iy = math.max(0.0, math.min(a[3], b[3]) - math.max(a[1], b[1]));
  final inter = ix * iy;
  final union =
      (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter;
  return union > 0 ? inter / union : 0.0;
}

/// MediaPipe's weighted NMS: overlapping candidates merge into a score-weighted average
/// of their boxes and keypoints; the merged detection keeps the top score.
List<(double, Float64List)> weightedNms(
  List<(double, Float64List)> candidates,
) {
  var remaining = [...candidates]..sort((a, b) => b.$1.compareTo(a.$1));
  final out = <(double, Float64List)>[];
  while (remaining.isNotEmpty) {
    final (topScore, top) = remaining.first;
    final cluster = remaining
        .where((c) => iou(top, c.$2) >= blazeNmsIou)
        .toList();
    remaining = remaining.where((c) => iou(top, c.$2) < blazeNmsIou).toList();
    final merged = Float64List(16);
    var total = 0.0;
    for (final (s, v) in cluster) {
      total += s;
      for (var i = 0; i < 16; i++) {
        merged[i] += v[i] * s;
      }
    }
    for (var i = 0; i < 16; i++) {
      merged[i] /= total;
    }
    out.add((topScore, merged));
  }
  return out;
}

/// Undoes the letterbox: input-normalized -> original-image-normalized coordinates.
List<Face> toFaces(List<(double, Float64List)> detections, Letterbox lb) {
  double ux(double x) => (x * blazeInputSize - lb.offX) / lb.scaledW;
  double uy(double y) => (y * blazeInputSize - lb.offY) / lb.scaledH;
  return [
    for (final (score, v) in detections)
      Face(
        score,
        ux(v[0]),
        uy(v[1]),
        ux(v[2]) - ux(v[0]),
        uy(v[3]) - uy(v[1]),
        [for (var k = 0; k < 6; k++) (ux(v[4 + 2 * k]), uy(v[5 + 2 * k]))],
      ),
  ];
}

class BlazeFace {
  BlazeFace._(this._interpreter);

  final Interpreter _interpreter;

  static Future<BlazeFace> load() async =>
      BlazeFace._(await ModelStore.load(ModelAssets.blazeFace));

  List<Face> detect(List<num> rgb, int width, int height) {
    final (input, lb) = letterbox(rgb, width, height);
    _interpreter
      ..setFloatInput(0, input)
      ..invoke();
    final regressors = _interpreter.floatOutput('regressors');
    final logits = _interpreter.floatOutput('classificators');
    return toFaces(weightedNms(decode(regressors, logits)), lb);
  }
}
