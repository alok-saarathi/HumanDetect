import 'dart:ui';

import '../../core/check.dart';
import 'blazeface.dart';
import 'face_rules.dart';

/// Approach 01: is there one clear, frontal, big-enough face in the photo?
class FaceDetectionCheck extends PhotoCheck {
  late final BlazeFace _detector;
  final _confidence = Tunable(
    label: 'Min confidence',
    min: 0.5,
    max: 0.95,
    initial: 0.6,
  );
  final _area = Tunable(
    label: 'Min face area (share of photo)',
    min: 0.005,
    max: 0.2,
    initial: 0.04,
    decimals: 3,
  );
  final _dominance = Tunable(
    label: 'Min size ratio, largest / 2nd face',
    min: 1.0,
    max: 4.0,
    initial: 2.0,
    decimals: 1,
  );
  final _yaw = Tunable(
    label: 'Max head turn (degrees)',
    min: 10,
    max: 60,
    initial: 35,
    decimals: 0,
  );

  @override
  String get id => '01';

  @override
  String get title => 'Face detection';

  @override
  String get scoreLabel => 'detector confidence';

  @override
  List<Tunable> get tunables => [_confidence, _area, _dominance, _yaw];

  @override
  Future<void> prepare() async => _detector = await BlazeFace.load();

  @override
  Future<CheckResult> check(CapturedPhoto photo) async {
    final watch = Stopwatch()..start();
    final image = photo.image;
    final faces = _detector.detect(image.rgb, image.width, image.height);
    final verdict = judgeFaces(
      faces,
      image.width / image.height,
      FaceRules(
        minConfidence: _confidence.value,
        minFaceArea: _area.value,
        minDominance: _dominance.value,
        maxYawDeg: _yaw.value,
      ),
    );
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
        if (verdict.yawDeg != null)
          ('Head turn (approx.)', '${verdict.yawDeg!.toStringAsFixed(0)}°'),
        ('Model', 'BlazeFace short-range, 128×128'),
      ],
      marks: [
        for (final f in faces)
          PhotoMark(
            box: Rect.fromLTWH(f.x, f.y, f.w, f.h),
            points: [for (final (x, y) in f.keypoints) Offset(x, y)],
            label: f.score.toStringAsFixed(2),
          ),
      ],
    );
  }
}
