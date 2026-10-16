import 'package:flutter/material.dart';

import '../approaches/a15_pipeline/pipeline_screen.dart';
import '../approaches/final_capture/final_capture_screen.dart';
import '../approaches/approach_details.dart';
import '../approaches/registry.dart';
import '../approaches/server/server_check.dart';
import 'approach_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  /// [ping] is the server health check (replaced in tests).
  const HomeScreen({super.key, this.ping = pingServer});

  final Future<String> Function() ping;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _status = ValueNotifier<ServerStatus>(ServerStatus.unknown());

  @override
  void initState() {
    super.initState();
    _check();
    // First launch: ask for the Mac's address right away.
    if (!ServerSettings.isSet) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showServerDialog(context);
        _check();
      });
    }
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (!ServerSettings.isSet) {
      _status.value = ServerStatus.notSet();
      return;
    }
    _status.value = ServerStatus.checking();
    try {
      final approaches = await widget.ping();
      _status.value = ServerStatus.connected(approaches);
    } catch (e) {
      _status.value = ServerStatus.failed('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('HumanDetect lab'),
        actions: [
          // Always visible, so the server can be checked and changed without scrolling.
          ValueListenableBuilder<ServerStatus>(
            valueListenable: _status,
            builder: (context, st, _) => IconButton(
              tooltip: 'Server: ${st.message.isEmpty ? 'unknown' : st.message}',
              onPressed: () async {
                await showServerDialog(context);
                _check();
              },
              icon: Icon(
                switch (st.link) {
                  LinkState.connected => Icons.cloud_done,
                  LinkState.failed => Icons.cloud_off,
                  LinkState.checking => Icons.cloud_sync,
                  _ => Icons.cloud_queue,
                },
                color: switch (st.link) {
                  LinkState.connected => Colors.green.shade700,
                  LinkState.failed => theme.colorScheme.error,
                  _ => null,
                },
              ),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            sliver: SliverToBoxAdapter(
              child: Card(
                clipBehavior: Clip.antiAlias,
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.photo_camera_front_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  title: const Text('Final capture'),
                  subtitle: const Text(
                    'A face on this phone, then the same check on the server.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FinalCaptureScreen(),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            sliver: SliverToBoxAdapter(
                child: Card.filled(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('15 · Pipeline'),
                  subtitle: const Text(
                    'Two paths. Switches skip a step.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PipelineScreen(),
                    ),
                  ),
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
              child: _ServerBar(
                status: _status,
                onChange: () async {
                  await showServerDialog(context);
                  _check();
                },
                onRefresh: _check,
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
                'Lab tiles keep a photo in memory. Final capture sends it to your server after this phone finds a face.',
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

enum LinkState { notSet, checking, connected, failed, unknown }

/// What the home screen knows about the server right now.
class ServerStatus {
  const ServerStatus._(this.link, this.message);
  factory ServerStatus.unknown() => const ServerStatus._(LinkState.unknown, '');
  factory ServerStatus.notSet() =>
      const ServerStatus._(LinkState.notSet, 'No address yet');
  factory ServerStatus.checking() =>
      const ServerStatus._(LinkState.checking, 'Checking…');
  factory ServerStatus.connected(String approaches) =>
      ServerStatus._(LinkState.connected, 'Connected · approaches $approaches');
  factory ServerStatus.failed(String why) =>
      ServerStatus._(LinkState.failed, why);

  final LinkState link;
  final String message;
}

class _ServerBar extends StatelessWidget {
  const _ServerBar({
    required this.status,
    required this.onChange,
    required this.onRefresh,
  });

  final ValueNotifier<ServerStatus> status;
  final VoidCallback onChange;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<ServerStatus>(
      valueListenable: status,
      builder: (context, st, _) {
        final (color, icon) = switch (st.link) {
          LinkState.connected => (Colors.green.shade700, Icons.check_circle),
          LinkState.failed => (theme.colorScheme.error, Icons.error),
          LinkState.checking => (theme.colorScheme.outline, Icons.sync),
          _ => (theme.colorScheme.outline, Icons.dns_outlined),
        };
        return Card.outlined(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tier 2 · runs on your Mac (server)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ServerSettings.isSet
                                ? ServerSettings.url
                                : 'Not connected',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            st.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Check again',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                    ),
                    TextButton(
                      onPressed: onChange,
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Address and token of the server the Tier 2 tiles talk to. The address can be a bare
/// IP ("192.168.1.23"), which gets "http://" and port 8765. Test checks it before saving;
/// Cancel keeps the previous settings.
Future<void> showServerDialog(BuildContext context) {
  final oldUrl = ServerSettings.url, oldToken = ServerSettings.token;
  final url = TextEditingController(text: ServerSettings.url);
  final token = TextEditingController(text: ServerSettings.token);
  String? status;
  var ok = false;
  var testing = false;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Server on your Mac'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Start the server on the Mac (server/start_mac.sh), keep the phone on '
                'the same Wi-Fi, and type the address the script prints. A Mac\'s '
                'address can change, so come back here if it stops connecting.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Mac address',
                  hintText: '192.168.1.23   or   http://192.168.1.23:8765',
                ),
              ),
              TextField(
                controller: token,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Token (leave empty unless the server sets one)',
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 12),
                Text(
                  status!,
                  style: TextStyle(
                    color: ok
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: testing
                ? null
                : () async {
                    ServerSettings.url = normalizeAddress(url.text);
                    ServerSettings.token = token.text.trim();
                    url.text = ServerSettings.url;
                    setState(() {
                      testing = true;
                      ok = false;
                      status = 'Testing…';
                    });
                    try {
                      final found = await pingServer();
                      ok = true;
                      status = 'Connected. Approaches on the server: $found';
                    } catch (e) {
                      status = '$e';
                    }
                    setState(() => testing = false);
                  },
            child: const Text('Test'),
          ),
          TextButton(
            onPressed: () {
              ServerSettings.url = oldUrl;
              ServerSettings.token = oldToken;
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ServerSettings.save(url.text, token.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
