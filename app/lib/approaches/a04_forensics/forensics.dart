// Recapture and metadata forensics: hand-written signals, no model. Mirrors
// approaches/04-metadata-forensics/forensics.py. Pure Dart, safe to run in an isolate.

import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/image_ops.dart';

const analysisSize =
    512; // long side of the copy used for sharpness, glare and contrast
const patchSize =
    512; // side of the full-resolution center patch used for the spectrum
const minRadius = 0.15,
    maxRadius = 0.95; // spectrum band, as a fraction of Nyquist
const topPeaks = 8;

class ForensicSignals {
  const ForensicSignals(this.sharpness, this.glare, this.contrast, this.moire);

  final double sharpness; // variance of the Laplacian
  final double glare; // share of pixels with luma >= 250
  final double contrast; // 99th minus 1st luma percentile
  final double
  moire; // mean of the strongest spectrum peaks over the per-ring median
}

ForensicSignals computeSignals(RgbImage image) {
  final gray = image.luma();
  final small = analysisCopy(gray, image.width, image.height);
  return ForensicSignals(
    laplacianVariance(small.data, small.width, small.height),
    glareShare(small.data),
    lumaSpread(small.data),
    moireScore(gray, image.width, image.height),
  );
}

/// Grayscale copy with long side [analysisSize] (box-averaged first to avoid aliasing).
({Float32List data, int width, int height}) analysisCopy(
  Float32List gray,
  int w,
  int h,
) {
  List<num> pixels = gray;
  final factor = math.max(w, h) ~/ (2 * analysisSize);
  if (factor >= 2) {
    final down = boxDownsample(pixels, w, h, 1, factor);
    pixels = down.data;
    w = down.width;
    h = down.height;
  }
  final scale = analysisSize / math.max(w, h);
  final ow = math.max(1, roundHalfUp(w * scale)),
      oh = math.max(1, roundHalfUp(h * scale));
  return (data: resizeBilinear(pixels, w, h, 1, ow, oh), width: ow, height: oh);
}

double laplacianVariance(Float32List p, int w, int h) {
  var sum = 0.0, sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final lap = p[i - 1] + p[i + 1] + p[i - w] + p[i + w] - 4 * p[i];
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

double glareShare(Float32List p) {
  var bright = 0;
  for (final v in p) {
    if (v >= 250) bright++;
  }
  return bright / p.length;
}

/// numpy.percentile with linear interpolation.
double percentile(List<double> sorted, double q) {
  final pos = q / 100 * (sorted.length - 1);
  final lo = pos.floor(), hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

double lumaSpread(Float32List p) {
  final sorted = List<double>.from(p)..sort();
  return percentile(sorted, 99) - percentile(sorted, 1);
}

double median(List<double> values) {
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// In-place radix-2 FFT of length n (a power of two).
void fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final angle = -2 * math.pi / len;
    final wr = math.cos(angle), wi = math.sin(angle);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k, b = a + len ~/ 2;
        final tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr;
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

/// Screens and halftone prints leave sharp periodic peaks in the spectrum; natural
/// scenes have smooth spectra. Mean of the [topPeaks] largest excesses over each
/// frequency ring's median, in log units.
double moireScore(Float32List gray, int w, int h) {
  var n = patchSize;
  while (n > 8 && n > math.min(w, h)) {
    n ~/= 2; // largest power of two that fits, down to 8
  }
  if (n > math.min(w, h)) return 0; // image too small to analyse
  final x0 = (w - n) ~/ 2, y0 = (h - n) ~/ 2;
  var mean = 0.0;
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      mean += gray[(y0 + y) * w + x0 + x];
    }
  }
  mean /= n * n;
  final window = Float64List.fromList([
    for (var k = 0; k < n; k++) 0.5 - 0.5 * math.cos(2 * math.pi * k / (n - 1)),
  ]);
  final re = Float64List(n * n), im = Float64List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      re[y * n + x] =
          (gray[(y0 + y) * w + x0 + x] - mean) * window[y] * window[x];
    }
  }
  final rowRe = Float64List(n), rowIm = Float64List(n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      rowRe[x] = re[y * n + x];
      rowIm[x] = im[y * n + x];
    }
    fft(rowRe, rowIm);
    for (var x = 0; x < n; x++) {
      re[y * n + x] = rowRe[x];
      im[y * n + x] = rowIm[x];
    }
  }
  for (var x = 0; x < n; x++) {
    for (var y = 0; y < n; y++) {
      rowRe[y] = re[y * n + x];
      rowIm[y] = im[y * n + x];
    }
    fft(rowRe, rowIm);
    for (var y = 0; y < n; y++) {
      re[y * n + x] = rowRe[y];
      im[y * n + x] = rowIm[y];
    }
  }
  // Group band values by integer ring radius.
  final rings = <int, List<double>>{};
  final ringOf = <int>[], values = <double>[];
  final half = n ~/ 2;
  for (var ky = 0; ky < n; ky++) {
    final fy = ky < half ? ky : ky - n;
    for (var kx = 0; kx < n; kx++) {
      final fx = kx < half ? kx : kx - n;
      final dist = math.sqrt(fx * fx + fy * fy);
      final radius = dist / half;
      if (radius < minRadius || radius > maxRadius) continue;
      final i = ky * n + kx;
      final v = math.log(1 + math.sqrt(re[i] * re[i] + im[i] * im[i]));
      final ring = dist.round();
      (rings[ring] ??= []).add(v);
      ringOf.add(ring);
      values.add(v);
    }
  }
  final medians = {for (final e in rings.entries) e.key: median(e.value)};
  final excess = [
    for (var i = 0; i < values.length; i++) values[i] - medians[ringOf[i]]!,
  ]..sort();
  final top = excess.sublist(math.max(0, excess.length - topPeaks));
  return top.isEmpty ? 0 : top.reduce((a, b) => a + b) / top.length;
}
