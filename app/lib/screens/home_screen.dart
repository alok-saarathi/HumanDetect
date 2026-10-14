import 'package:flutter/material.dart';

import '../approaches/approach_details.dart';
import '../approaches/registry.dart';
import '../approaches/server/server_check.dart';
import 'approach_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('HumanDetect lab')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Tier 1 · no training, runs on this phone. Open an approach, take a photo '
                'or pick one from the gallery, and see what it decides and why. '
                'Capture integrity (03) and active liveness (05) use the camera only.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverToBoxAdapter(child: _Grid(tier1)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tier 2 · runs on the HumanDetect server',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => showServerDialog(context),
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    label: const Text('Server'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverToBoxAdapter(child: _Grid(tier2)),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Lab build for testing only. Photos stay in memory and are never saved or uploaded.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiles in rows of equal height that grow with their content (and with the phone's
/// font size), instead of a fixed aspect ratio that would clip text.
class _Grid extends StatelessWidget {
  const _Grid(this.tiles);

  final List<ApproachTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 220).floor().clamp(1, 4);
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < i + columns; j++) ...[
                        if (j > i) const SizedBox(width: 12),
                        Expanded(
                          child: j < tiles.length
                              ? _Tile(tiles[j])
                              : const SizedBox(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.tile);

  final ApproachTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.filled(
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => tile.open())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    tile.id,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(tile.icon, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tile.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tile.summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final c in tile.catches)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        c,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _openDetails(context),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ApproachDetailScreen(
          details: approachDetails[tile.id]!,
          onOpen: () => navigator.pushReplacement(
            MaterialPageRoute<void>(builder: (_) => tile.open()),
          ),
        ),
      ),
    );
  }
}

/// Address and token of the server the Tier 2 tiles talk to, with a connection test.
Future<void> showServerDialog(BuildContext context) {
  final url = TextEditingController(text: ServerSettings.url);
  final token = TextEditingController(text: ServerSettings.token);
  String? status;
  var testing = false;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('HumanDetect server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Photos are sent here for Tier 2 checks and judged in memory. '
              'Start the server with server/README.md, then use the computer\'s address.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: 'http://192.168.1.10:8000',
              ),
            ),
            TextField(
              controller: token,
              decoration: const InputDecoration(
                labelText: 'Token (only if the server sets one)',
              ),
            ),
            if (status != null) ...[const SizedBox(height: 12), Text(status!)],
          ],
        ),
        actions: [
          TextButton(
            onPressed: testing
                ? null
                : () async {
                    ServerSettings.url = url.text;
                    ServerSettings.token = token.text;
                    setState(() {
                      testing = true;
                      status = 'Testing…';
                    });
                    try {
                      status = await pingServer();
                    } catch (e) {
                      status = '$e';
                    }
                    setState(() => testing = false);
                  },
            child: const Text('Test'),
          ),
          FilledButton(
            onPressed: () {
              ServerSettings.url = url.text;
              ServerSettings.token = token.text;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
