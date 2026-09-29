import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/database/node_repository.dart';
import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../core/providers/env.dart';
import '../../core/providers/node_list_provider.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/ping_provider.dart';
import '../../core/providers/profiles_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/util/formatters.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';

class ProxiesPage extends ConsumerStatefulWidget {
  const ProxiesPage({super.key});
  @override
  ConsumerState<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends ConsumerState<ProxiesPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        ref.read(nodeListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final list = ref.watch(nodeListProvider);
    final ping = ref.watch(pingProvider);
    final activeId = ref.watch(settingsProvider.select((x) => x.activeNodeId));
    final profiles = ref.watch(profilesProvider).value ?? const [];
    final ctl = ref.read(nodeListProvider.notifier);

    ref.listen(
      profilesProvider,
      (_, _) => ctl.reload(),
    ); // refreshed subscriptions

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('proxies.title')),
        actions: [
          PopupMenuButton<NodeSort>(
            tooltip: s.t('proxies.sort'),
            icon: const Icon(Icons.sort),
            onSelected: ctl.setSort,
            itemBuilder: (_) => [
              for (final o in NodeSort.values)
                CheckedPopupMenuItem(
                  value: o,
                  checked: list.sort == o,
                  child: Text(s.t('proxies.sort.${o.name}')),
                ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) {
              if (v == 'fav') ctl.setFavoritesFirst(!list.favoritesFirst);
              if (v == 'only') ctl.setOnlyFavorites(!list.onlyFavorites);
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'fav',
                checked: list.favoritesFirst,
                child: Text(s.t('proxies.favorites_first')),
              ),
              CheckedPopupMenuItem(
                value: 'only',
                checked: list.onlyFavorites,
                child: Text(s.t('proxies.only_favorites')),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(ping.running ? 4 : 0),
          child: ping.running
              ? LinearProgressIndicator(
                  value: ping.progress == 0 ? null : ping.progress,
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: ctl.setQuery,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.t('proxies.search'),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          ctl.setQuery('');
                          setState(() {});
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
          if (profiles.length > 1)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: ChoiceChip(
                      label: Text(s.t('proxies.all_profiles')),
                      selected: list.profileId == null,
                      onSelected: (_) => ctl.setProfile(null),
                    ),
                  ),
                  for (final p in profiles)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: ChoiceChip(
                        label: Text(p.name),
                        selected: list.profileId == p.id,
                        onSelected: (_) => ctl.setProfile(p.id),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                s.t('proxies.count', {'n': list.total}),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
          Expanded(
            child: list.rows.isEmpty && !list.loading
                ? EmptyState(
                    icon: Icons.dns_outlined,
                    title: s.t('proxies.empty'),
                    hint: s.t('proxies.empty.hint'),
                    action: FilledButton.icon(
                      onPressed: () =>
                          ref.read(navProvider.notifier).go(Dest.profiles),
                      icon: const Icon(Icons.add),
                      label: Text(s.t('subs.add')),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: list.rows.length + (list.hasMore ? 1 : 0),
                    itemExtent: 72,
                    itemBuilder: (context, i) {
                      if (i >= list.rows.length)
                        return const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      final r = list.rows[i];
                      return _NodeTile(row: r, active: r.id == activeId);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: PopupMenuButton<String>(
        onSelected: (v) {
          final p = ref.read(pingProvider.notifier);
          switch (v) {
            case 'stop':
              p.cancel();
            case 'all':
              p.run(profileId: list.profileId, mode: 'tcp');
            case 'visible':
              p.run(ids: list.rows.map((e) => e.id).toList(), mode: 'tcp');
            case 'url':
              p.run(ids: list.rows.map((e) => e.id).toList(), mode: 'url');
          }
        },
        itemBuilder: (_) => [
          if (ping.running)
            PopupMenuItem(value: 'stop', child: Text(s.t('proxies.stop'))),
          if (!ping.running) ...[
            PopupMenuItem(
              value: 'all',
              child: Text(
                '${s.t('proxies.ping_all')} · ${s.t('proxies.tcp_test')}',
              ),
            ),
            PopupMenuItem(
              value: 'visible',
              child: Text(s.t('proxies.ping_visible')),
            ),
            PopupMenuItem(
              value: 'url',
              child: Text(
                '${s.t('proxies.ping_visible')} · ${s.t('proxies.url_test')}',
              ),
            ),
          ],
        ],
        child: FloatingActionButton.extended(
          onPressed: null,
          icon: ping.running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.speed),
          label: Text(
            ping.running
                ? '${ping.done}/${ping.total}'
                : s.t('proxies.ping_all'),
          ),
        ),
      ),
    );
  }
}

class _NodeTile extends ConsumerWidget {
  const _NodeTile({required this.row, required this.active});
  final NodeRow row;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final cs = Theme.of(context).colorScheme;
    final needs = row.requires.isNotEmpty ? row.requires.join(', ') : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: active
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: active ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          onTap: () =>
              ref.read(coreControllerProvider.notifier).selectNode(row.id),
          onLongPress: () => _menu(context, ref),
          leading: ProtocolChip(protocolLabel(row.protocol)),
          title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            needs != null
                ? s.t('proxies.needs', {'cap': needs})
                : '${row.server}:${row.port}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: needs != null ? cs.error : null),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LatencyBadge(row.latency),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  row.isFavorite ? Icons.star : Icons.star_border,
                  color: row.isFavorite ? Colors.amber : cs.outline,
                ),
                onPressed: () =>
                    ref.read(nodeListProvider.notifier).toggleFavorite(row),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert),
                onPressed: () => _menu(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                row.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${row.server}:${row.port}'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(s.t('proxies.use')),
              onTap: () => Navigator.pop(ctx, 'use'),
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: Text(s.t('proxies.url_test')),
              onTap: () => Navigator.pop(ctx, 'test'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(s.t('proxies.copy_link')),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: Text(s.t('proxies.qr')),
              onTap: () => Navigator.pop(ctx, 'qr'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(s.t('common.rename')),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(s.t('common.delete')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (v == null || !context.mounted) return;
    final env = ref.read(envProvider);
    switch (v) {
      case 'use':
        await ref.read(coreControllerProvider.notifier).selectNode(row.id);
      case 'test':
        await ref.read(pingProvider.notifier).run(ids: [row.id], mode: 'url');
      case 'copy':
      case 'qr':
        final raw = await env.repo.rawNode(row.id);
        if (raw == null || !context.mounted) return;
        try {
          final link = await env.core.export('uri', [raw]);
          if (!context.mounted) return;
          if (v == 'copy') {
            await copyText(context, link);
          } else {
            showDialog<void>(
              context: context,
              builder: (_) => QrDialog(title: row.name, data: link),
            );
          }
        } catch (e) {
          if (context.mounted) showSnack(context, '$e', error: true);
        }
      case 'rename':
        final name = await promptText(
          context,
          title: s.t('common.rename'),
          initial: row.name,
        );
        if (name != null && name.isNotEmpty)
          await ref.read(nodeListProvider.notifier).rename(row, name);
      case 'delete':
        await ref.read(nodeListProvider.notifier).delete(row);
    }
  }
}

class QrDialog extends StatelessWidget {
  const QrDialog({super.key, required this.title, required this.data});
  final String title;
  final String data;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    content: SizedBox(
      width: 280,
      height: 280,
      child: data.length > 2500
          ? Center(child: Text(context.s.t('scan.unsupported')))
          : QrImageView(
              data: data,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(12),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => copyText(context, data),
        child: Text(context.s.t('common.copy')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.s.t('common.close')),
      ),
    ],
  );
}
