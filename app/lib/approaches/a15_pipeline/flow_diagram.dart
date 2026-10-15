import 'package:flutter/material.dart';

import 'plan.dart';

/// Vertical flowchart of the pipeline: phone stages, then server stages.
class FlowDiagram extends StatelessWidget {
  const FlowDiagram({super.key, required this.stages});

  final List<StageView> stages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = stages.where((s) => s.stage.onPhone).toList();
    final server = stages.where((s) => !s.stage.onPhone).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Band(
          label: 'On the phone',
          color: theme.colorScheme.primary,
          children: _boxes(context, phone),
        ),
        const _Arrow(),
        _Band(
          label: 'On the server — only if the phone passed',
          color: theme.colorScheme.tertiary,
          children: _boxes(context, server),
        ),
      ],
    );
  }

  List<Widget> _boxes(BuildContext context, List<StageView> group) {
    final out = <Widget>[];
    for (var i = 0; i < group.length; i++) {
      if (i > 0) out.add(const _Arrow());
      out.add(_NodeBox(group[i]));
    }
    return out;
  }
}

class _Band extends StatelessWidget {
  const _Band({
    required this.label,
    required this.color,
    required this.children,
  });

  final String label;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Icon(Icons.arrow_downward, size: 18),
    );
  }
}

class _NodeBox extends StatelessWidget {
  const _NodeBox(this.view);

  final StageView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, status) = _style(theme.colorScheme);
    final dim =
        view.state == NodeState.offPath ||
        view.state == NodeState.skipped ||
        view.state == NodeState.stopped;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dim ? 0.08 : 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color,
            child: Text(
              view.stage.id,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.stage.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  view.stage.blurb,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                status,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  (Color, IconData, String) _style(ColorScheme scheme) {
    return switch (view.state) {
      NodeState.waiting => (
        scheme.outline,
        Icons.radio_button_unchecked,
        'ready',
      ),
      NodeState.skipped => (scheme.outline, Icons.switch_left, 'off'),
      NodeState.offPath => (scheme.outline, Icons.block, 'upload skips'),
      NodeState.running => (scheme.primary, Icons.timelapse, 'running'),
      NodeState.passed => (Colors.green.shade700, Icons.check_circle, 'pass'),
      NodeState.failed => (scheme.error, Icons.cancel, 'fail'),
      NodeState.noted => (Colors.orange.shade800, Icons.flag, 'note'),
      NodeState.stopped => (
        scheme.outline,
        Icons.remove_circle_outline,
        'not run',
      ),
    };
  }
}
