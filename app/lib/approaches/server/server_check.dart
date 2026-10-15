// Tier 2 on the phone: send the photo to the HumanDetect server (server/README.md) and
// show its verdict like an on-device one. The server judges the photo in memory and
// never stores it (approach 07 stores only fingerprints).

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/check.dart';

/// Where the server runs: set from the home screen, remembered between launches.
/// Lab use: plain HTTP to a computer on the same Wi-Fi.
class ServerSettings {
  static const defaultPort = 8765;
  static const _urlKey = 'server_url';
  static const _tokenKey = 'server_token';

  /// Empty until the tester enters one.
  static String url = '';
  static String token = '';

  static bool get isSet => url.isNotEmpty;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      url = prefs.getString(_urlKey) ?? '';
      token = prefs.getString(_tokenKey) ?? '';
    } catch (_) {
      // Settings simply aren't remembered if storage is unavailable.
    }
  }

  /// Saves a cleaned-up address (see [normalizeAddress]) and token.
  static Future<void> save(String rawUrl, String rawToken) async {
    url = normalizeAddress(rawUrl);
    token = rawToken.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_urlKey, url);
      await prefs.setString(_tokenKey, token);
    } catch (_) {}
  }

  static Uri endpoint(String path, [Map<String, String>? query]) {
    final base = Uri.parse(url.replaceAll(RegExp(r'/+$'), ''));
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }
}

/// Turns what a tester types into a full address: "192.168.1.23" becomes
/// "http://192.168.1.23:8765"; "mac.local:9000" keeps its port; "https://…" is kept.
/// Returns '' for empty input.
String normalizeAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return '';
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return input.trim();
  final port = uri.hasPort
      ? uri.port
      : (uri.scheme == 'https' ? null : ServerSettings.defaultPort);
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: port,
    path: path,
  ).toString();
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
  if (!ServerSettings.isSet) {
    throw ServerUnreachable(
      'No server address yet. Press Server on the home screen and enter your Mac\'s address.',
    );
  }
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

/// One server stage inside a pipeline response.
class ServerStageReport {
  ServerStageReport({
    required this.id,
    required this.state,
    required this.reasons,
    required this.score,
  });

  final String id;
  final String state;
  final List<String> reasons;
  final double? score;

  static ServerStageReport parse(Map<String, dynamic> json) =>
      ServerStageReport(
        id: json['id'] as String,
        state: json['state'] as String,
        reasons: (json['reasons'] as List?)?.cast<String>() ?? const [],
        score: (json['score'] as num?)?.toDouble(),
      );
}

/// Verdict of POST /v1/pipeline.
class ServerPipelineReport {
  ServerPipelineReport({
    required this.passed,
    required this.reasons,
    required this.advisory,
    required this.stoppedAt,
    required this.stages,
  });

  final bool passed;
  final List<String> reasons;
  final List<String> advisory;
  final String? stoppedAt;
  final List<ServerStageReport> stages;

  static ServerPipelineReport parse(Map<String, dynamic> json) =>
      ServerPipelineReport(
        passed: json['passed'] as bool,
        reasons: (json['reasons'] as List).cast<String>(),
        advisory: (json['advisory'] as List?)?.cast<String>() ?? const [],
        stoppedAt: json['stopped_at'] as String?,
        stages: [
          for (final stage in json['stages'] as List)
            ServerStageReport.parse(Map<String, dynamic>.from(stage as Map)),
        ],
      );
}

/// Runs the server half of the pipeline. [skip] lists stages switched off.
Future<ServerPipelineReport> runServerPipeline(
  List<int> jpeg, {
  required Set<String> skip,
}) async {
  final query = <String, String>{};
  if (skip.isNotEmpty) query['skip'] = (skip.toList()..sort()).join(',');
  final json = await _send(
    'POST',
    ServerSettings.endpoint('/v1/pipeline', query.isEmpty ? null : query),
    body: jpeg,
    timeout: const Duration(minutes: 3),
  );
  return ServerPipelineReport.parse(Map<String, dynamic>.from(json as Map));
}

/// Health check: the approach ids the server offers, e.g. "06, 07, 08, 09".
Future<String> pingServer() async {
  final health = await _send(
    'GET',
    ServerSettings.endpoint('/v1/health'),
    timeout: const Duration(seconds: 8),
  ) as Map;
  return (health['approaches'] as List).join(', ');
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
