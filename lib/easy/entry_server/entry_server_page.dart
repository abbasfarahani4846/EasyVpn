import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'entry_server_store.dart';

bool _isFa(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

class EasyEntryServerItem extends StatelessWidget {
  const EasyEntryServerItem({super.key});

  @override
  Widget build(BuildContext context) {
    final fa = _isFa(context);
    return ListItem.open(
      leading: const Icon(Icons.alt_route),
      title: Text(fa ? 'سرور ورودی (Chain)' : 'Entry server (chain)'),
      subtitle: Text(
        fa
            ? 'همه‌ی ترافیک و تست پینگ از یک سرور مشخص رد شود'
            : 'Route all traffic and ping tests through one server',
      ),
      widget: const EntryServerView(),
    );
  }
}

typedef _Candidate = ({Map<String, Object?> proxy, String profile});

class EntryServerView extends ConsumerStatefulWidget {
  const EntryServerView({super.key});

  @override
  ConsumerState<EntryServerView> createState() => _EntryServerViewState();
}

class _EntryServerViewState extends ConsumerState<EntryServerView> {
  Map<String, Object?>? _entry;
  List<_Candidate> _candidates = const [];
  String _filter = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final entry = await EntryServerStore.load();
    final core = ref.read(coreHandlerProvider);
    final candidates = <_Candidate>[];
    for (final profile in ref.read(profilesProvider)) {
      try {
        final config = await core.getConfig(profile.id);
        for (final item in (config['proxies'] as List? ?? const [])) {
          if (item is Map && item['name'] != null && item['server'] != null) {
            candidates.add((
              proxy: Map<String, Object?>.from(item),
              profile: profile.realLabel,
            ));
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _candidates = candidates;
      _loading = false;
    });
  }

  Future<void> _set(Map<String, Object?>? proxy) async {
    if (proxy == null) {
      await EntryServerStore.clear();
    } else {
      await EntryServerStore.save(proxy);
    }
    if (!mounted) return;
    setState(() => _entry = proxy);
    ref.read(setupActionProvider.notifier).applyProfileDebounce();
    final fa = _isFa(context);
    dialogs.showNotifier(
      proxy == null
          ? (fa ? 'سرور ورودی غیرفعال شد' : 'Entry server disabled')
          : (fa
                ? 'سرور ورودی: ${proxy['name']}'
                : 'Entry server: ${proxy['name']}'),
      level: MessageLevel.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fa = _isFa(context);
    final filter = _filter.toLowerCase();
    final shown = [
      for (final c in _candidates)
        if (filter.isEmpty ||
            '${c.proxy['name']} ${c.proxy['server']}'.toLowerCase().contains(
              filter,
            ))
          c,
    ];
    return CommonScaffold(
      title: fa ? 'سرور ورودی (Chain)' : 'Entry server (chain)',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
        children: [
          Text(
            fa
                ? 'با انتخاب یک سرور، همه‌ی سرورهای دیگر از طریق آن وصل '
                      'می‌شوند (اتصال و تست پینگ هر دو). خود آن سرور مستقیم '
                      'وصل می‌شود.'
                : 'Pick a server and every other server connects through it, '
                      'for both real connections and delay tests. The entry '
                      'server itself connects directly.',
          ),
          const SizedBox(height: 12),
          if (_entry != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.alt_route),
                title: Text('${_entry!['name']}'),
                subtitle: Text(
                  '${_entry!['type']} · ${_entry!['server']}:${_entry!['port']}',
                ),
                trailing: TextButton(
                  onPressed: () => _set(null),
                  child: Text(fa ? 'غیرفعال' : 'Disable'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              labelText: fa ? 'جستجو' : 'Search',
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                fa ? 'سروری پیدا نشد' : 'No servers found',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final c in shown)
              ListTile(
                title: Text('${c.proxy['name']}'),
                subtitle: Text(
                  '${c.proxy['type']} · ${c.proxy['server']}:${c.proxy['port']}'
                  ' · ${c.profile}',
                ),
                selected:
                    _entry?['name'] == c.proxy['name'] &&
                    _entry?['server'] == c.proxy['server'],
                onTap: () => _set(c.proxy),
              ),
        ],
      ),
    );
  }
}
