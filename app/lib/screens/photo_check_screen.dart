import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/check.dart';
import '../core/image_ops.dart';
import '../approaches/approach_details.dart';
import 'approach_detail_screen.dart';
import 'result_screen.dart';
import 'tunables_sheet.dart';

/// Camera screen shared by the photo-based approaches (01-04). The only way to get a
/// photo in is to take it here: there is no gallery picker anywhere in the app.
class PhotoCheckScreen extends StatefulWidget {
  const PhotoCheckScreen({super.key, required this.check});

  final PhotoCheck check;

  @override
  State<PhotoCheckScreen> createState() => _PhotoCheckScreenState();
}

class _PhotoCheckScreenState extends State<PhotoCheckScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  CameraLensDirection _lens = CameraLensDirection.back;
  late final Future<void> _prepared = widget.check.prepare();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepared.catchError(
      (Object e) => setState(
        () => _error =
            'Could not load the model: $e\n\n'
            'Model files are fetched separately: see app/README.md.',
      ),
    );
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      final description = _cameras.firstWhere(
        (c) => c.lensDirection == _lens,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();
      final old = _controller;
      _controller = controller;
      await old?.dispose();
      widget.check.startSession();
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      setState(() => _error = 'Camera unavailable: ${e.description ?? e.code}');
    }
  }

  Future<void> _switchCamera() async {
    _lens = _lens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    await _start();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _prepared;
      final file = await controller.takePicture();
      final capturedAt = DateTime.now();
      final jpeg = await file.readAsBytes();
      await File(file.path).delete(); // keep customer photos in memory only
      final watch = Stopwatch()..start();
      final decoded = await Isolate.run(() => _decode(jpeg));
      watch.stop();
      final photo = CapturedPhoto(
        jpeg: jpeg,
        image: decoded.image,
        capturedAt: capturedAt,
        frontCamera: _lens == CameraLensDirection.front,
        decodeTime: watch.elapsed,
      );
      final result = await widget.check.check(photo);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            title: '${widget.check.id} · ${widget.check.title}',
            scoreLabel: widget.check.scoreLabel,
            photo: photo,
            preview: decoded.preview,
            result: result,
          ),
        ),
      );
      widget.check.startSession(); // a new photo is a new session
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Check failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.check.id} · ${widget.check.title}'),
        actions: [
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ApproachDetailScreen(
                  details: approachDetails[widget.check.id]!,
                ),
              ),
            ),
          ),
          if (widget.check.tunables.isNotEmpty)
            IconButton(
              tooltip: 'Thresholds',
              icon: const Icon(Icons.tune),
              onPressed: () => showTunablesSheet(
                context,
                widget.check.title,
                widget.check.tunables,
              ),
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
                Expanded(
                  child: Center(
                    child: controller == null || !controller.value.isInitialized
                        ? const CircularProgressIndicator()
                        : CameraPreview(controller),
                  ),
                ),
                _ShutterBar(
                  busy: _busy,
                  onCapture: _capture,
                  onSwitch: _cameras.length > 1 ? _switchCamera : null,
                ),
              ],
            ),
    );
  }
}

class _ShutterBar extends StatelessWidget {
  const _ShutterBar({
    required this.busy,
    required this.onCapture,
    required this.onSwitch,
  });

  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 48),
            SizedBox(
              width: 76,
              height: 76,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : FloatingActionButton.large(
                      heroTag: 'shutter',
                      backgroundColor: Colors.white,
                      onPressed: onCapture,
                      child: const Icon(Icons.camera_alt, color: Colors.black),
                    ),
            ),
            IconButton(
              tooltip: 'Switch camera',
              onPressed: busy ? null : onSwitch,
              icon: const Icon(Icons.cameraswitch, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs in a background isolate: JPEG -> upright RGB plus a small preview for display.
({RgbImage image, ({Uint8List rgba, int width, int height}) preview}) _decode(
  Uint8List jpeg,
) {
  final image = RgbImage.fromJpeg(jpeg);
  var w = 0, h = 0;
  final rgba = image.previewRgba(900, (pw, ph) {
    w = pw;
    h = ph;
  });
  return (image: image, preview: (rgba: rgba, width: w, height: h));
}
