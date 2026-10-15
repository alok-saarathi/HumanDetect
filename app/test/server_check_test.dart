import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/server/server_check.dart';

void main() {
  test('server reply parses into a CheckResult', () {
    final r = parseServerResult({
      'passed': false,
      'score': 0.31,
      'reasons': ['DUPLICATE'],
      'details': [
        ['Closest by pHash', '0 bits differ'],
        ['Matches', 'photo ab12, 3 min ago'],
      ],
      'marks': [
        {
          'box': [0.1, 0.2, 0.3, 0.4],
          'label': 'person 0.97',
        },
      ],
      'latency_ms': 12.5,
    });
    expect(r.passed, isFalse);
    expect(r.score, closeTo(0.31, 1e-9));
    expect(r.reasons, ['DUPLICATE']);
    expect(r.details, [
      ('Closest by pHash', '0 bits differ'),
      ('Matches', 'photo ab12, 3 min ago'),
    ]);
    expect(r.marks.single.box!.width, closeTo(0.3, 1e-9));
    expect(r.marks.single.label, 'person 0.97');
    expect(r.latency, const Duration(microseconds: 12500));
  });

  test('endpoint joins address, path and query', () {
    ServerSettings.url = 'http://10.0.0.5:8765/';
    expect(
      ServerSettings.endpoint('/v1/check/08', {'min_area': '0.1'}).toString(),
      'http://10.0.0.5:8765/v1/check/08?min_area=0.1',
    );
  });

  test('every Tier 2 tile has a server check', () {
    expect(serverChecks.keys, ['06', '07', '08', '09']);
  });
}
