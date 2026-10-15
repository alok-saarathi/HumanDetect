// Which steps the lab pipeline runs, and in what order.
//
// Capture (photo taken in the app): 05 → 03 → 04 → 02, then the server.
// Upload: 05 and 03 do not exist; start at 04 → 02, then the server.
// Server: 08 → 07 → 06 → 09. 06 is a note, not a hard reject.
// A switch turns a step off. 10–14 are not in this pipeline.

enum PipelinePath { capture, upload }

enum NodeState {
  waiting,
  skipped,
  offPath,
  running,
  passed,
  failed,
  noted,
  stopped,
}

class FlowStage {
  const FlowStage({
    required this.id,
    required this.title,
    required this.blurb,
    required this.onPhone,
    required this.captureOnly,
    required this.advisory,
  });

  final String id;
  final String title;
  final String blurb;
  final bool onPhone;

  /// Blink and the live-capture check. An upload never runs these.
  final bool captureOnly;

  /// A failure here is reported and the pipeline continues.
  final bool advisory;
}

const flowStages = <FlowStage>[
  FlowStage(
    id: '05',
    title: 'Blink and head turn',
    blurb: 'BlazeFace + Face Mesh. This also covers face detection.',
    onPhone: true,
    captureOnly: true,
    advisory: false,
  ),
  FlowStage(
    id: '03',
    title: 'Live capture',
    blurb: 'Session nonce, capture time, real phone, GPS.',
    onPhone: true,
    captureOnly: true,
    advisory: false,
  ),
  FlowStage(
    id: '04',
    title: 'Rules',
    blurb: 'Blur, glare, contrast, moiré, and EXIF.',
    onPhone: true,
    captureOnly: false,
    advisory: false,
  ),
  FlowStage(
    id: '02',
    title: 'TinyCLIP',
    blurb: 'Person versus scene, screen, cartoon, or drawing.',
    onPhone: true,
    captureOnly: false,
    advisory: false,
  ),
  FlowStage(
    id: '08',
    title: 'Person present',
    blurb: 'RT-DETRv2 + D-FINE. One clear person.',
    onPhone: false,
    captureOnly: false,
    advisory: false,
  ),
  FlowStage(
    id: '07',
    title: 'Already submitted?',
    blurb: 'pHash + DINOv2.',
    onPhone: false,
    captureOnly: false,
    advisory: false,
  ),
  FlowStage(
    id: '06',
    title: 'Face, not a screen',
    blurb: 'OWLv2. Kept as a reason, not the only reject.',
    onPhone: false,
    captureOnly: false,
    advisory: true,
  ),
  FlowStage(
    id: '09',
    title: 'Final judge',
    blurb: 'SmolVLM2-500M. What is this photo?',
    onPhone: false,
    captureOnly: false,
    advisory: false,
  ),
];

const phoneOrder = ['05', '03', '04', '02'];
const serverOrder = ['08', '07', '06', '09'];

bool stageEnabled(Map<String, bool> enabled, String id) => enabled[id] ?? true;

/// Steps that will actually run on the phone for this path and these switches.
List<String> phoneSteps(PipelinePath path, Map<String, bool> enabled) {
  final ids = path == PipelinePath.capture
      ? phoneOrder
      : phoneOrder.where((id) => id != '05' && id != '03');
  return [
    for (final id in ids)
      if (stageEnabled(enabled, id)) id,
  ];
}

/// Server stages left switched on. Sent as the complement in `skip`.
List<String> serverSteps(Map<String, bool> enabled) => [
  for (final id in serverOrder)
    if (stageEnabled(enabled, id)) id,
];

Set<String> serverSkip(Map<String, bool> enabled) => {
  for (final id in serverOrder)
    if (!stageEnabled(enabled, id)) id,
};

class StageView {
  const StageView(this.stage, this.state);

  final FlowStage stage;
  final NodeState state;
}

/// Diagram rows. A live run overrides the idle state of steps that are on.
List<StageView> layoutPipeline({
  required PipelinePath path,
  required Map<String, bool> enabled,
  Map<String, NodeState> live = const {},
}) {
  return [
    for (final stage in flowStages)
      StageView(stage, _stateOf(stage, path, enabled, live)),
  ];
}

NodeState _stateOf(
  FlowStage stage,
  PipelinePath path,
  Map<String, bool> enabled,
  Map<String, NodeState> live,
) {
  if (path == PipelinePath.upload && stage.captureOnly) {
    return NodeState.offPath;
  }
  if (!stageEnabled(enabled, stage.id)) return NodeState.skipped;
  return live[stage.id] ?? NodeState.waiting;
}
