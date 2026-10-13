import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../../core/image_ops.dart';

/// Converts a raw YUV_420_888 camera frame (sensor orientation) into an upright RGB
/// image as the user sees it: rotated clockwise by [rotationDegrees] (the camera's
/// sensor orientation, phone held in portrait) and, for the front camera, mirrored
/// like the preview.
RgbImage yuvToUprightRgb(
  CameraImage frame,
  int rotationDegrees, {
  required bool mirror,
}) {
  final rawW = frame.width, rawH = frame.height;
  final rotation = rotationDegrees % 360;
  final outW = rotation % 180 == 0 ? rawW : rawH;
  final outH = rotation % 180 == 0 ? rawH : rawW;
  final yPlane = frame.planes[0],
      uPlane = frame.planes[1],
      vPlane = frame.planes[2];
  final yBytes = yPlane.bytes, uBytes = uPlane.bytes, vBytes = vPlane.bytes;
  final yRow = yPlane.bytesPerRow,
      uRow = uPlane.bytesPerRow,
      vRow = vPlane.bytesPerRow;
  final uPix = uPlane.bytesPerPixel ?? 1, vPix = vPlane.bytesPerPixel ?? 1;
  final out = Uint8List(outW * outH * 3);
  var o = 0;
  for (var oy = 0; oy < outH; oy++) {
    for (var ox = 0; ox < outW; ox++) {
      final mx = mirror ? outW - 1 - ox : ox;
      final int rx, ry;
      switch (rotation) {
        case 90:
          rx = oy;
          ry = rawH - 1 - mx;
        case 180:
          rx = rawW - 1 - mx;
          ry = rawH - 1 - oy;
        case 270:
          rx = rawW - 1 - oy;
          ry = mx;
        default:
          rx = mx;
          ry = oy;
      }
      final y = yBytes[ry * yRow + rx];
      final u = uBytes[(ry >> 1) * uRow + (rx >> 1) * uPix] - 128;
      final v = vBytes[(ry >> 1) * vRow + (rx >> 1) * vPix] - 128;
      // BT.601 full range (JFIF).
      out[o++] = (y + 1.402 * v).round().clamp(0, 255);
      out[o++] = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
      out[o++] = (y + 1.772 * u).round().clamp(0, 255);
    }
  }
  return RgbImage(outW, outH, out);
}
