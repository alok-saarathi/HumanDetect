// Tier 2 on the phone: send the photo to the HumanDetect server (server/README.md) and
// show its verdict like an on-device one. The server judges the photo in memory and
// never stores it (approach 07 stores only fingerprints).

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import '../../core/check.dart';

/// Where the server runs. Set from the home screen (lab only: plain HTTP on the LAN).
class ServerSettings {
  static String url = 'http://192.168.1.10:8000';
  static String token = '';

  static Uri endpoint(String path, [Map<String, String>? query]) {
    final base = Uri.parse(url.trim().replaceAll(RegExp(r'/+$'), ''));
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }
}

class ServerUnreachable implements Exception {
  ServerUnreachable(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<dynamic> _send(
  String method,
  Uri uri, {
  List<int>? body,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 8));
    if (ServerSettings.token.isNotEmpty) {
      request.headers.set('X-HumanDetect-Token', ServerSettings.token);
    }
    if (body != null) {
      request.headers.contentType = ContentType.binary;
      request.add(body);
    }
    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      final detail = _detail(text);
      throw ServerUnreachable('Server said ${response.statusCode}: $detail');
    }
    return jsonDecode(text);
  } on SocketException catch (e) {
    throw ServerUnreachable(
      'Cannot reach ${ServerSettings.url} (${e.osError?.message ?? e.message}). '
      'Is the server running, and the phone on the same network?',
    );
  } on HttpException catch (e) {
    throw ServerUnreachable('Bad server address: ${e.message}');
  } on FormatException catch (e) {
    throw ServerUnreachable('Bad server address or reply: ${e.message}');
  } finally {
    client.close(force: true);
  }
}

String _detail(String body) {
  try {
    return (jsonDecode(body) as Map)['detail'].toString();
  } catch (_) {
    return body.length > 160 ? '${body.substring(0, 160)}…' : body;
  }
}

/// Health check used by the settings dialog.
Future<String> pingServer() async {
  final health = await _send(
    'GET',
    ServerSettings.endpoint('/v1/health'),
    timeout: const Duration(seconds: 8),
  ) as Map;
  return 'Connected. Approaches on the server: ${(health['approaches'] as List).join(', ')}';
}

CheckResult parseServerResult(Map<String, dynamic> json) {
  return CheckResult(
    passed: json['passed'] as bool,
    score: (json['score'] as num).toDouble(),
    reasons: (json['reasons'] as List).cast<String>(),
    latency: Duration(
      microseconds: ((json['latency_ms'] as num) * 1000).round(),
    ),
    details: [
      for (final d in json['details'] as List)
        ((d as List)[0] as String, d[1] as String),
    ],
    marks: [
      for (final m in json['marks'] as List)
        PhotoMark(
          box: () {
            final b = ((m as Map)['box'] as List).cast<num>();
            return Rect.fromLTWH(
              b[0].toDouble(),
              b[1].toDouble(),
              b[2].toDouble(),
              b[3].toDouble(),
            );
          }(),
          label: m['label'] as String?,
        ),
    ],
  );
}

/// One approach that runs on the server.
class ServerCheck extends PhotoCheck {
  ServerCheck(this.id, this.title, this.scoreLabel);

  @override
  final String id;
  @override
  final String title;
  @override
  final String scoreLabel;

  List<Tunable> _tunables = [];
  final _values = <String, Tunable>{};

  @override
  List<Tunable> get tunables => _tunables;

  /// Reads the thresholds the server offers for this approach.
  @override
  Future<void> prepare() async {
    final all = await _send(
      'GET',
      ServerSettings.endpoint('/v1/approaches'),
      timeout: const Duration(seconds: 15),
    ) as List;
    final mine = all.cast<Map<String, dynamic>>().firstWhere(
      (a) => a['id'] == id,
    );
    _tunables = [
      for (final t in (mine['tunables'] as List).cast<Map<String, dynamic>>())
        Tunable(
          label: t['label'] as String,
          min: (t['min'] as num).toDouble(),
          max: (t['max'] as num).toDouble(),
          initial: (t['default'] as num).toDouble(),
          decimals: t['decimals'] as int,
        ),
    ];
    _values
      ..clear()
      ..addEntries([
        for (var i = 0; i < _tunables.length; i++)
          MapEntry(
            (mine['tunables'] as List)[i]['key'] as String,
            _tunables[i],
          ),
      ]);
  }

  /// A first request can take a while: the server loads its models on first use.
  @override
  Future<CheckResult> check(CapturedPhoto photo) async {
    final query = {
      for (final e in _values.entries) e.key: e.value.value.toString(),
    };
    final json = await _send(
      'POST',
      ServerSettings.endpoint('/v1/check/$id', query),
      body: photo.jpeg,
      timeout: const Duration(minutes: 4),
    ) as Map<String, dynamic>;
    return parseServerResult(json);
  }
}

/// Clears approach 07's index (lab use).
Future<int> resetDuplicateIndex() async {
  final r = await _send(
    'POST',
    ServerSettings.endpoint('/v1/approaches/07/reset'),
    body: const [],
  ) as Map;
  return r['removed'] as int;
}

final serverChecks = <String, ServerCheck Function()>{
  '06': () => ServerCheck('06', 'Zero-shot detection', 'face score'),
  '07': () => ServerCheck(
    '07',
    'Duplicate detection',
    '1 − similarity to closest earlier photo',
  ),
  '08': () => ServerCheck('08', 'Open deep detectors', 'person confidence'),
  '09': () =>
      ServerCheck('09', 'Open VLM judge', "probability of 'real person'"),
};
