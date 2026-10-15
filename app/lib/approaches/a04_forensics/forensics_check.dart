import 'dart:typed_data';

import 'package:exif/exif.dart';

import '../../core/check.dart';
import 'forensics.dart';

/// Approach 04: hand-written recapture and metadata signals, no model.
class ForensicsCheck extends PhotoCheck {
  final _sharpness = Tunable(
    label: 'Min sharpness (Laplacian variance)',
    min: 5,
    max: 300,
    initial: 40,
    decimals: 0,
  );
  final _glare = Tunable(
    label: 'Max glare (share of near-white pixels)',
    min: 0.005,
    max: 0.2,
    initial: 0.05,
    decimals: 3,
  );
  final _contrast = Tunable(
    label: 'Min contrast (luma spread)',
    min: 10,
    max: 150,
    initial: 60,
    decimals: 0,
  );
  final _moire = Tunable(
    label: 'Max moiré score',
    min: 2.0,
    max: 8.0,
    initial: 3.5,
    decimals: 1,
  );
  final _timeSkew = Tunable(
    label: 'Max EXIF time difference (seconds)',
    min: 30,
    max: 3600,
    initial: 600,
    decimals: 0,
  );

  @override
  String get id => '04';

  @override
  String get title => 'Recapture forensics';

  @override
  String get scoreLabel => 'share of signals within limits';

  @override
  List<Tunable> get tunables => [
    _sharpness,
    _glare,
    _contrast,
    _moire,
    _timeSkew,
  ];

  @override
  Future<CheckResult> check(CapturedPhoto photo) async {
    final watch = Stopwatch()..start();
    final image = photo.image;
    final s = await signalsInBackground(image);
    // The exif package reads JPEG markers. A gallery PNG, WebP, GIF or BMP has
    // none; missing metadata is shown and, for a gallery file, is not a failure.
    final exif = _isJpeg(photo.jpeg)
        ? await readExifFromBytes(photo.jpeg)
        : <String, IfdTag>{};
    watch.stop();

    final make = exif['Image Make']?.printable.trim();
    final model = exif['Image Model']?.printable.trim();
    final rawTime = (exif['EXIF DateTimeOriginal'] ?? exif['Image DateTime'])
        ?.printable
        .trim();
    final exifTime = _parseExifTime(rawTime);

    final reasons = <String>[];
    final rows = <(String, String)>[];
    var ok = 0, total = 0;
    void signal(
      String name,
      bool pass,
      String value,
      String limit,
      String reason,
    ) {
      total++;
      if (pass) {
        ok++;
      } else {
        reasons.add(reason);
      }
      rows.add(('${pass ? '✓' : '✗'} $name', '$value  ($limit)'));
    }

    signal(
      'Sharpness',
      s.sharpness >= _sharpness.value,
      s.sharpness.toStringAsFixed(0),
      '≥ ${_sharpness.display}',
      'BLURRY',
    );
    signal(
      'Glare',
      s.glare <= _glare.value,
      '${(s.glare * 100).toStringAsFixed(1)} %',
      '≤ ${(_glare.value * 100).toStringAsFixed(1)} %',
      'GLARE',
    );
    signal(
      'Contrast',
      s.contrast >= _contrast.value,
      s.contrast.toStringAsFixed(0),
      '≥ ${_contrast.display}',
      'LOW_CONTRAST',
    );
    signal(
      'Moiré',
      s.moire <= _moire.value,
      s.moire.toStringAsFixed(2),
      '≤ ${_moire.display}',
      'MOIRE',
    );
    // Make/model and the EXIF clock are a verdict only for an in-app capture.
    // A gallery file often has neither, and an old timestamp is normal there.
    if (photo.source == PhotoSource.camera) {
      signal(
        'Camera metadata',
        (make ?? '').isNotEmpty || (model ?? '').isNotEmpty,
        '${make ?? '-'} / ${model ?? '-'}',
        'present',
        'METADATA_MISSING',
      );
      if (exifTime != null) {
        final skew = photo.capturedAt.difference(exifTime).inSeconds.abs();
        signal(
          'EXIF time',
          skew <= _timeSkew.value,
          '$skew s from capture',
          '≤ ${_timeSkew.display} s',
          'TIME_MISMATCH',
        );
      } else {
        rows.add(('– EXIF time', 'not present'));
      }
    } else {
      rows.add((
        '– Camera metadata',
        '${make ?? '-'} / ${model ?? '-'}  (not applied to gallery)',
      ));
      rows.add((
        '– EXIF time',
        exifTime == null
            ? 'not present  (not applied to gallery)'
            : 'present  (not applied to gallery)',
      ));
    }

    return CheckResult(
      passed: reasons.isEmpty,
      score: ok / total,
      reasons: reasons,
      latency: watch.elapsed,
      details: rows,
    );
  }

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  static DateTime? _parseExifTime(String? raw) {
    // EXIF format "YYYY:MM:DD HH:MM:SS", local time.
    final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(raw ?? '');
    if (m == null) return null;
    final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  }
}
