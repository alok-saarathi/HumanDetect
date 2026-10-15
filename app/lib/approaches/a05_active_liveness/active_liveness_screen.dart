import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/check.dart';
import '../../core/image_ops.dart';
import '../../screens/approach_detail_screen.dart';
import '../../screens/result_screen.dart';
import '../approach_details.dart';
import '../../screens/tunables_sheet.dart';
import '../a01_face_detection/blazeface.dart';
import 'face_mesh.dart';
import 'frame_convert.dart';
import 'liveness_session.dart';

/// Approach 05: live video. The person must blink and turn their head on request;
/// a printout or a still photo on a screen can't follow random instructions.
class ActiveLivenessScreen extends StatefulWidget {
  const ActiveLivenessScreen({super.key, this.handBack = false});

  /// Pop with the photo and verdict instead of opening the result page.
  /// The pipeline continues from there, and does not continue when this fails.
  final bool handBack;

  @override
  State<ActiveLivenessScreen> createState() => _ActiveLivenessScreenState();
}

class _ActiveLivenessScreenState extends State<ActiveLivenessScreen>
    with WidgetsBindingObserver {
  static const _title = 'Active liveness';

  final _settings = LivenessSettings();
  late final _tunables = [
    Tunable(
      label: 'Turn threshold (nose offset, 0..1)',
      min: 0.15,
      max: 0.7,
      initial: _settings.turnThreshold,
    ),
    Tunable(
      label: 'Eyes closed below × open level',
      min: 0.3,
      max: 0.9,
      initial: _settings.closeRatio,
    ),
    Tunable(
      label: 'Seconds per challenge',
      min: 3,
      max: 15,
      initial: 7,
      decimals: 0,
    ),
    Tunable(
      label: 'Min face area (share of frame)',
      min: 0.01,
      max: 0.3,
      initial: _settings.minFaceArea,
      decimals: 3,
    ),
  ];

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  CameraLensDirection _lens = CameraLensDirection.back;
  BlazeFace? _detector;
  FaceMesh? _mesh;
  String? _error;

  LivenessSession? _session;
  bool _processing = false;
  bool _finishing = false;
  bool _starting = false;
  int _sensorOrientation = 0; // of the camera the running check streams from
  FrameObservation? _last;
  Rect? _faceBox;
  int _frames = 0;
  DateTime? _streamStart;

  bool get _front => _lens == CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// Leaving the app mid-check cancels it (a live check can't pause); the camera is
  /// released and reopened on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      if (controller == null || _finishing) return;
      final cancelled = _session != null;
      setState(() {
        _session = null;
        _controller = null;
      });
      controller.dispose();
      if (cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check cancelled: the app was left.')),
        );
      }
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _cameras.isNotEmpty) {
      _openCamera();
    }
  }

  Future<void> _init() async {
    try {
      _detector = await BlazeFace.load();
      _mesh = await FaceMesh.load();
      _cameras = await availableCameras();
      await _openCamera();
    } catch (e) {
      setState(
        () => _error =
            'Could not start: $e\n\nModel files are fetched separately: see app/README.md.',
      );
    }
  }

  Future<void> _openCamera() async {
    if (_starting) return;
    _starting = true;
    try {
      await _openCameraNow();
    } finally {
      _starting = false;
    }
  }

  Future<void> _openCameraNow() async {
    final description = _cameras.firstWhere(
      (c) => c.lensDirection == _lens,
      orElse: () => _cameras.first,
    );
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    final old = _controller;
    _controller = controller;
    await old?.dispose();
    if (mounted) setState(() {});
  }

  void _applyTunables() {
    _settings
      ..turnThreshold = _tunables[0].value
      ..closeRatio = _tunables[1].value
      ..challengeTimeout = Duration(seconds: _tunables[2].value.round())
      ..minFaceArea = _tunables[3].value;
  }

  Future<void> _startChallenge() async {
    final controller = _controller;
    if (controller == null) return;
    _applyTunables();
    _sensorOrientation = controller.description.sensorOrientation;
    setState(() {
      _session = LivenessSession(_settings);
      _frames = 0;
      _streamStart = DateTime.now();
      _finishing = false;
    });
    await controller.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage frame) {
    final session = _session;
    if (_processing || _finishing || session == null) return;
    _processing = true;
    try {
      final rgb = yuvToUprightRgb(frame, _sensorOrientation, mirror: _front);
      final faces = _detector!.detect(rgb.rgb, rgb.width, rgb.height)
        ..sort((a, b) => b.area.compareTo(a.area));
      FrameObservation obs;
      if (faces.isEmpty) {
        obs = const FrameObservation(faceCount: 0);
        _faceBox = null;
      } else {
        final face = faces.first;
        final mesh = _mesh!.run(rgb, face);
        final ear =
            (eyeAspectRatio(mesh.landmarks, eyeA) +
                eyeAspectRatio(mesh.landmarks, eyeB)) /
            2;
        // Front camera frames are mirrored like a mirror: the person's left is on the
        // image's left. Back camera: the person's left is on the image's right.
        final yaw = yawSignal(mesh.landmarks) * (_front ? 1 : -1);
        obs = FrameObservation(
          faceCount: faces.where((f) => f.score >= 0.6).length.clamp(1, 99),
          presence: mesh.presence,
          faceArea: face.area,
          centerX: face.x + face.w / 2,
          centerY: face.y + face.h / 2,
          ear: ear,
          yaw: yaw,
        );
        _faceBox = Rect.fromLTWH(face.x, face.y, face.w, face.h);
      }
      _frames++;
      session.update(obs, DateTime.now());
      _last = obs;
      if (mounted) setState(() {});
      if (session.phase == LivenessPhase.passed ||
          session.phase == LivenessPhase.failed) {
        _finish();
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final controller = _controller!;
    final session = _session!;
    final elapsed = DateTime.now().difference(_streamStart!);
    try {
      await controller.stopImageStream();
      final file = await controller.takePicture();
      final capturedAt = DateTime.now();
      final jpeg = await file.readAsBytes();
      await File(file.path).delete();
      final watch = Stopwatch()..start();
      final decoded = await decodePhotoInBackground(jpeg, gallery: false);
      watch.stop();
      final photo = CapturedPhoto(
        jpeg: jpeg,
        image: decoded.image,
        capturedAt: capturedAt,
        source: PhotoSource.camera,
        frontCamera: _front,
        decodeTime: watch.elapsed,
      );
      final result = _resultOf(session, elapsed);
      if (!mounted) return;
      if (widget.handBack) {
        Navigator.of(context).pop((photo: photo, result: result));
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            title: '05 · $_title',
            scoreLabel: 'challenges completed',
            photo: photo,
            preview: decoded.preview,
            result: result,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not finish: $e')));
      }
    } finally {
      if (mounted) setState(() => _session = null);
    }
  }

  CheckResult _resultOf(LivenessSession s, Duration elapsed) {
    final fps =
        _frames / (elapsed.inMilliseconds / 1000).clamp(0.001, double.infinity);
    return CheckResult(
      passed: s.phase == LivenessPhase.passed,
      score: s.timeline.length / s.challenges.length,
      reasons: [?s.failReason],
      latency: elapsed,
      details: [
        for (final c in s.challenges)
          (
            c.selfie,
            switch (s.timeline.where((t) => t.$1 == c)) {
              final done when done.isNotEmpty =>
                '✓ in ${(done.first.$2.inMilliseconds / 1000).toStringAsFixed(1)} s',
              _ => '✗ not completed',
            },
          ),
        if (s.baselineEar != null)
          (
            'Eye openness (open / lowest)',
            '${s.baselineEar!.toStringAsFixed(3)} / '
                '${s.minEar.isFinite ? s.minEar.toStringAsFixed(3) : '-'}',
          ),
        (
          'Furthest turn left / right',
          '${s.maxLeft.toStringAsFixed(2)} / ${s.maxRight.toStringAsFixed(2)}',
        ),
        ('Frames analysed', '$_frames (${fps.toStringAsFixed(1)} per second)'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final session = _session;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('05 · $_title'),
        actions: [
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ApproachDetailScreen(details: approachDetails['05']!),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Thresholds',
            icon: const Icon(Icons.tune),
            onPressed: session == null
                ? () => showTunablesSheet(context, _title, _tunables)
                : null,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : Column(
              children: [
                _InstructionBar(session: session, agentMode: !_front),
                Expanded(
                  child: Center(
                    child: controller == null || !controller.value.isInitialized
                        ? const CircularProgressIndicator()
                        : CameraPreview(
                            controller,
                            child: CustomPaint(
                              painter: _FacePainter(_faceBox),
                              size: Size.infinite,
                            ),
                          ),
                  ),
                ),
                if (session != null && _last != null)
                  _DebugLine(_last!, session),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: session == null && controller != null
                                ? _startChallenge
                                : null,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              session == null ? 'Start check' : 'Checking…',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          tooltip: 'Switch camera',
                          onPressed: session == null && _cameras.length > 1
                              ? () async {
                                  _lens = _front
                                      ? CameraLensDirection.back
                                      : CameraLensDirection.front;
                                  await _openCamera();
                                }
                              : null,
                          icon: const Icon(Icons.cameraswitch),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InstructionBar extends StatelessWidget {
  const _InstructionBar({required this.session, required this.agentMode});

  final LivenessSession? session;
  final bool agentMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final String text;
    if (s == null) {
      text = agentMode
          ? 'Point the camera at the person, then press Start. Read the instructions out to them.'
          : 'Hold the phone at arm\'s length, then press Start.';
    } else if (s.phase == LivenessPhase.positioning) {
      text = 'Face the camera and hold still…';
    } else if (s.current != null) {
      text = agentMode ? s.current!.agent : s.current!.selfie;
    } else {
      text = 'Done';
    }
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (s == null) ...[
            const SizedBox(height: 4),
            Text(
              'A gallery photo is not used here. This check needs a live blink and head turn.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
          if (s != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < s.challenges.length; i++)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      i < s.index
                          ? Icons.check_circle
                          : (i == s.index
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked),
                      size: 18,
                    ),
                    label: Text(s.challenges[i].name),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DebugLine extends StatelessWidget {
  const _DebugLine(this.o, this.session);

  final FrameObservation o;
  final LivenessSession session;

  @override
  Widget build(BuildContext context) {
    final base = session.baselineEar;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'faces ${o.faceCount} · eye ${o.ear?.toStringAsFixed(3) ?? '-'}'
        '${base != null ? ' (open ${base.toStringAsFixed(3)})' : ''} · turn ${o.yaw?.toStringAsFixed(2) ?? '-'}',
        style: const TextStyle(
          color: Colors.white70,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.box);

  final Rect? box;

  @override
  void paint(Canvas canvas, Size size) {
    final b = box;
    if (b == null) return;
    canvas.drawRect(
      Rect.fromLTRB(
        b.left * size.width,
        b.top * size.height,
        b.right * size.width,
        b.bottom * size.height,
      ),
      Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.box != box;
}
