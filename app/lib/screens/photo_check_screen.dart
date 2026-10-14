import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/check.dart';
import '../core/gallery_pick.dart';
import '../core/image_ops.dart';
import '../approaches/approach_details.dart';
import 'approach_detail_screen.dart';
import 'result_screen.dart';
import 'tunables_sheet.dart';

/// Camera screen shared by the photo-based approaches (01-04).
/// A photo comes from the shutter, or from the gallery when the check accepts it.
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
  String? _modelError;
  String? _cameraError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepared.catchError(
      (Object e) => setState(
        () => _modelError =
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
      setState(
        () => _cameraError = 'Camera unavailable: ${e.description ?? e.code}',
      );
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
      await _submit(
        jpeg,
        capturedAt: capturedAt,
        source: PhotoSource.camera,
        frontCamera: _lens == CameraLensDirection.front,
      );
    } catch (e) {
      _showFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickGallery() async {
    if (_busy || !widget.check.acceptsGallery) return;
    setState(() => _busy = true);
    try {
      await _prepared;
      final bytes = await pickGalleryImage();
      if (bytes == null || !mounted) return;
      await _submit(
        bytes,
        capturedAt: DateTime.now(),
        source: PhotoSource.gallery,
        frontCamera: false,
      );
    } catch (e) {
      _showFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(
    Uint8List bytes, {
    required DateTime capturedAt,
    required PhotoSource source,
    required bool frontCamera,
  }) async {
    final watch = Stopwatch()..start();
    // compute() sends a top-level function plus the bytes. A closure written
    // inside this method also captures this State, and its Future is not sendable.
    final decoded = await compute(
      source == PhotoSource.gallery ? _decodeEncoded : _decodeJpeg,
      bytes,
    );
    watch.stop();
    final photo = CapturedPhoto(
      jpeg: bytes,
      image: decoded.image,
      capturedAt: capturedAt,
      source: source,
      frontCamera: frontCamera,
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
  }

  void _showFailure(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Check failed: $e')));
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
      body: _modelError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _modelError!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: _cameraError != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _cameraError!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : controller == null || !controller.value.isInitialized
                        ? const CircularProgressIndicator()
                        : CameraPreview(controller),
                  ),
                ),
                if (!widget.check.acceptsGallery)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      'Gallery isn\'t offered here. This check only applies to a photo taken in this session.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                _ShutterBar(
                  busy: _busy,
                  canCapture:
                      controller != null && controller.value.isInitialized,
                  onCapture: _capture,
                  onGallery: widget.check.acceptsGallery ? _pickGallery : null,
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
    required this.canCapture,
    required this.onCapture,
    required this.onGallery,
    required this.onSwitch,
  });

  final bool busy;
  final bool canCapture;
  final VoidCallback onCapture;
  final VoidCallback? onGallery;
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
            onGallery == null
                ? const SizedBox(width: 48)
                : IconButton(
                    tooltip: 'Choose from gallery',
                    onPressed: busy ? null : onGallery,
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                    ),
                  ),
            SizedBox(
              width: 96,
              height: 96,
              child: IgnorePointer(
                ignoring: busy,
                child: FloatingActionButton.large(
                  // Stay in the tree while busy. Swapping this button out on
                  // tap deactivates its Hero mid-gesture and Flutter paints
                  // the red error block.
                  heroTag: null,
                  backgroundColor: Colors.white,
                  onPressed: canCapture ? onCapture : null,
                  child: busy
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.camera_alt, color: Colors.black),
                ),
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
({RgbImage image, ({Uint8List rgba, int width, int height}) preview})
_decodeJpeg(Uint8List jpeg) => _decodeWith(jpeg, RgbImage.fromJpeg);

/// Same as [_decodeJpeg], for gallery files that may be PNG, WebP, GIF or BMP.
({RgbImage image, ({Uint8List rgba, int width, int height}) preview})
_decodeEncoded(Uint8List bytes) => _decodeWith(bytes, RgbImage.fromEncoded);

({RgbImage image, ({Uint8List rgba, int width, int height}) preview})
_decodeWith(Uint8List bytes, RgbImage Function(Uint8List) decode) {
  final image = decode(bytes);
  var w = 0, h = 0;
  final rgba = image.previewRgba(900, (pw, ph) {
    w = pw;
    h = ph;
  });
  return (image: image, preview: (rgba: rgba, width: w, height: h));
}
