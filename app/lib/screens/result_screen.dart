import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/check.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.title,
    required this.scoreLabel,
    required this.photo,
    required this.preview,
    required this.result,
  });

  final String title;
  final String scoreLabel;
  final CapturedPhoto photo;
  final ({Uint8List rgba, int width, int height}) preview;
  final CheckResult result;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    final p = widget.preview;
    ui.decodeImageFromPixels(
      p.rgba,
      p.width,
      p.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted) setState(() => _image = image);
      },
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.result;
    final verdictColor = r.passed
        ? Colors.green.shade700
        : theme.colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: verdictColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  r.passed ? Icons.check_circle : Icons.cancel,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.passed ? 'PASS' : 'FAIL',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${widget.scoreLabel}: ${r.score.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (r.reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final code in r.reasons)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(reasonText[code] ?? code),
                subtitle: Text(code),
              ),
          ],
          const SizedBox(height: 12),
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _image!.width / _image!.height,
                child: CustomPaint(
                  painter: _PhotoPainter(
                    _image!,
                    r.marks,
                    theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (final (label, value) in r.details) _Row(label, value),
                  _Row('Check time', '${r.latency.inMilliseconds} ms'),
                  _Row(
                    'JPEG decode',
                    '${widget.photo.decodeTime.inMilliseconds} ms',
                  ),
                  _Row(
                    'Photo',
                    '${widget.photo.image.width}×${widget.photo.image.height}, '
                        '${widget.photo.originLabel}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.replay),
                  label: Text(
                    widget.photo.source == PhotoSource.gallery
                        ? 'Another photo'
                        : 'Retake',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.grid_view),
                  label: const Text('All approaches'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the photo and the approach's marks (face boxes, keypoints) on top.
class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.image, this.marks, this.color);

  final ui.Image image;
  final List<PhotoMark> marks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.fill,
    );
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final dot = Paint()..color = Colors.yellowAccent;
    for (final m in marks) {
      final box = m.box;
      if (box != null) {
        final rect = Rect.fromLTRB(
          box.left * size.width,
          box.top * size.height,
          box.right * size.width,
          box.bottom * size.height,
        );
        canvas.drawRect(rect, stroke);
        if (m.label != null) {
          final text = TextPainter(
            text: TextSpan(
              text: ' ${m.label} ',
              style: TextStyle(
                color: Colors.white,
                backgroundColor: color,
                fontSize: 13,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          text.paint(canvas, rect.topLeft - Offset(0, text.height));
        }
      }
      for (final p in m.points) {
        canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height),
          4,
          dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PhotoPainter old) =>
      old.image != image || old.marks != marks;
}
