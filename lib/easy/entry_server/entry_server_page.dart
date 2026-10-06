import 'dart:async';

import 'package:easy_vpn/common/common.dart';
import 'package:easy_vpn/enum/enum.dart';
import 'package:easy_vpn/providers/providers.dart';
import 'package:easy_vpn/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../servers/all_servers_page.dart';
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
            ? 'همه‌ی ترافیک، تست پینگ و Psiphon از یک سرور مشخص رد شود'
            : 'Route all traffic, ping tests and Psiphon through one server',
      ),
      widget: const EntryServerView(),
    );
  }
}

class EntryServerView extends ConsumerStatefulWidget {
  const EntryServerView({super.key});

  @override
  ConsumerState<EntryServerView> createState() => _EntryServerViewState();
}

class _EntryServerViewState extends ConsumerState<EntryServerView> {
  Map<String, Object?>? _entry;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final entry = await EntryServerStore.load();
    if (!mounted) return;
    setState(() => _entry = entry);
  }

  /// Every server of every profile, grouped by profile and searchable.
  Future<void> _choose() async {
    final fa = _isFa(context);
    final proxy = await BaseNavigator.push<Map<String, Object?>>(
      context,
      EasyAllServersPage(
        title: fa ? 'انتخاب سرور ورودی' : 'Choose entry server',
        selectedName: _entry?['name'] as String?,
      ),
    );
    if (proxy == null || !mounted) return;
    final clean = Map<String, Object?>.from(proxy)..remove('dialer-proxy');
    await EntryServerStore.save(clean);
    ref.read(setupActionProvider.notifier).applyProfileDebounce();
    if (!mounted) return;
    setState(() => _entry = clean);
    dialogs.showNotifier(
      fa ? 'سرور ورودی: ${clean['name']}' : 'Entry server: ${clean['name']}',
      level: MessageLevel.success,
    );
  }

  Future<void> _disable() async {
    await EntryServerStore.clear();
    ref.read(setupActionProvider.notifier).applyProfileDebounce();
    if (!mounted) return;
    setState(() => _entry = null);
    dialogs.showNotifier(
      _isFa(context) ? 'سرور ورودی غیرفعال شد' : 'Entry server disabled',
      level: MessageLevel.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fa = _isFa(context);
    final entry = _entry;
    return CommonScaffold(
      title: fa ? 'سرور ورودی (Chain)' : 'Entry server (chain)',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
        children: [
          Text(
            fa
                ? 'یک سرور را از بین سرورهای همه‌ی پروفایل‌ها انتخاب کنید. '
                      'همه‌ی سرورهای دیگر، و Psiphon، از طریق آن وصل می‌شوند. '
                      'انتخاب شما با عوض کردن پروفایل هم می‌ماند. خود آن سرور '
                      'مستقیم وصل می‌شود.'
                : 'Pick a server from any profile. Every other server, and '
                      'Psiphon, then connects through it. Your choice stays '
                      'when you switch profile. The entry server itself '
                      'connects directly.',
          ),
          const SizedBox(height: 16),
          if (entry != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.alt_route),
                title: EmojiText(
                  '${entry['name']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${entry['type']} · ${entry['server']}:${entry['port']}',
                ),
                trailing: TextButton(
                  onPressed: _disable,
                  child: Text(fa ? 'غیرفعال' : 'Disable'),
                ),
              ),
            )
          else
            Text(fa ? 'سرور ورودی انتخاب نشده' : 'No entry server selected'),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _choose,
              icon: const Icon(Icons.dns),
              label: Text(
                entry == null
                    ? (fa ? 'انتخاب سرور' : 'Choose server')
                    : (fa ? 'تغییر سرور' : 'Change server'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
