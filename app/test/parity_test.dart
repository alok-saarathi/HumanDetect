// Proves the app computes what the Python references compute, on synthetic inputs.
// Regenerate the fixture with: uv run --group models python app/tool/make_test_fixtures.py

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/a01_face_detection/blazeface.dart';
import 'package:humandetect_app/approaches/a01_face_detection/face_rules.dart';
import 'package:humandetect_app/approaches/a02_zero_shot/zero_shot_check.dart';
import 'package:humandetect_app/approaches/a04_forensics/forensics.dart';
import 'package:humandetect_app/approaches/a05_active_liveness/face_mesh.dart';
import 'package:humandetect_app/core/image_ops.dart';

/// Same formula as formula_image() in tool/make_test_fixtures.py.
RgbImage formulaImage(int w, int h) {
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        rgb[(y * w + x) * 3 + c] = ((x * 31 + y * 17 + c * 7) ^ (x * y)) & 255;
      }
    }
  }
  return RgbImage(w, h, rgb);
}

void expectStats(
  List<num> values,
  Map<String, dynamic> expected, {
  double tol = 1e-4,
}) {
  expect(values.length, expected['len']);
  var sum = 0.0, sumsq = 0.0;
  for (final v in values) {
    sum += v;
    sumsq += v * v;
  }
  expect(
    sum,
    closeTo(
      expected['sum'] as num,
      (expected['sum'] as num).abs() * 1e-5 + 1e-3,
    ),
  );
  expect(
    sumsq,
    closeTo(
      expected['sumsq'] as num,
      (expected['sumsq'] as num).abs() * 1e-5 + 1e-3,
    ),
  );
  (expected['samples'] as Map<String, dynamic>).forEach((index, value) {
    expect(
      values[int.parse(index)],
      closeTo(value as num, tol),
      reason: 'index $index',
    );
  });
}

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/parity.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('bilinear resize matches Python', () {
    final f = fixture['resize'] as Map<String, dynamic>;
    final out = resizeBilinear(formulaImage(37, 23).rgb, 37, 23, 3, 16, 29);
    final expected = (f['values'] as List).cast<num>();
    for (var i = 0; i < expected.length; i++) {
      expect(out[i], closeTo(expected[i], 1e-3));
    }
  });

  test('01 letterbox matches Python', () {
    final f = fixture['letterbox'] as Map<String, dynamic>;
    final (input, lb) = letterbox(formulaImage(50, 31).rgb, 50, 31);
    expect([lb.scaledW, lb.scaledH, lb.offX, lb.offY], f['lb']);
    expectStats(input, f);
  });

  test(
    '01 BlazeFace decode + weighted NMS + letterbox removal match Python',
    () {
      final f = fixture['blazeface'] as Map<String, dynamic>;
      final regressors = Float32List(896 * 16);
      final logits = Float32List(896)..fillRange(0, 896, -10);
      for (final p in (f['planted'] as List).cast<Map<String, dynamic>>()) {
        final i = p['index'] as int;
        logits[i] = (p['logit'] as num).toDouble();
        final r = (p['regressors'] as List).cast<num>();
        for (var k = 0; k < 16; k++) {
          regressors[i * 16 + k] = r[k].toDouble();
        }
      }
      final lbv = (f['lb'] as List).cast<int>();
      final faces = toFaces(
        weightedNms(decode(regressors, logits)),
        Letterbox(lbv[0], lbv[1], lbv[2], lbv[3]),
      );
      final expected = (f['faces'] as List).cast<Map<String, dynamic>>();
      expect(faces.length, expected.length);
      for (var i = 0; i < faces.length; i++) {
        final e = expected[i];
        final box = (e['box'] as List).cast<num>();
        expect(faces[i].score, closeTo(e['score'] as num, 1e-6));
        expect(
          [faces[i].x, faces[i].y, faces[i].w, faces[i].h],
          [for (final v in box) closeTo(v, 1e-5)],
        );
        final kps = (e['keypoints'] as List).cast<List>();
        for (var k = 0; k < 6; k++) {
          expect(faces[i].keypoints[k].$1, closeTo(kps[k][0] as num, 1e-5));
          expect(faces[i].keypoints[k].$2, closeTo(kps[k][1] as num, 1e-5));
        }
      }
    },
  );

  test('01 rules match Python', () {
    final f = fixture['rules'] as Map<String, dynamic>;
    const face = Face(0.9, 0.3, 0.2, 0.25, 0.3, [
      (0.38, 0.3),
      (0.5, 0.31),
      (0.47, 0.37),
      (0.44, 0.43),
      (0.3, 0.33),
      (0.55, 0.34),
    ]);
    const small = Face(0.8, 0.7, 0.7, 0.1, 0.1, [
      (0.72, 0.72),
      (0.72, 0.72),
      (0.72, 0.72),
      (0.72, 0.72),
      (0.72, 0.72),
      (0.72, 0.72),
    ]);
    expect(estimateYaw(face, 0.75), closeTo(f['yaw'] as num, 1e-9));
    final v = judgeFaces([face, small], 0.75, FaceRules());
    expect(v.passed, f['passed']);
    expect(v.reasons, f['reasons']);
    expect(v.score, closeTo(f['score'] as num, 1e-9));
  });

  test(
    '02 CLIP preprocessing matches Python (with and without box downsampling)',
    () {
      final f = fixture['clip'] as Map<String, dynamic>;
      for (final (w, h) in const [(700, 500), (1000, 950)]) {
        expectStats(
          clipPreprocess(formulaImage(w, h)),
          f['${w}x$h'] as Map<String, dynamic>,
          tol: 1e-5,
        );
      }
    },
  );

  test('02 zero-shot scoring matches Python', () {
    final f = fixture['zero_shot'] as Map<String, dynamic>;
    final embeddings = [
      for (final e in (f['embeddings'] as List))
        Float32List.fromList(
          (e as List).cast<num>().map((v) => v.toDouble()).toList(),
        ),
    ];
    final buckets = (f['buckets'] as List).cast<String>();
    final prompts = PromptSet(
      'test',
      'test',
      [for (var i = 0; i < buckets.length; i++) 'p$i'],
      buckets,
      embeddings,
      (f['logit_scale'] as num).toDouble(),
      const {'no_human': 'NO_HUMAN', 'recapture': 'RECAPTURE'},
    );
    for (final c in (f['cases'] as List).cast<Map<String, dynamic>>()) {
      final image = Float32List.fromList(
        (c['image'] as List).cast<num>().map((v) => v.toDouble()).toList(),
      );
      final v = judgeEmbedding(
        image,
        prompts,
        (f['threshold'] as num).toDouble(),
      );
      expect(v.passed, c['passed']);
      expect(v.reasons, c['reasons']);
      expect(v.score, closeTo(c['score'] as num, 1e-5));
      (c['bucket_scores'] as Map<String, dynamic>).forEach(
        (b, s) => expect(v.bucketScores[b], closeTo(s as num, 1e-5)),
      );
    }
  });

  test('04 forensic signals match Python', () {
    final f = fixture['forensics'] as Map<String, dynamic>;
    for (final (w, h) in const [(300, 260), (2100, 1300)]) {
      final e = f['${w}x$h'] as Map<String, dynamic>;
      final s = computeSignals(formulaImage(w, h));
      double rel(String k) => (e[k] as num).abs() * 1e-4 + 1e-6;
      expect(
        s.sharpness,
        closeTo(e['sharpness'] as num, rel('sharpness')),
        reason: 'sharpness ${w}x$h',
      );
      expect(
        s.glare,
        closeTo(e['glare'] as num, 1e-9),
        reason: 'glare ${w}x$h',
      );
      expect(
        s.contrast,
        closeTo(e['contrast'] as num, 1e-3),
        reason: 'contrast ${w}x$h',
      );
      expect(
        s.moire,
        closeTo(e['moire'] as num, 1e-4),
        reason: 'moire ${w}x$h',
      );
    }
  });

  test('05 face-mesh crop matches Python', () {
    final f = fixture['mesh_crop'] as Map<String, dynamic>;
    final roi = (f['roi'] as List).cast<num>();
    expectStats(
      meshCrop(
        formulaImage(120, 90),
        roi[0].toDouble(),
        roi[1].toDouble(),
        roi[2].toDouble(),
      ),
      f,
      tol: 1e-6,
    );
  });

  test('FFT matches a direct DFT', () {
    final random = math.Random(1);
    const n = 32;
    final re = Float64List.fromList([
      for (var i = 0; i < n; i++) random.nextDouble() - 0.5,
    ]);
    final im = Float64List.fromList([
      for (var i = 0; i < n; i++) random.nextDouble() - 0.5,
    ]);
    final (r0, i0) = (Float64List.fromList(re), Float64List.fromList(im));
    fft(re, im);
    for (var k = 0; k < n; k++) {
      var sr = 0.0, si = 0.0;
      for (var t = 0; t < n; t++) {
        final a = -2 * math.pi * k * t / n;
        sr += r0[t] * math.cos(a) - i0[t] * math.sin(a);
        si += r0[t] * math.sin(a) + i0[t] * math.cos(a);
      }
      expect(re[k], closeTo(sr, 1e-9));
      expect(im[k], closeTo(si, 1e-9));
    }
  });
}
