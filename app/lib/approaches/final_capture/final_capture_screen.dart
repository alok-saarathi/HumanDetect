import 'package:flutter/material.dart';

import '../../core/check.dart';
import '../../screens/photo_check_screen.dart';
import '../server/server_check.dart';
import 'face_presence.dart';

/// Production path. A still from the shutter or the gallery, BlazeFace on this
/// phone, then the same check on the server. The server result is the decision.
class FinalCaptureScreen extends StatefulWidget {
  const FinalCaptureScreen({super.key, this.serverCheck = runFinalCapture});

  /// Replaced in tests. Receives the JPEG bytes.
  final Future<CheckResult> Function(List<int> jpeg) serverCheck;

  @override
  State<FinalCaptureScreen> createState() => _FinalCaptureScreenState();
}

class _FinalCaptureScreenState extends State<FinalCaptureScreen> {
  final _faces = FacePresenceCheck();
  bool _running = false;
  String? _status;
  CheckResult? _phone;
  CheckResult? _server;
  String? _error;

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = null;
      _phone = null;
      _server = null;
      _error = null;
    });
    try {
      final photo = await Navigator.of(context).push<CapturedPhoto>(
        MaterialPageRoute(
          builder: (context) => PhotoCheckScreen(
            check: _faces,
            onCaptured: (taken) => Navigator.of(context).pop(taken),
          ),
        ),
      );
      if (!mounted || photo == null) return;
      setState(() => _status = 'Checking for a face on this phone…');
      final phone = await _faces.check(photo);
      if (!mounted) return;
      setState(() => _phone = phone);
      if (!phone.passed) {
        setState(() => _status = 'This phone found no usable face, so nothing was sent.');
        return;
      }
      setState(() => _status = 'Face found. Asking the server…');
      final server = await widget.serverCheck(photo.jpeg);
      if (!mounted) return;
      setState(() {
        _server = server;
        _status = server.passed
            ? 'Passed. The server sees a person in this photo.'
            : 'The server did not see a usable face.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Final capture')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Take a photo or choose one from the gallery. This phone looks for a face, then sends the photo to the server for the same check. A photo of a screen or of a printed photograph is fine when a person is visible.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_outlined),
            label: Text(_running ? 'Working…' : 'Take or choose a photo'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: theme.textTheme.titleSmall),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_phone != null) ...[
            const SizedBox(height: 16),
            _StepCard(title: 'On this phone', result: _phone!),
          ],
          if (_server != null) ...[
            const SizedBox(height: 12),
            _StepCard(title: 'On the server', result: _server!),
          ],
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.title, required this.result});

  final String title;
  final CheckResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = result.passed
        ? Colors.green.shade700
        : theme.colorScheme.error;
    final why = result.reasons.map((code) => reasonText[code] ?? code).join(' ');
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.passed ? Icons.check_circle : Icons.cancel,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  result.passed ? 'Pass' : 'Fail',
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ],
            ),
            if (why.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(why),
            ],
            for (final row in result.details) ...[
              const SizedBox(height: 4),
              Text(
                '${row.$1}: ${row.$2}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
