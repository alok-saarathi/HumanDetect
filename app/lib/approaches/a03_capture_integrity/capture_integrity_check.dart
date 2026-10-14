// Approach 03: harden the capture flow. No model: checks that the photo was taken live,
// in this app, in this session, on a real phone, at a real location, and signs a receipt
// the server could verify.
//
// In production the nonce and signing key come from the server; here they are made on
// the phone so the flow can be tried without a backend.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import '../../core/check.dart';

/// Demo only: a real deployment gets a per-session key from the server.
const _demoSigningKey = 'humandetect-lab-demo-key';

class CaptureIntegrityCheck extends PhotoCheck {
  final _maxSessionAge = Tunable(
    label: 'Max seconds from session start to photo',
    min: 15,
    max: 600,
    initial: 120,
    decimals: 0,
  );
  final _maxAccuracy = Tunable(
    label: 'Max location error (metres)',
    min: 5,
    max: 500,
    initial: 50,
    decimals: 0,
  );
  final _maxFixAge = Tunable(
    label: 'Max location age (seconds)',
    min: 10,
    max: 600,
    initial: 120,
    decimals: 0,
  );

  late String _nonce;
  late DateTime _sessionStart;
  Future<Position?>? _position;
  Object? _locationError;
  Future<AndroidDeviceInfo>? _device;

  Future<AndroidDeviceInfo> _deviceInfo() =>
      _device ??= DeviceInfoPlugin().androidInfo;

  @override
  String get id => '03';

  @override
  String get title => 'Capture integrity';

  @override
  String get scoreLabel => 'share of checks passed';

  @override
  List<Tunable> get tunables => [_maxSessionAge, _maxAccuracy, _maxFixAge];

  @override
  bool get acceptsGallery => false;

  @override
  void startSession() {
    final random = math.Random.secure();
    _nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _sessionStart = DateTime.now();
    _locationError = null;
    _position = _locate();
  }

  Future<Position?> _locate() async {
    final geo = GeolocatorPlatform.instance;
    try {
      if (!await geo.isLocationServiceEnabled()) {
        throw StateError('Location services are off');
      }
      var permission = await geo.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await geo.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission denied');
      }
      return await geo.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        ),
      );
    } catch (e) {
      _locationError = e;
      return null;
    }
  }

  @override
  Future<CheckResult> check(CapturedPhoto photo) async {
    final watch = Stopwatch()..start();
    if (photo.source == PhotoSource.gallery) {
      watch.stop();
      return CheckResult(
        passed: false,
        score: 0,
        reasons: const ['GALLERY_UPLOAD'],
        latency: watch.elapsed,
        details: const [
          (
            '✗ Live capture',
            'Gallery file. The session nonce, freshness and GPS apply only to a photo taken with this screen\'s camera.',
          ),
        ],
      );
    }

    final position = await (_position ?? Future.value(null));
    final device = await _deviceInfo();
    final rows = <(String, String)>[];
    final reasons = <String>[];
    var passedCount = 0, total = 0;

    void record(String name, bool ok, String detail, [String? reason]) {
      total++;
      if (ok) {
        passedCount++;
      } else if (reason != null) {
        reasons.add(reason);
      }
      rows.add(('${ok ? '✓' : '✗'} $name', detail));
    }

    record('Live capture', true, 'Taken with this screen\'s camera');

    final age = photo.capturedAt.difference(_sessionStart);
    record(
      'Fresh session',
      age.inSeconds <= _maxSessionAge.value,
      '${age.inSeconds} s after nonce ${_nonce.substring(0, 8)}…',
      'STALE_SESSION',
    );

    record(
      'Real device',
      device.isPhysicalDevice,
      '${device.manufacturer} ${device.model}, Android ${device.version.release}',
      'EMULATOR',
    );

    if (position == null) {
      record('Location', false, '$_locationError', 'NO_LOCATION');
    } else {
      final fixAge = photo.capturedAt
          .difference(position.timestamp)
          .inSeconds
          .abs();
      record(
        'Location precise',
        position.accuracy <= _maxAccuracy.value,
        '±${position.accuracy.toStringAsFixed(0)} m, fix ${fixAge}s old',
        'LOW_LOCATION_ACCURACY',
      );
      record(
        'Location fresh',
        fixAge <= _maxFixAge.value,
        '${position.latitude.toStringAsFixed(5)}, '
            '${position.longitude.toStringAsFixed(5)}',
        'NO_LOCATION',
      );
      record(
        'Location not mocked',
        !position.isMocked,
        position.isMocked ? 'A mock-location app is active' : 'OK',
        'MOCK_LOCATION',
      );
    }

    // Receipt: what the server would store and verify.
    final photoHash = sha256.convert(photo.jpeg).toString();
    final payload = jsonEncode({
      'nonce': _nonce,
      'photo_sha256': photoHash,
      'captured_at': photo.capturedAt.toUtc().toIso8601String(),
      'lat': position?.latitude,
      'lon': position?.longitude,
      'device': '${device.manufacturer} ${device.model}',
    });
    final signature = Hmac(
      sha256,
      utf8.encode(_demoSigningKey),
    ).convert(utf8.encode(payload)).toString();
    watch.stop();

    rows
      ..add(('Photo SHA-256', '${photoHash.substring(0, 16)}…'))
      ..add(('Receipt HMAC (demo key)', '${signature.substring(0, 16)}…'));

    return CheckResult(
      passed: reasons.isEmpty,
      score: passedCount / total,
      reasons: reasons,
      latency: watch.elapsed,
      details: rows,
    );
  }
}
