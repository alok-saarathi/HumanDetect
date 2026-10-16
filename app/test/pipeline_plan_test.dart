import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/a15_pipeline/pipeline_screen.dart';
import 'package:humandetect_app/approaches/a15_pipeline/plan.dart';

void main() {
  test('capture clicks a still, then BlazeFace; an upload starts at BlazeFace', () {
    const enabled = <String, bool>{};
    expect(phoneSteps(PipelinePath.capture, enabled), ['01', '03', '04', '02']);
    expect(phoneSteps(PipelinePath.upload, enabled), ['01', '04', '02']);
    expect(serverSteps(enabled), ['08', '07', '06', '09']);
  });

  test('a switch skips that step, including on the server', () {
    final enabled = {for (final stage in flowStages) stage.id: true}
      ..['02'] = false
      ..['08'] = false
      ..['06'] = false;
    expect(phoneSteps(PipelinePath.capture, enabled), ['01', '03', '04']);
    expect(phoneSteps(PipelinePath.upload, enabled), ['01', '04']);
    expect(serverSkip(enabled), {'08', '06'});
    // Turning the live-capture check on does not put it on the upload path.
    expect(phoneSteps(PipelinePath.upload, {'03': true}), ['01', '04', '02']);
  });

  test(
    'the upload diagram marks the live-capture check as not on this path',
    () {
      final rows = layoutPipeline(path: PipelinePath.upload, enabled: {});
      expect(rows[0].stage.id, '01');
      expect(rows[0].state, NodeState.waiting);
      expect(rows[1].stage.id, '03');
      expect(rows[1].state, NodeState.offPath);
      expect(
        rows.firstWhere((row) => row.stage.id == '04').state,
        NodeState.waiting,
      );
    },
  );

  testWidgets('the pipeline screen shows the diagram and both paths', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PipelineScreen()));
    expect(find.text('Face in the photo'), findsOneWidget);
    expect(find.text('Final judge'), findsOneWidget);
    expect(find.text('On the phone'), findsOneWidget);
    expect(find.textContaining('only if the phone passed'), findsOneWidget);

    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(find.text('upload skips'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Choose from the gallery'), 400);
    expect(find.text('Choose from the gallery'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('03 · Live capture'), 200);
    expect(find.text('An upload always skips this'), findsWidgets);
  });
}
