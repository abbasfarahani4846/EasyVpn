import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../entry_server/entry_server_chain.dart';

typedef ServerGroup = ({
  String profile,
  int profileId,
  List<Map<String, Object?>> proxies,
});

/// Every server of every profile, grouped by profile, with search. Picking one
/// returns its full proxy map. Servers that live on this machine (Psiphon)
/// are left out because they cannot serve as someone else's entry.
class EasyAllServersPage extends ConsumerStatefulWidget {
  final String? selectedName;
  final String title;

  const EasyAllServersPage({super.key, this.selectedName, required this.title});

  @override
  ConsumerState<EasyAllServersPage> createState() => _EasyAllServersPageState();
}

class _EasyAllServersPageState extends ConsumerState<EasyAllServersPage> {
  List<ServerGroup> _groups = const [];
  String _filter = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final core = ref.read(coreHandlerProvider);
    final groups = <ServerGroup>[];
    for (final profile in ref.read(profilesProvider)) {
      try {
        final config = await core.getConfig(profile.id);
        final proxies = [
          for (final item in (config['proxies'] as List? ?? const []))
            if (item is Map &&
                item['name'] != null &&
                item['server'] != null &&
                !EntryServerChain.isLocal(item))
              Map<String, Object?>.from(item),
        ];
        if (proxies.isNotEmpty) {
          groups.add((
            profile: profile.realLabel,
            profileId: profile.id,
            proxies: proxies,
          ));
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  bool _matches(Map<String, Object?> proxy, String filter) {
    if (filter.isEmpty) return true;
    final haystack = '${proxy['name']} ${proxy['server']} ${proxy['type']}'
        .toLowerCase();
    return haystack.contains(filter);
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final filter = _filter.toLowerCase();
    final currentId = ref.watch(currentProfileIdProvider);
    final rows = <Widget>[];
    for (final group in _groups) {
      final shown = [
        for (final p in group.proxies)
          if (_matches(p, filter)) p,
      ];
      if (shown.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            '${group.profile} · ${shown.length}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
      for (final proxy in shown) {
        rows.add(
          _ServerTile(
            proxy: proxy,
            // Delays exist only for the profile the core is running.
            showDelay: group.profileId == currentId,
            selected: widget.selectedName == proxy['name'],
            onTap: () => Navigator.of(context).pop(proxy),
          ),
        );
      }
    }
    return CommonScaffold(
      title: widget.title,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              labelText: fa
                  ? 'جستجو (نام، آدرس، نوع)'
                  : 'Search (name, address, type)',
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                fa ? 'سروری پیدا نشد' : 'No servers found',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }
}

class _ServerTile extends ConsumerWidget {
  final Map<String, Object?> proxy;
  final bool showDelay;
  final bool selected;
  final VoidCallback onTap;

  const _ServerTile({
    required this.proxy,
    required this.showDelay,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = showDelay
        ? ref.watch(delayProvider(proxyName: '${proxy['name']}'))
        : null;
    final delayText = switch (delay) {
      null => '—',
      <= 0 => 'timeout',
      final ms => '$ms ms',
    };
    return ListTile(
      selected: selected,
      title: EmojiText(
        '${proxy['name']}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${proxy['type']} · ${proxy['server']}:${proxy['port']}'),
      trailing: Text(delayText, style: Theme.of(context).textTheme.bodySmall),
      onTap: onTap,
    );
  }
}
