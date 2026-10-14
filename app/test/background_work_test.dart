// Regression tests for background work on photos.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/a04_forensics/forensics.dart';
import 'package:humandetect_app/core/image_ops.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'tile 04 handles a tiny gallery image (smaller than the moiré patch)',
    () async {
      final tiny = img.Image(width: 40, height: 30);
      for (final p in tiny) {
        p
          ..r = p.x * 6
          ..g = p.y * 8
          ..b = 90;
      }
      final image = RgbImage.fromEncoded(img.encodePng(tiny));
      final signals = await compute(
        computeSignals,
        image,
      ); // as ForensicsCheck runs it
      expect(
        signals.moire,
        greaterThan(0),
      ); // 32x32 patch analysed, no out-of-range read
      final dot = RgbImage.fromEncoded(
        img.encodePng(img.Image(width: 5, height: 5)),
      );
      expect(
        computeSignals(dot).moire,
        0,
      ); // too small to analyse: scored 0, not a crash
    },
  );

  // The 0.1.0 shutter crash: an inline closure handed to Isolate.run/compute inside a
  // State method captured `this`, which can't be sent to another isolate. Background
  // work must take a top-level function and its data, e.g. compute(decode, bytes).
  test('no inline closures are sent to background isolates', () {
    final offenders = <String>[];
    final pattern = RegExp(r'(Isolate\.run|compute)\(\s*(\(|[a-z_]\w*\s*=>)');
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final source = f.readAsStringSync();
      for (final m in pattern.allMatches(source)) {
        final line = source.substring(0, m.start).split('\n').length;
        offenders.add('${f.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Pass a top-level function instead of a closure',
    );
  });
}
