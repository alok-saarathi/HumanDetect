import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/a05_active_liveness/liveness_session.dart';

const _open = 0.30;

FrameObservation face({
  double ear = _open,
  double yaw = 0,
  double x = 0.5,
  int count = 1,
}) => FrameObservation(
  faceCount: count,
  presence: 0.99,
  faceArea: 0.12,
  centerX: x,
  centerY: 0.5,
  ear: ear,
  yaw: yaw,
);

void main() {
  late LivenessSession session;
  late DateTime now;

  void feed(FrameObservation o, {int frames = 1}) {
    for (var i = 0; i < frames; i++) {
      now = now.add(const Duration(milliseconds: 50));
      session.update(o, now);
    }
  }

  void position() => feed(face(), frames: 20); // 1 s still, frontal

  setUp(() {
    session = LivenessSession(LivenessSettings(), random: math.Random(4));
    now = DateTime(2026);
  });

  test('passes when the person blinks and turns as asked', () {
    position();
    expect(session.phase, LivenessPhase.challenge);
    expect(session.baselineEar, _open);
    for (final c in session.challenges) {
      switch (c) {
        case Challenge.blink:
          feed(face(ear: 0.1), frames: 2);
          feed(face(), frames: 2);
        case Challenge.turnLeft:
          feed(face(yaw: -0.5), frames: 3);
          feed(face(), frames: 2);
        case Challenge.turnRight:
          feed(face(yaw: 0.5), frames: 3);
          feed(face(), frames: 2);
      }
    }
    expect(session.phase, LivenessPhase.passed);
    expect(session.timeline.length, 2);
  });

  test('a still photo times out', () {
    position();
    feed(face(), frames: 200); // 10 s of a face that never moves
    expect(session.phase, LivenessPhase.failed);
    expect(session.failReason, 'TIMEOUT');
  });

  test('turning the wrong way does not count', () {
    position();
    final turn = session.challenges.firstWhere((c) => c != Challenge.blink);
    if (session.current == Challenge.blink) {
      feed(face(ear: 0.1), frames: 2);
      feed(face(), frames: 2);
    }
    expect(session.current, turn);
    feed(face(yaw: turn == Challenge.turnLeft ? 0.5 : -0.5), frames: 10);
    expect(session.current, turn);
  });

  test('fails when the face leaves the frame', () {
    position();
    feed(
      const FrameObservation(faceCount: 0),
      frames: 20,
    ); // 1 s without a face
    expect(session.failReason, 'FACE_LOST');
  });

  test('fails when the face jumps (e.g. swapping a printout in)', () {
    position();
    feed(face(x: 0.9));
    expect(session.failReason, 'FACE_SWITCHED');
  });

  test('fails when a second face stays in view', () {
    position();
    feed(face(count: 2), frames: 20);
    expect(session.failReason, 'MULTIPLE_FACES');
  });

  test('does not start until the face is big, frontal and still', () {
    feed(face(yaw: 0.5), frames: 40);
    expect(session.phase, LivenessPhase.positioning);
    feed(
      const FrameObservation(
        faceCount: 1,
        presence: 0.99,
        faceArea: 0.01,
        centerX: 0.5,
        centerY: 0.5,
        ear: _open,
        yaw: 0,
      ),
      frames: 40,
    );
    expect(session.phase, LivenessPhase.positioning);
  });
}
