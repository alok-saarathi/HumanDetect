// Final capture on the phone: is a person visible?
//
// Same question the server asks in humandetect_server/final_capture.py.
// One confident face, large enough. A turned head and a second face still pass.
// A photo of a screen or of a print passes when a face is visible.

import 'dart:ui';

import '../../core/check.dart';
import '../a01_face_detection/blazeface.dart';

const presenceMinConfidence = 0.6;
const presenceMinFaceArea = 0.04;

class PresenceVerdict {
  const PresenceVerdict(this.passed, this.score, this.reasons, {this.top});

  final bool passed;
  final double score;
  final List<String> reasons;
  final Face? top;
}

PresenceVerdict judgePresence(
  List<Face> faces, {
  double minConfidence = presenceMinConfidence,
  double minFaceArea = presenceMinFaceArea,
}) {
  if (faces.isEmpty) {
    return const PresenceVerdict(false, 0, ['NO_FACE']);
  }
  final confident = faces.where((f) => f.score >= minConfidence).toList();
  if (confident.isEmpty) {
    final best = faces.map((f) => f.score).reduce((a, b) => a > b ? a : b);
    return PresenceVerdict(false, best, const ['LOW_CONFIDENCE']);
  }
  confident.sort((a, b) => b.area.compareTo(a.area));
  final top = confident.first;
  final reasons = <String>[
    if (top.area < minFaceArea) 'FACE_TOO_SMALL',
  ];
  return PresenceVerdict(reasons.isEmpty, top.score, reasons, top: top);
}

class FacePresenceCheck extends PhotoCheck {
  BlazeFace? _detector;

  @override
  String get id => 'final';

  @override
  String get title => 'Final capture';

  @override
  String get scoreLabel => 'detector confidence';

  @override
  List<Tunable> get tunables => const [];

  @override
  Future<void> prepare() async => _detector ??= await BlazeFace.load();

  @override
  Future<CheckResult> check(CapturedPhoto photo) async {
    final detector = _detector;
    if (detector == null) throw StateError('BlazeFace is not loaded.');
    final watch = Stopwatch()..start();
    final image = photo.image;
    final faces = detector.detect(image.rgb, image.width, image.height);
    final verdict = judgePresence(faces);
    watch.stop();
    final top = verdict.top;
    return CheckResult(
      passed: verdict.passed,
      score: verdict.score,
      reasons: verdict.reasons,
      latency: watch.elapsed,
      details: [
        ('Faces found', '${faces.length}'),
        if (top != null)
          (
            'Largest face area',
            '${(top.area * 100).toStringAsFixed(1)} % of photo',
          ),
        ('Model', 'BlazeFace short-range, 128×128'),
      ],
      marks: [
        for (final f in faces)
          PhotoMark(
            box: Rect.fromLTWH(f.x, f.y, f.w, f.h),
            label: f.score.toStringAsFixed(2),
          ),
      ],
    );
  }
}
