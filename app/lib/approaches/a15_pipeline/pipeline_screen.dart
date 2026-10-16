import 'package:flutter/material.dart';

import '../../core/check.dart';
import '../../core/gallery_pick.dart';
import '../../core/image_ops.dart';
import '../../screens/approach_detail_screen.dart';
import '../../screens/photo_check_screen.dart';
import '../a01_face_detection/face_detection_check.dart';
import '../a02_zero_shot/zero_shot_check.dart';
import '../a03_capture_integrity/capture_integrity_check.dart';
import '../a04_forensics/forensics_check.dart';
import '../approach_details.dart';
import '../server/server_check.dart';
import 'flow_diagram.dart';
import 'plan.dart';

/// Lab subsection for approach 15. Capture and upload share one diagram.
/// Each step has a switch. A failed phone step stops the run; the photo is
/// not sent to the server.
class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});

  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> {
  PipelinePath _path = PipelinePath.capture;
  final _enabled = {for (final stage in flowStages) stage.id: true};
  final _live = <String, NodeState>{};
  final _faces = FaceDetectionCheck();
  final _forensics = ForensicsCheck();
  final _clip = ZeroShotCheck();
  final _integrity = CaptureIntegrityCheck();
  bool _running = false;
  String? _banner;
  bool? _passed;

  List<StageView> get _rows =>
      layoutPipeline(path: _path, enabled: _enabled, live: _live);

  void _setPath(PipelinePath path) {
    if (_running) return;
    setState(() {
      _path = path;
      _live.clear();
      _banner = null;
      _passed = null;
    });
  }

  void _toggle(String id, bool on) {
    if (_running) return;
    setState(() {
      _enabled[id] = on;
      _live.clear();
      _banner = null;
      _passed = null;
    });
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _live.clear();
      _banner = null;
      _passed = null;
    });
    try {
      final photo = _path == PipelinePath.capture
          ? await _capture()
          : await _upload();
      if (!mounted || photo == null) return;
      await _run(photo);
    } catch (e) {
      if (mounted) {
        setState(() => _banner = 'Stopped: $e');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<CapturedPhoto?> _capture() async {
    _integrity.startSession();
    return Navigator.of(context).push<CapturedPhoto>(
      MaterialPageRoute(
        builder: (context) => PhotoCheckScreen(
          check: _ShutterOnly(),
          onCaptured: (photo) => Navigator.of(context).pop(photo),
        ),
      ),
    );
  }

  Future<CapturedPhoto?> _upload() async {
    final bytes = await pickGalleryImage();
    if (bytes == null) return null;
    final watch = Stopwatch()..start();
    final decoded = await decodePhotoInBackground(bytes, gallery: true);
    watch.stop();
    return CapturedPhoto(
      jpeg: bytes,
      image: decoded.image,
      capturedAt: DateTime.now(),
      source: PhotoSource.gallery,
      frontCamera: false,
      decodeTime: watch.elapsed,
    );
  }

  Future<void> _run(CapturedPhoto photo) async {
    final steps = phoneSteps(_path, _enabled);
    if (steps.contains('01')) await _faces.prepare();
    if (steps.contains('02')) await _clip.prepare();
    for (final id in steps) {
      setState(() => _live[id] = NodeState.running);
      final result = await _phoneCheck(id).check(photo);
      if (!mounted) return;
      if (!result.passed) {
        _failAt(id, result.reasons);
        return;
      }
      setState(() => _live[id] = NodeState.passed);
    }
    if (serverSteps(_enabled).isEmpty) {
      setState(() {
        _passed = true;
        _banner = 'Passed on the phone. Every server step is switched off, so nothing was sent.';
      });
      return;
    }
    for (final id in serverSteps(_enabled)) {
      _live[id] = NodeState.running;
    }
    setState(() {});
    final report = await runServerPipeline(
      photo.jpeg,
      skip: serverSkip(_enabled),
    );
    if (!mounted) return;
    setState(() {
      for (final stage in report.stages) {
        _live[stage.id] = switch (stage.state) {
          'passed' => NodeState.passed,
          'failed' => NodeState.failed,
          'noted' => NodeState.noted,
          'skipped' => NodeState.skipped,
          'not_reached' => NodeState.stopped,
          _ => NodeState.waiting,
        };
      }
      _passed = report.passed;
      _banner = _summary(report);
    });
  }

  PhotoCheck _phoneCheck(String id) => switch (id) {
    '01' => _faces,
    '03' => _integrity,
    '04' => _forensics,
    '02' => _clip,
    _ => throw ArgumentError(id),
  };

  void _failAt(String id, List<String> reasons) {
    final text = reasons.map((code) => reasonText[code] ?? code).join(' ');
    setState(() {
      _live[id] = NodeState.failed;
      _passed = false;
      _banner = text.isEmpty
          ? 'Retake. Step $id failed, so the photo was not sent on.'
          : 'Retake. $text The photo was not sent on.';
      for (final stage in flowStages) {
        if (_live[stage.id] == null &&
            _stateWouldRun(stage) &&
            _after(stage.id, id)) {
          _live[stage.id] = NodeState.stopped;
        }
      }
    });
  }

  bool _stateWouldRun(FlowStage stage) {
    if (_path == PipelinePath.upload && stage.captureOnly) return false;
    return stageEnabled(_enabled, stage.id);
  }

  bool _after(String id, String failed) {
    const order = ['01', '03', '04', '02', '08', '07', '06', '09'];
    return order.indexOf(id) > order.indexOf(failed);
  }

  String _summary(ServerPipelineReport report) {
    if (report.passed && report.advisory.isEmpty) {
      return 'Passed. Every step that was switched on accepted the photo.';
    }
    if (report.passed) {
      final notes = report.advisory.map((c) => reasonText[c] ?? c).join(' ');
      return 'Passed. Step 06 noted: $notes It did not reject the photo on its own.';
    }
    final why = report.reasons.map((c) => reasonText[c] ?? c).join(' ');
    final at = report.stoppedAt ?? 'the server';
    return 'Retake. Stopped at $at. $why';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capture = _path == PipelinePath.capture;
    return Scaffold(
      appBar: AppBar(
        title: const Text('15 · Pipeline'),
        actions: [
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ApproachDetailScreen(details: approachDetails['15']!),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<PipelinePath>(
            segments: const [
              ButtonSegment(
                value: PipelinePath.capture,
                label: Text('Capture'),
                icon: Icon(Icons.photo_camera),
              ),
              ButtonSegment(
                value: PipelinePath.upload,
                label: Text('Upload'),
                icon: Icon(Icons.photo_library_outlined),
              ),
            ],
            selected: {_path},
            onSelectionChanged: _running
                ? null
                : (next) => _setPath(next.first),
          ),
          const SizedBox(height: 8),
          Text(
            capture
                ? 'Taken in the app: tap the shutter, then BlazeFace, the live-capture check, and the rules. A failure stops the run.'
                : 'Chosen from the gallery: BlazeFace runs on the file. The live-capture check is skipped. The rules run next.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FlowDiagram(stages: _rows),
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('Switches'),
            subtitle: const Text('Turn a step off to skip it'),
            initiallyExpanded: true,
            children: [
              for (final stage in flowStages)
                SwitchListTile(
                  title: Text('${stage.id} · ${stage.title}'),
                  subtitle: Text(
                    !capture && stage.captureOnly
                        ? 'An upload always skips this'
                        : stage.advisory
                        ? 'A failure is kept as a note'
                        : stage.blurb,
                  ),
                  value: capture || !stage.captureOnly
                      ? stageEnabled(_enabled, stage.id)
                      : false,
                  onChanged: _running || (!capture && stage.captureOnly)
                      ? null
                      : (on) => _toggle(stage.id, on),
                ),
            ],
          ),
          if (_banner != null) ...[
            const SizedBox(height: 8),
            Material(
              color: (_passed ?? false)
                  ? Colors.green.shade700
                  : theme.colorScheme.error,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _banner!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    capture ? Icons.photo_camera : Icons.photo_library_outlined,
                  ),
            label: Text(
              _running
                  ? 'Running…'
                  : capture
                  ? 'Take the photo'
                  : 'Choose from the gallery',
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera screen for the pipeline. It only returns the photo; BlazeFace runs after.
class _ShutterOnly extends PhotoCheck {
  @override
  String get id => '15';

  @override
  String get title => 'Pipeline capture';

  @override
  String get scoreLabel => '';

  @override
  List<Tunable> get tunables => const [];

  @override
  bool get acceptsGallery => false;

  @override
  Future<CheckResult> check(CapturedPhoto photo) =>
      throw UnsupportedError('The pipeline runs the checks after the shutter.');
}
