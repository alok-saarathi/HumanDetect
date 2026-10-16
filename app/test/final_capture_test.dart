import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/a01_face_detection/blazeface.dart';
import 'package:humandetect_app/approaches/final_capture/face_presence.dart';
import 'package:humandetect_app/approaches/final_capture/final_capture_screen.dart';
import 'package:humandetect_app/core/check.dart';
import 'package:humandetect_app/screens/home_screen.dart';

Face _face(double score, double area) =>
    Face(score, 0.1, 0.1, area, 1, const []);

void main() {
  test('a confident large face passes, including a second face', () {
    final verdict = judgePresence([
      _face(0.9, 0.2),
      _face(0.8, 0.15),
    ]);
    expect(verdict.passed, isTrue);
    expect(verdict.reasons, isEmpty);
    expect(verdict.score, 0.9);
  });

  test('no face, a weak face, and a tiny face fail', () {
    expect(judgePresence(const []).reasons, ['NO_FACE']);
    expect(judgePresence([_face(0.2, 0.2)]).reasons, ['LOW_CONFIDENCE']);
    expect(judgePresence([_face(0.9, 0.01)]).reasons, ['FACE_TOO_SMALL']);
  });

  testWidgets('home has a Final capture section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(ping: () async => '06, 07')),
    );
    expect(find.text('Final capture'), findsOneWidget);
    expect(
      find.text('A face on this phone, then the same check on the server.'),
      findsOneWidget,
    );
  });

  testWidgets('the section explains both checks before a photo is taken', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinalCaptureScreen(
          serverCheck: (_) async => CheckResult(
            passed: true,
            score: 1,
            latency: Duration.zero,
          ),
        ),
      ),
    );
    expect(find.text('Take or choose a photo'), findsOneWidget);
    expect(find.textContaining('printed photograph'), findsOneWidget);
  });
}
