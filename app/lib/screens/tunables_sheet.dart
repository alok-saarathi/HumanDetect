import 'package:flutter/material.dart';

import '../core/check.dart';

/// Bottom sheet with a slider per threshold. Changes apply to the next photo.
Future<void> showTunablesSheet(
  BuildContext context,
  String title,
  List<Tunable> tunables,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · thresholds',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Not calibrated yet. Changes apply to the next photo and reset when you leave.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final t in tunables) ...[
                Row(
                  children: [
                    Expanded(child: Text(t.label)),
                    Text(t.display),
                  ],
                ),
                Slider(
                  value: t.value.clamp(t.min, t.max),
                  min: t.min,
                  max: t.max,
                  divisions: t.divisions,
                  onChanged: (v) => setState(() => t.value = v),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
