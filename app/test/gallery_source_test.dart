import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/a01_face_detection/face_detection_check.dart';
import 'package:humandetect_app/approaches/a02_zero_shot/zero_shot_check.dart';
import 'package:humandetect_app/approaches/a03_capture_integrity/capture_integrity_check.dart';
import 'package:humandetect_app/approaches/a04_forensics/forensics_check.dart';
import 'package:humandetect_app/core/check.dart';
import 'package:humandetect_app/core/gallery_pick.dart';
import 'package:humandetect_app/core/image_ops.dart';

void main() {
  test('gallery bytes the image package can decode directly', () {
    expect(
      galleryBytesAreDirectlyDecodable(
        Uint8List.fromList([0xFF, 0xD8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      ),
      isTrue,
    );
    final png = Uint8List(12)..setRange(0, 4, [0x89, 0x50, 0x4E, 0x47]);
    expect(galleryBytesAreDirectlyDecodable(png), isTrue);
    final webp = Uint8List(12)
      ..setRange(0, 4, [0x52, 0x49, 0x46, 0x46])
      ..setRange(8, 12, [0x57, 0x45, 0x42, 0x50]);
    expect(galleryBytesAreDirectlyDecodable(webp), isTrue);
    // HEIC: size + 'ftyp' — not decoded by the image package.
    final heic = Uint8List(12)..setRange(4, 8, [0x66, 0x74, 0x79, 0x70]);
    expect(galleryBytesAreDirectlyDecodable(heic), isFalse);
    expect(galleryBytesAreDirectlyDecodable(Uint8List(4)), isFalse);
  });

  test('content checks accept a gallery file; capture integrity does not', () {
    expect(FaceDetectionCheck().acceptsGallery, isTrue);
    expect(ZeroShotCheck().acceptsGallery, isTrue);
    expect(ForensicsCheck().acceptsGallery, isTrue);
    expect(CaptureIntegrityCheck().acceptsGallery, isFalse);
  });

  test(
    'a gallery file fails capture integrity without session checks',
    () async {
      final check = CaptureIntegrityCheck();
      final photo = CapturedPhoto(
        jpeg: Uint8List(0),
        image: RgbImage(1, 1, Uint8List(3)),
        capturedAt: DateTime.utc(2020),
        source: PhotoSource.gallery,
        frontCamera: false,
        decodeTime: Duration.zero,
      );
      final result = await check.check(photo);
      expect(result.passed, isFalse);
      expect(result.reasons, ['GALLERY_UPLOAD']);
      expect(result.details.single.$1, contains('Live capture'));
    },
  );

  test('origin label follows the source', () {
    CapturedPhoto photo(PhotoSource source, {bool front = false}) =>
        CapturedPhoto(
          jpeg: Uint8List(0),
          image: RgbImage(1, 1, Uint8List(3)),
          capturedAt: DateTime.utc(2020),
          source: source,
          frontCamera: front,
          decodeTime: Duration.zero,
        );
    expect(photo(PhotoSource.gallery).originLabel, 'gallery');
    expect(photo(PhotoSource.camera).originLabel, 'back camera');
    expect(photo(PhotoSource.camera, front: true).originLabel, 'front camera');
  });
}
