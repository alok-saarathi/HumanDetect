// Approach 02: zero-shot classification with TinyCLIP. Mirrors
// approaches/02-zero-shot-clip/zero_shot.py (preprocess + judge).
//
// The exported image encoder takes NHWC RGB in [0, 1] and returns a normalized 512-d
// embedding; prompt embeddings come precomputed in tinyclip_prompts.json.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/check.dart';
import '../../core/image_ops.dart';
import '../../core/models.dart';

const clipImageSize = 224;
const genuineBucket = 'genuine';

/// Shorter side -> 224, center crop 224x224, scaled to [0, 1] (NHWC).
/// Large photos are first box-averaged by an integer factor (shorter side stays >= 448)
/// to avoid aliasing.
Float32List clipPreprocess(RgbImage image) {
  List<num> pixels = image.rgb;
  var w = image.width, h = image.height;
  final factor = math.min(w, h) ~/ (2 * clipImageSize);
  if (factor >= 2) {
    final down = boxDownsample(pixels, w, h, 3, factor);
    pixels = down.data;
    w = down.width;
    h = down.height;
  }
  final scale = clipImageSize / math.min(w, h);
  final rw = math.max(clipImageSize, roundHalfUp(w * scale));
  final rh = math.max(clipImageSize, roundHalfUp(h * scale));
  final resized = resizeBilinear(pixels, w, h, 3, rw, rh);
  final x0 = (rw - clipImageSize) ~/ 2, y0 = (rh - clipImageSize) ~/ 2;
  final out = Float32List(clipImageSize * clipImageSize * 3);
  for (var y = 0; y < clipImageSize; y++) {
    final src = ((y + y0) * rw + x0) * 3;
    final dst = y * clipImageSize * 3;
    for (var i = 0; i < clipImageSize * 3; i++) {
      out[dst + i] = resized[src + i] / 255.0;
    }
  }
  return out;
}

class PromptSet {
  PromptSet(
    this.version,
    this.model,
    this.texts,
    this.buckets,
    this.embeddings,
    this.logitScale,
    this.reasons,
  );

  factory PromptSet.fromJson(Map<String, dynamic> json) {
    final prompts = (json['prompts'] as List).cast<Map<String, dynamic>>();
    return PromptSet(
      json['prompt_version'] as String,
      json['model'] as String,
      [for (final p in prompts) p['text'] as String],
      [for (final p in prompts) p['bucket'] as String],
      [
        for (final p in prompts)
          Float32List.fromList(
            (p['embedding'] as List)
                .cast<num>()
                .map((v) => v.toDouble())
                .toList(),
          ),
      ],
      (json['logit_scale'] as num).toDouble(),
      (json['reasons'] as Map).cast<String, String>(),
    );
  }

  final String version;
  final String model;
  final List<String> texts;
  final List<String> buckets;
  final List<Float32List> embeddings;
  final double logitScale;
  final Map<String, String> reasons;
}

class ZeroShotVerdict {
  const ZeroShotVerdict(
    this.passed,
    this.score,
    this.reasons,
    this.bucketScores,
    this.bestPrompt,
  );

  final bool passed;
  final double score; // probability of the genuine bucket
  final List<String> reasons;
  final Map<String, double> bucketScores;
  final Map<String, String> bestPrompt; // bucket -> its best-matching prompt
}

/// Each bucket is scored by its best-matching prompt, then softmax across buckets, so
/// buckets with more prompts don't win just by having more prompts.
ZeroShotVerdict judgeEmbedding(
  Float32List embedding,
  PromptSet prompts,
  double threshold,
) {
  final best = <String, double>{};
  final bestPrompt = <String, String>{};
  for (var p = 0; p < prompts.texts.length; p++) {
    final e = prompts.embeddings[p];
    var dot = 0.0;
    for (var i = 0; i < e.length; i++) {
      dot += e[i] * embedding[i];
    }
    final logit = prompts.logitScale * dot;
    final bucket = prompts.buckets[p];
    if (logit > (best[bucket] ?? double.negativeInfinity)) {
      best[bucket] = logit;
      bestPrompt[bucket] = prompts.texts[p];
    }
  }
  final maxLogit = best.values.reduce(math.max);
  final exps = {
    for (final e in best.entries) e.key: math.exp(e.value - maxLogit),
  };
  final total = exps.values.reduce((a, b) => a + b);
  final scores = {for (final e in exps.entries) e.key: e.value / total};
  final score = scores[genuineBucket] ?? 0.0;
  if (score >= threshold) {
    return ZeroShotVerdict(true, score, const [], scores, bestPrompt);
  }
  final worst = scores.keys
      .where((b) => b != genuineBucket)
      .reduce((a, b) => scores[a]! >= scores[b]! ? a : b);
  return ZeroShotVerdict(
    false,
    score,
    [prompts.reasons[worst] ?? worst.toUpperCase()],
    scores,
    bestPrompt,
  );
}

class ZeroShotCheck extends PhotoCheck {
  Interpreter? _encoder;
  PromptSet? _prompts;
  final _threshold = Tunable(
    label: 'Min "genuine" probability',
    min: 0.2,
    max: 0.9,
    initial: 0.5,
  );

  @override
  String get id => '02';

  @override
  String get title => 'Zero-shot classification';

  @override
  String get scoreLabel => 'probability of "genuine"';

  @override
  List<Tunable> get tunables => [_threshold];

  @override
  Future<void> prepare() async {
    // The pipeline calls this on every photo. A late final can be set once;
    // the second photo threw LateInitializationError.
    _encoder ??= await ModelStore.load(ModelAssets.tinyClip);
    _prompts ??= PromptSet.fromJson(
      jsonDecode(await rootBundle.loadString(ModelAssets.tinyClipPrompts))
          as Map<String, dynamic>,
    );
  }

  @override
  Future<CheckResult> check(CapturedPhoto photo) async {
    final encoder = _encoder;
    final prompts = _prompts;
    if (encoder == null || prompts == null) {
      throw StateError('TinyCLIP is not loaded.');
    }
    final watch = Stopwatch()..start();
    final input = clipPreprocess(photo.image);
    encoder.setFloatInput(0, input);
    try {
      encoder.invoke();
    } on StateError catch (e) {
      throw StateError('TinyCLIP could not score this photo (${e.message}).');
    }
    final embedding = encoder.floatOutputAt(0);
    final v = judgeEmbedding(embedding, prompts, _threshold.value);
    watch.stop();
    final ranked = v.bucketScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return CheckResult(
      passed: v.passed,
      score: v.score,
      reasons: v.reasons,
      latency: watch.elapsed,
      details: [
        for (final e in ranked)
          (
            '${e.key} ${(e.value * 100).toStringAsFixed(0)} %',
            'best match: "${v.bestPrompt[e.key]}"',
          ),
        (
          'Prompts',
          'version ${prompts.version}, ${prompts.texts.length} prompts',
        ),
        ('Model', prompts.model.split('@').first.split('/').last),
      ],
    );
  }
}
