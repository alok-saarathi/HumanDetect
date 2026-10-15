// Image helpers shared by the approaches. Each function mirrors a Python reference
// (named in its comment) so laptop and phone results come from identical math.

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Interleaved 8-bit RGB pixels, upright (EXIF orientation already applied).
class RgbImage {
  RgbImage(this.width, this.height, this.rgb)
    : assert(rgb.length == width * height * 3);

  final int width;
  final int height;
  final Uint8List rgb;

  /// Decodes a JPEG and applies its EXIF orientation. Slow for big photos: call it
  /// from a background isolate.
  static RgbImage fromJpeg(Uint8List bytes) =>
      _fromDecoded(img.decodeJpg(bytes));

  /// Decodes a JPEG, PNG, GIF, WebP or BMP and applies EXIF orientation when present.
  /// Gallery picks use this. HEIC and other formats are transcoded to JPEG first.
  static RgbImage fromEncoded(Uint8List bytes) =>
      _fromDecoded(img.decodeImage(bytes));

  static RgbImage _fromDecoded(img.Image? decoded) {
    if (decoded == null) throw const FormatException('Not a decodable image');
    final upright = img.bakeOrientation(decoded);
    final rgb = upright.convert(numChannels: 3, format: img.Format.uint8);
    return RgbImage(
      rgb.width,
      rgb.height,
      rgb.getBytes(order: img.ChannelOrder.rgb),
    );
  }

  /// A smaller RGBA copy for showing on screen (long side <= [maxSide]).
  Uint8List previewRgba(int maxSide, void Function(int w, int h) size) {
    final scale = math.min(1.0, maxSide / math.max(width, height));
    final w = math.max(1, (width * scale + 0.5).floor());
    final h = math.max(1, (height * scale + 0.5).floor());
    final small = resizeBilinear(rgb, width, height, 3, w, h);
    final out = Uint8List(w * h * 4);
    for (var i = 0, j = 0; i < small.length; i += 3, j += 4) {
      out[j] = small[i].round().clamp(0, 255);
      out[j + 1] = small[i + 1].round().clamp(0, 255);
      out[j + 2] = small[i + 2].round().clamp(0, 255);
      out[j + 3] = 255;
    }
    size(w, h);
    return out;
  }

  /// Luma (BT.601) as floats, row-major.
  Float32List luma() {
    final out = Float32List(width * height);
    for (var i = 0, p = 0; i < out.length; i++, p += 3) {
      out[i] = rgb[p] * 0.299 + rgb[p + 1] * 0.587 + rgb[p + 2] * 0.114;
    }
    return out;
  }
}

typedef DecodedPhoto = ({
  RgbImage image,
  ({Uint8List rgba, int width, int height}) preview,
});

/// Decodes off the UI isolate.
///
/// Do not call [compute] or [Isolate.run] from a State method. Flutter inlines
/// `compute`, so the closure is built inside that method and sends the State,
/// including any [Future] it holds.
@pragma('vm:never-inline')
Future<DecodedPhoto> decodePhotoInBackground(
  Uint8List bytes, {
  required bool gallery,
}) async {
  final port = ReceivePort();
  try {
    await Isolate.spawn(_decodePhotoEntry, (port.sendPort, bytes, gallery));
    final result = await port.first;
    if (result is String) throw Exception(result);
    return result as DecodedPhoto;
  } finally {
    port.close();
  }
}

void _decodePhotoEntry((SendPort, Uint8List, bool) message) {
  final (send, bytes, gallery) = message;
  try {
    send.send(gallery ? _decodeEncoded(bytes) : _decodeJpeg(bytes));
  } catch (e) {
    send.send(e.toString());
  }
}

DecodedPhoto _decodeJpeg(Uint8List jpeg) =>
    _decodePhoto(jpeg, RgbImage.fromJpeg);

DecodedPhoto _decodeEncoded(Uint8List bytes) =>
    _decodePhoto(bytes, RgbImage.fromEncoded);

DecodedPhoto _decodePhoto(
  Uint8List bytes,
  RgbImage Function(Uint8List) decode,
) {
  final image = decode(bytes);
  var w = 0, h = 0;
  final rgba = image.previewRgba(900, (pw, ph) {
    w = pw;
    h = ph;
  });
  return (image: image, preview: (rgba: rgba, width: w, height: h));
}

/// Plain bilinear resize with half-pixel centers and no antialiasing (OpenCV
/// INTER_LINEAR). Mirrors `resize_bilinear` in approaches/01-face-detection/blazeface.py.
/// [src] holds [channels] interleaved values per pixel.
Float32List resizeBilinear(
  List<num> src,
  int inW,
  int inH,
  int channels,
  int outW,
  int outH,
) {
  final out = Float32List(outW * outH * channels);
  final x0s = Int32List(outW), x1s = Int32List(outW), fxs = Float64List(outW);
  for (var x = 0; x < outW; x++) {
    final sx = ((x + 0.5) * (inW / outW) - 0.5).clamp(0.0, inW - 1.0);
    x0s[x] = sx.floor();
    x1s[x] = math.min(x0s[x] + 1, inW - 1);
    fxs[x] = sx - x0s[x];
  }
  var o = 0;
  for (var y = 0; y < outH; y++) {
    final sy = ((y + 0.5) * (inH / outH) - 0.5).clamp(0.0, inH - 1.0);
    final y0 = sy.floor(), y1 = math.min(y0 + 1, inH - 1);
    final fy = sy - y0;
    final row0 = y0 * inW, row1 = y1 * inW;
    for (var x = 0; x < outW; x++) {
      final fx = fxs[x];
      final a = (row0 + x0s[x]) * channels, b = (row0 + x1s[x]) * channels;
      final c = (row1 + x0s[x]) * channels, d = (row1 + x1s[x]) * channels;
      for (var k = 0; k < channels; k++) {
        final top = src[a + k] * (1 - fx) + src[b + k] * fx;
        final bottom = src[c + k] * (1 - fx) + src[d + k] * fx;
        out[o++] = top * (1 - fy) + bottom * fy;
      }
    }
  }
  return out;
}

/// Averages non-overlapping factor x factor blocks ([factor] >= 2); leftover edge
/// rows/columns are dropped. Mirrors `box_downsample` in approaches/02-zero-shot-clip/zero_shot.py.
({Float32List data, int width, int height}) boxDownsample(
  List<num> src,
  int inW,
  int inH,
  int channels,
  int factor,
) {
  assert(factor >= 2);
  final outW = inW ~/ factor, outH = inH ~/ factor;
  final out = Float32List(outW * outH * channels);
  final norm = 1.0 / (factor * factor);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      for (var k = 0; k < channels; k++) {
        var sum = 0.0;
        for (var dy = 0; dy < factor; dy++) {
          final row = (y * factor + dy) * inW;
          for (var dx = 0; dx < factor; dx++) {
            sum += src[(row + x * factor + dx) * channels + k];
          }
        }
        out[(y * outW + x) * channels + k] = sum * norm;
      }
    }
  }
  return (data: out, width: outW, height: outH);
}

/// Round half up, matching `int(x + 0.5)` in the Python references.
int roundHalfUp(double x) => (x + 0.5).floor();
