import 'package:flutter/material.dart';

import '../approaches/approach_details.dart';

/// "How it works" page for one approach: pipeline, components, thresholds,
/// what it catches and misses, how it was checked, limitations and code locations.
class ApproachDetailScreen extends StatelessWidget {
  const ApproachDetailScreen({super.key, required this.details, this.onOpen});

  final ApproachDetails details;

  /// Opens the approach's camera; null when we came from the camera screen.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = details;
    return Scaffold(
      appBar: AppBar(title: Text('${d.id} · ${d.title}')),
      bottomNavigationBar: onOpen == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Try it'),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            d.question,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          _Section('How it works', [
            for (var i = 0; i < d.steps.length; i++)
              _Numbered(i + 1, d.steps[i]),
          ]),
          _Section('Components', [
            for (final c in d.components) _ComponentCard(c),
          ]),
          _Section('Default thresholds', [
            for (final (name, value) in d.thresholds)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(name)),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'All adjustable from the camera screen (tune button).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ]),
          _Section('Catches', [
            for (final s in d.catches)
              _Bullet(s, icon: Icons.check, color: Colors.green.shade700),
          ]),
          _Section('Misses', [
            for (final s in d.misses)
              _Bullet(s, icon: Icons.close, color: theme.colorScheme.error),
          ]),
          _Section('How we checked it', [
            for (final s in d.verified) _Bullet(s),
          ]),
          _Section('Limitations', [for (final s in d.limitations) _Bullet(s)]),
          _Section('Code', [
            for (final s in d.code)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  s,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Numbered extends StatelessWidget {
  const _Numbered(this.n, this.text);

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              '$n',
              style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.icon = Icons.circle, this.color});

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              icon,
              size: icon == Icons.circle ? 6 : 16,
              color: color ?? Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard(this.c);

  final Component c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.name, style: theme.textTheme.titleSmall),
                ),
                _Chip(
                  c.kind,
                  scheme.secondaryContainer,
                  scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 4),
                _Chip(
                  c.license,
                  scheme.tertiaryContainer,
                  scheme.onTertiaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(c.role, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.background, this.foreground);

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}
