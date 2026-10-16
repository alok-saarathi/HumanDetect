import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/a05_active_liveness/face_align.dart';
import 'package:humandetect_app/approaches/a05_active_liveness/liveness_session.dart';

FrameObservation sample({
  double x = 0.5,
  double y = 0.5,
  double area = 0.12,
  double yaw = 0,
  int count = 1,
  double presence = 0.99,
}) => FrameObservation(
  faceCount: count,
  presence: presence,
  faceArea: area,
  centerX: x,
  centerY: y,
  ear: 0.3,
  yaw: yaw,
);

void main() {
  test('a missing or off-center face stays red', () {
    expect(
      judgeAlignment(const FrameObservation(faceCount: 0)).hint,
      'Put your face in the box',
    );
    expect(judgeAlignment(sample(x: 0.1)).aligned, isFalse);
    expect(judgeAlignment(sample(x: 0.1)).hint, 'Move your face to the center');
  });

  test('a small or turned face is told how to fix it', () {
    expect(judgeAlignment(sample(area: 0.02)).hint, 'Move closer');
    expect(
      judgeAlignment(sample(yaw: 0.5)).hint,
      'Look straight at the camera',
    );
  });

  test('a centered face large enough turns the box green', () {
    final cue = judgeAlignment(sample());
    expect(cue.aligned, isTrue);
    expect(cue.hint, 'Hold still. You can start the check.');
  });
}
