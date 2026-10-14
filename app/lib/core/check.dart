import 'dart:typed_data';
import 'dart:ui';

import 'image_ops.dart';

/// Where the bytes came from. Content checks (01, 02, 04's image signals) treat both
/// the same. Provenance checks (03, 04's EXIF clock, 05) only apply to [camera].
enum PhotoSource { camera, gallery }

/// A photo from the in-app camera or from the gallery picker.
class CapturedPhoto {
  CapturedPhoto({
    required this.jpeg,
    required this.image,
    required this.capturedAt,
    required this.source,
    required this.frontCamera,
    required this.decodeTime,
  });

  final Uint8List jpeg;
  final RgbImage image; // decoded and upright
  final DateTime capturedAt;
  final PhotoSource source;

  /// Lens for an in-app capture. Always false for a gallery file (the lens is unknown).
  final bool frontCamera;
  final Duration decodeTime;

  String get originLabel => switch (source) {
    PhotoSource.gallery => 'gallery',
    PhotoSource.camera => frontCamera ? 'front camera' : 'back camera',
  };
}

/// Something to draw on top of the photo, in normalized (0..1) image coordinates.
class PhotoMark {
  const PhotoMark({this.box, this.points = const [], this.label});

  final Rect? box;
  final List<Offset> points;
  final String? label;
}

class CheckResult {
  const CheckResult({
    required this.passed,
    required this.score,
    this.reasons = const [],
    required this.latency,
    this.details = const [],
    this.marks = const [],
  });

  final bool passed;

  /// 0..1; what it means depends on the approach (shown with the result).
  final double score;
  final List<String> reasons;

  /// Time spent in the check itself, decoding excluded.
  final Duration latency;

  /// Label/value rows shown under the verdict.
  final List<(String, String)> details;
  final List<PhotoMark> marks;
}

/// A threshold testers can adjust from the app without a new build.
class Tunable {
  Tunable({
    required this.label,
    required this.min,
    required this.max,
    required double initial,
    this.divisions,
    this.decimals = 2,
  }) : value = initial;

  final String label;
  final double min;
  final double max;
  final int? divisions;
  final int decimals;
  double value;

  String get display => value.toStringAsFixed(decimals);
}

/// One photo-based approach (01-04). Active liveness (05) has its own live-video screen.
abstract class PhotoCheck {
  String get id;
  String get title;

  /// What the score means, shown next to it.
  String get scoreLabel;

  List<Tunable> get tunables;

  /// Loads models; called once when the camera screen opens.
  Future<void> prepare() async {}

  /// Called when the camera is ready, before any capture (03 issues its nonce here).
  void startSession() {}

  /// Gallery files can be judged by this check. Capture-integrity (03) cannot:
  /// a file already on the phone has no session nonce.
  bool get acceptsGallery => true;

  Future<CheckResult> check(CapturedPhoto photo);
}

/// Human-readable text for every reason code the approaches emit.
const reasonText = <String, String>{
  // 01 face detection
  'NO_FACE': 'No face found',
  'LOW_CONFIDENCE': 'Face found, but the detector is not confident',
  'FACE_TOO_SMALL': 'Face too small: move closer',
  'NO_DOMINANT_FACE': 'More than one face of similar size',
  'FACE_NOT_FRONTAL': 'Face turned too far from the camera',
  // 02 zero-shot
  'NO_HUMAN': 'Looks like a scene or object, not a person',
  'RECAPTURE': 'Looks like a photo of a screen or a printout',
  'SCREENSHOT': 'Looks like a screenshot',
  'NOT_REAL': 'Looks like a drawing, statue or mannequin',
  // 03 capture integrity
  'STALE_SESSION': 'Photo taken too long after the session started',
  'NO_LOCATION': 'Location unavailable',
  'LOW_LOCATION_ACCURACY': 'Location too imprecise',
  'MOCK_LOCATION': 'Location is being faked by an app',
  'EMULATOR': 'Running on an emulator, not a real phone',
  // 04 forensics
  'BLURRY': 'Photo is blurry',
  'GLARE': 'Strong glare (typical of screens and glossy prints)',
  'LOW_CONTRAST': 'Washed-out, low contrast',
  'MOIRE': 'Screen pixel or moiré pattern detected',
  'METADATA_MISSING': 'Camera metadata missing',
  'TIME_MISMATCH': 'Photo timestamp does not match capture time',
  'GALLERY_UPLOAD':
      'Chosen from the gallery. This check only accepts a photo taken in this session',
  // 05 active liveness
  'FACE_LOST': 'Face left the frame during the challenge',
  'MULTIPLE_FACES': 'More than one face in view',
  'FACE_SWITCHED': 'Face jumped: possibly a different face',
  'TIMEOUT': 'Challenge not completed in time',
};
