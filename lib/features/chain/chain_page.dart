import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/env.dart';
import '../../core/providers/profiles_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';

/// Chains: hops before the selected server and an optional exit after it.
///
///   app → hop 1 → hop 2 → [selected server] → exit → internet
///
/// Presets create WARP devices on demand ("Exit via WARP", "WARP in WARP").
class ChainPage extends ConsumerStatefulWidget {
  const ChainPage({super.key});
  @override
  ConsumerState<ChainPage> createState() => _ChainPageState();
}

class _ChainPageState extends ConsumerState<ChainPage> {
  bool _busy = false;

  Future<NodeRow?> _row(String id) => ref.read(envProvider).repo.nodeRow(id);

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// selected → WARP
  Future<void> _warpExit() => _run(() async {
    final id = await ref
        .read(profilesProvider.notifier)
        .addWarp(name: 'WARP exit');
    ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(exitNodeId: id, chainNodeIds: const []));
    if (mounted) showSnack(context, context.s.t('chain.warp.created'));
  });

  /// WARP A → WARP B (B becomes the selected server).
  Future<void> _warpInWarp() => _run(() async {
    final p = ref.read(profilesProvider.notifier);
    final a = await p.addWarp(name: 'WARP A (outer)');
    final b = await p.addWarp(name: 'WARP B (inner)');
    ref
        .read(settingsProvider.notifier)
        .update(
          (x) => x.copyWith(
            chainNodeIds: [a],
            exitNodeId: '',
            activeNodeId: b,
            activeProfileId: 'warp',
          ),
        );
    if (mounted) showSnack(context, context.s.t('chain.warp.created'));
  });

  Future<void> _addWarpWithLicense() async {
    final s = context.s;
    final lic = await promptText(context, title: s.t('chain.warp.license'));
    if (lic == null) return;
    await _run(() async {
      await ref
          .read(profilesProvider.notifier)
          .addWarp(name: lic.isEmpty ? 'WARP' : 'WARP+', license: lic.trim());
      if (mounted) showSnack(context, s.t('chain.warp.created'));
    });
  }

  Future<String?> _pickNode() async {
    final all = await ref.read(envProvider).repo.query(limit: 300);
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.s.t('chain.pick')),
        children: [
          SizedBox(
            width: 420,
            height: 420,
            child: ListView(
              children: [
                for (final r in all.rows)
                  ListTile(
                    dense: true,
                    title: Text(r.name, maxLines: 1),
                    subtitle: Text(r.protocol.toUpperCase()),
                    onTap: () => Navigator.pop(ctx, r.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final st = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('chain.title')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('chain.desc')),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(s.t('chain.preset.warp_exit')),
                  subtitle: Text(s.t('chain.preset.warp_exit.desc')),
                  onTap: _busy ? null : _warpExit,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: Text(s.t('chain.preset.warp_in_warp')),
                  subtitle: Text(s.t('chain.preset.warp_in_warp.desc')),
                  onTap: _busy ? null : _warpInWarp,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(s.t('chain.warp.add')),
                  subtitle: Text(s.t('chain.warp.license')),
                  onTap: _busy ? null : _addWarpWithLicense,
                ),
              ],
            ),
          ),
          SectionHeader(s.t('chain.hops')),
          for (var i = 0; i < st.chainNodeIds.length; i++)
            FutureBuilder<NodeRow?>(
              future: _row(st.chainNodeIds[i]),
              builder: (ctx, snap) => ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(snap.data?.name ?? st.chainNodeIds[i]),
                subtitle: Text(snap.data?.protocol.toUpperCase() ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => set.update(
                    (x) => x.copyWith(
                      chainNodeIds: [...x.chainNodeIds]..removeAt(i),
                    ),
                  ),
                ),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add_link),
            title: Text(s.t('chain.add_hop')),
            onTap: () async {
              final id = await _pickNode();
              if (id != null) {
                set.update(
                  (x) => x.copyWith(chainNodeIds: [...x.chainNodeIds, id]),
                );
              }
            },
          ),
          SectionHeader(s.t('chain.exit')),
          FutureBuilder<NodeRow?>(
            future: st.exitNodeId.isEmpty
                ? Future.value(null)
                : _row(st.exitNodeId),
            builder: (ctx, snap) => ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(snap.data?.name ?? s.t('chain.exit.none')),
              trailing: st.exitNodeId.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          set.update((x) => x.copyWith(exitNodeId: '')),
                    ),
              onTap: () async {
                final id = await _pickNode();
                if (id != null) set.update((x) => x.copyWith(exitNodeId: id));
              },
            ),
          ),
          const SizedBox(height: 8),
          if (st.chainNodeIds.isNotEmpty || st.exitNodeId.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off),
              label: Text(s.t('chain.clear')),
              onPressed: () => set.update(
                (x) => x.copyWith(chainNodeIds: const [], exitNodeId: ''),
              ),
            ),
          const SizedBox(height: 12),
          Text(s.t('chain.note'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
