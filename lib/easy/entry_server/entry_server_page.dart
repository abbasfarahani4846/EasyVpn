import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'entry_server_store.dart';
import 'proxy_picker.dart';

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

  @override
  void dispose() {
    EasyProxyPicker.disarm();
    super.dispose();
  }

  Future<void> _load() async {
    final entry = await EntryServerStore.load();
    if (!mounted) return;
    setState(() => _entry = entry);
  }

  /// Opens the real Proxies page; the next proxy tapped there becomes the entry.
  Future<void> _choose() async {
    final fa = _isFa(context);
    EasyProxyPicker.arm((name) => unawaited(_picked(name, fa)));
    try {
      await BaseNavigator.push<void>(context, const ProxiesView());
    } finally {
      EasyProxyPicker.disarm();
    }
  }

  Future<void> _picked(String name, bool fa) async {
    final proxy = await _resolve(name);
    if (proxy == null) {
      dialogs.showNotifier(
        fa
            ? 'این مورد گروه است یا سرور مستقل نیست؛ یک سرور را انتخاب کنید'
            : 'That is a group or a provider server; pick a plain server',
        level: MessageLevel.warning,
      );
      return;
    }
    EasyProxyPicker.disarm();
    await EntryServerStore.save(proxy);
    ref.read(setupActionProvider.notifier).applyProfileDebounce();
    globalState.navigatorKey.currentState?.pop();
    if (!mounted) return;
    setState(() => _entry = proxy);
    dialogs.showNotifier(
      fa ? 'سرور ورودی: ${proxy['name']}' : 'Entry server: ${proxy['name']}',
      level: MessageLevel.success,
    );
  }

  Future<Map<String, Object?>?> _resolve(String name) async {
    final core = ref.read(coreHandlerProvider);
    final configs = <Map<String, dynamic>>[];
    try {
      configs.add(await core.getAppliedConfig());
    } catch (_) {}
    for (final profile in ref.read(profilesProvider)) {
      try {
        configs.add(await core.getConfig(profile.id));
      } catch (_) {}
    }
    for (final config in configs) {
      for (final item in (config['proxies'] as List? ?? const [])) {
        if (item is Map && item['name'] == name && item['server'] != null) {
          return Map<String, Object?>.from(item)..remove('dialer-proxy');
        }
      }
    }
    return null;
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
                ? 'یک سرور را از صفحه‌ی پروکسی‌ها انتخاب کنید. همه‌ی سرورهای '
                      'دیگر از طریق آن وصل می‌شوند (اتصال و تست پینگ هر دو). '
                      'خود آن سرور مستقیم وصل می‌شود.'
                : 'Choose a server from the Proxies page. Every other server '
                      'then connects through it, for both real connections and '
                      'delay tests. The entry server itself connects directly.',
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
            Text(
              fa ? 'سرور ورودی انتخاب نشده' : 'No entry server selected',
              style: context.textTheme.bodyMedium,
            ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _choose,
              icon: const Icon(Icons.dns),
              label: Text(
                entry == null
                    ? (fa ? 'انتخاب از پروکسی‌ها' : 'Choose from Proxies')
                    : (fa ? 'تغییر سرور' : 'Change server'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
