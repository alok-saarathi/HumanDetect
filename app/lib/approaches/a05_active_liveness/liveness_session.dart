// Challenge-response state machine for approach 05. Pure logic, no camera or model,
// so it can be unit-tested with synthetic observations.

import 'dart:math' as math;

enum Challenge {
  blink('Blink slowly', 'Ask the person to blink slowly'),
  turnLeft(
    'Turn your head to your left',
    "Ask the person to turn their head to THEIR left",
  ),
  turnRight(
    'Turn your head to your right',
    "Ask the person to turn their head to THEIR right",
  );

  const Challenge(this.selfie, this.agent);

  /// Instruction when the person holds the phone (front camera).
  final String selfie;

  /// Instruction when someone else holds the phone (back camera).
  final String agent;
}

enum LivenessPhase { positioning, challenge, passed, failed }

/// What one processed camera frame showed.
class FrameObservation {
  const FrameObservation({
    required this.faceCount,
    this.presence = 0,
    this.faceArea,
    this.centerX,
    this.centerY,
    this.ear,
    this.yaw,
  });

  final int faceCount;
  final double presence; // Face Mesh face-presence score of the largest face
  final double? faceArea; // largest face box as a share of the frame
  final double? centerX, centerY; // largest face center, normalized
  final double? ear; // eye aspect ratio, mean of both eyes
  final double? yaw; // -1..1, negative = towards the PERSON's left

  bool get hasFace => faceCount > 0 && presence >= 0.5;
}

class LivenessSettings {
  double minFaceArea = 0.05;
  double maxStartYaw = 0.2;
  Duration holdStill = const Duration(milliseconds: 700);
  double closeRatio = 0.6; // eyes count as closed below baseline * closeRatio
  double reopenRatio = 0.85; // and open again above baseline * reopenRatio
  double turnThreshold = 0.35;
  Duration challengeTimeout = const Duration(seconds: 7);
  Duration faceLostGrace = const Duration(milliseconds: 700);
  double maxJump = 0.25; // largest allowed face-center jump between frames
}

class LivenessSession {
  LivenessSession(this.settings, {math.Random? random})
    : challenges = [
        Challenge.blink,
        (random ?? math.Random()).nextBool()
            ? Challenge.turnLeft
            : Challenge.turnRight,
      ]..shuffle(random ?? math.Random());

  final LivenessSettings settings;
  final List<Challenge> challenges;

  LivenessPhase phase = LivenessPhase.positioning;
  int index = 0;
  String? failReason;
  double? baselineEar;
  double minEar = double.infinity;
  double maxLeft = 0, maxRight = 0;
  final timeline = <(Challenge, Duration)>[];

  DateTime? _stableSince, _challengeStart, _lostSince, _multiSince;
  final _openEars = <double>[];
  bool _eyesClosed = false;
  int _turnFrames = 0;
  double? _lastX, _lastY;

  Challenge? get current =>
      phase == LivenessPhase.challenge ? challenges[index] : null;

  void update(FrameObservation o, DateTime now) {
    switch (phase) {
      case LivenessPhase.positioning:
        _position(o, now);
      case LivenessPhase.challenge:
        _challenge(o, now);
      case LivenessPhase.passed || LivenessPhase.failed:
        break;
    }
  }

  void _position(FrameObservation o, DateTime now) {
    final ready =
        o.faceCount == 1 &&
        o.hasFace &&
        (o.faceArea ?? 0) >= settings.minFaceArea &&
        (o.yaw?.abs() ?? 1) <= settings.maxStartYaw &&
        o.ear != null;
    if (!ready) {
      _stableSince = null;
      _openEars.clear();
      return;
    }
    _stableSince ??= now;
    _openEars.add(o.ear!);
    _lastX = o.centerX;
    _lastY = o.centerY;
    if (now.difference(_stableSince!) >= settings.holdStill) {
      final sorted = [..._openEars]..sort();
      baselineEar = sorted[sorted.length ~/ 2];
      phase = LivenessPhase.challenge;
      _challengeStart = now;
    }
  }

  void _challenge(FrameObservation o, DateTime now) {
    if (now.difference(_challengeStart!) > settings.challengeTimeout) {
      return _fail('TIMEOUT');
    }
    if (!o.hasFace) {
      _lostSince ??= now;
      if (now.difference(_lostSince!) > settings.faceLostGrace) {
        _fail('FACE_LOST');
      }
      return;
    }
    _lostSince = null;
    if (o.faceCount > 1) {
      _multiSince ??= now;
      if (now.difference(_multiSince!) > settings.faceLostGrace) {
        _fail('MULTIPLE_FACES');
      }
      return;
    }
    _multiSince = null;
    if (_lastX != null && o.centerX != null) {
      final jump = math.sqrt(
        math.pow(o.centerX! - _lastX!, 2) + math.pow(o.centerY! - _lastY!, 2),
      );
      if (jump > settings.maxJump) return _fail('FACE_SWITCHED');
    }
    _lastX = o.centerX;
    _lastY = o.centerY;
    if (o.yaw != null) {
      maxLeft = math.max(maxLeft, -o.yaw!);
      maxRight = math.max(maxRight, o.yaw!);
    }

    final done = switch (challenges[index]) {
      Challenge.blink => _blink(o),
      Challenge.turnLeft => _turn(
        o.yaw != null && o.yaw! < -settings.turnThreshold,
      ),
      Challenge.turnRight => _turn(
        o.yaw != null && o.yaw! > settings.turnThreshold,
      ),
    };
    if (!done) return;
    timeline.add((challenges[index], now.difference(_challengeStart!)));
    index++;
    _eyesClosed = false;
    _turnFrames = 0;
    _challengeStart = now;
    if (index == challenges.length) phase = LivenessPhase.passed;
  }

  bool _blink(FrameObservation o) {
    final ear = o.ear;
    if (ear == null) return false;
    minEar = math.min(minEar, ear);
    if (ear < baselineEar! * settings.closeRatio) _eyesClosed = true;
    return _eyesClosed && ear > baselineEar! * settings.reopenRatio;
  }

  bool _turn(bool turned) {
    _turnFrames = turned ? _turnFrames + 1 : 0;
    return _turnFrames >= 2;
  }

  void _fail(String reason) {
    phase = LivenessPhase.failed;
    failReason = reason;
  }
}
