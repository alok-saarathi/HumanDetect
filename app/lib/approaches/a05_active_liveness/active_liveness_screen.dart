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
import 'face_align.dart';
import 'face_mesh.dart';
import 'frame_convert.dart';
import 'liveness_session.dart';

/// Approach 05: live video. The face stays in the center box, and one blink
/// while it is there unlocks a single capture.
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
      label: 'Eyes closed below × open level',
      min: 0.3,
      max: 0.9,
      initial: _settings.closeRatio,
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

  final _blink = HeldBlink();
  bool _processing = false;
  bool _capturing = false;
  bool _starting = false;
  bool _streaming = false;
  bool _aligned = false;
  String _hint = 'Put your face in the box';
  int _sensorOrientation = 0; // of the camera the running check streams from
  FrameObservation? _last;
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
      if (controller == null || _capturing) return;
      setState(() {
        _controller = null;
        _streaming = false;
      });
      controller.dispose();
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
    _streaming = false;
    _controller = controller;
    await old?.dispose();
    _sensorOrientation = controller.description.sensorOrientation;
    await _ensureStream();
    if (mounted) setState(() {});
  }

  Future<void> _ensureStream() async {
    final controller = _controller;
    if (_streaming ||
        controller == null ||
        !controller.value.isInitialized ||
        _detector == null) {
      return;
    }
    _sensorOrientation = controller.description.sensorOrientation;
    await controller.startImageStream(_onFrame);
    _streaming = true;
  }

  void _onFrame(CameraImage frame) {
    if (_processing || _capturing || _detector == null || _mesh == null) return;
    _processing = true;
    try {
      final rgb = yuvToUprightRgb(frame, _sensorOrientation, mirror: _front);
      final faces = _detector!.detect(rgb.rgb, rgb.width, rgb.height)
        ..sort((a, b) => b.area.compareTo(a.area));
      final FrameObservation obs;
      if (faces.isEmpty) {
        obs = const FrameObservation(faceCount: 0);
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
      }
      final cue = judgeAlignment(
        obs,
        minFaceArea: _tunables[1].value,
        maxYaw: _settings.maxStartYaw,
      );
      _blink.update(
        aligned: cue.aligned,
        ear: obs.ear,
        now: DateTime.now(),
        closeRatio: _tunables[0].value,
      );
      _aligned = cue.aligned;
      _hint = _blink.ready
          ? 'You can capture.'
          : cue.aligned
          ? 'Stay aligned'
          : cue.hint;
      _last = obs;
      _streamStart ??= DateTime.now();
      _frames++;
      if (mounted) setState(() {});
    } finally {
      _processing = false;
    }
  }

  Future<void> _capture() async {
    if (_capturing || !_blink.ready) return;
    _capturing = true;
    final controller = _controller;
    if (controller == null) {
      _capturing = false;
      return;
    }
    final elapsed = DateTime.now().difference(_streamStart ?? DateTime.now());
    try {
      if (_streaming) {
        await controller.stopImageStream();
        _streaming = false;
      }
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
      final result = _resultOf(elapsed);
      if (!mounted) return;
      if (widget.handBack) {
        Navigator.of(context).pop((photo: photo, result: result));
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            title: '05 · $_title',
            scoreLabel: 'blink while aligned',
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
      _blink.reset();
      _capturing = false;
      if (mounted) {
        setState(() {});
        await _ensureStream();
      }
    }
  }

  CheckResult _resultOf(Duration elapsed) {
    final fps =
        _frames / (elapsed.inMilliseconds / 1000).clamp(0.001, double.infinity);
    final open = _blink.baselineEar;
    final low = _blink.minEar;
    return CheckResult(
      passed: true,
      score: 1,
      latency: elapsed,
      details: [
        ('Blink while aligned', 'seen'),
        if (open != null)
          (
            'Eye openness (open / lowest)',
            '${open.toStringAsFixed(3)} / '
                '${low.isFinite ? low.toStringAsFixed(3) : '-'}',
          ),
        ('Frames analysed', '$_frames (${fps.toStringAsFixed(1)} per second)'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = _blink.ready;
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
            onPressed: () => showTunablesSheet(context, _title, _tunables),
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
                _InstructionBar(hint: _hint, aligned: _aligned, ready: ready),
                Expanded(
                  child: Center(
                    child: controller == null || !controller.value.isInitialized
                        ? const CircularProgressIndicator()
                        : CameraPreview(
                            controller,
                            child: CustomPaint(
                              painter: _FacePainter(aligned: _aligned),
                              size: Size.infinite,
                            ),
                          ),
                  ),
                ),
                if (_last != null) _DebugLine(_last!, _blink.baselineEar),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                controller != null && ready && !_capturing
                                ? _capture
                                : null,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Capture'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          tooltip: 'Switch camera',
                          onPressed: !_capturing && _cameras.length > 1
                              ? () async {
                                  _lens = _front
                                      ? CameraLensDirection.back
                                      : CameraLensDirection.front;
                                  _blink.reset();
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
  const _InstructionBar({
    required this.hint,
    required this.aligned,
    required this.ready,
  });

  final String hint;
  final bool aligned;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hint,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ready
                ? 'Capture is ready.'
                : aligned
                ? 'Stay in the box.'
                : 'The box stays red until your face is in the center.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugLine extends StatelessWidget {
  const _DebugLine(this.o, this.baselineEar);

  final FrameObservation o;
  final double? baselineEar;

  @override
  Widget build(BuildContext context) {
    final base = baselineEar;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'faces ${o.faceCount} · eye ${o.ear?.toStringAsFixed(3) ?? '-'}'
        '${base != null ? ' (open ${base.toStringAsFixed(3)})' : ''}',
        style: const TextStyle(
          color: Colors.white70,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.aligned});

  final bool aligned;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          alignGuide.left * size.width,
          alignGuide.top * size.height,
          alignGuide.right * size.width,
          alignGuide.bottom * size.height,
        ),
        const Radius.circular(24),
      ),
      Paint()
        ..color = aligned ? Colors.greenAccent : Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.aligned != aligned;
}
