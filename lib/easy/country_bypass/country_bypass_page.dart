import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'country_bypass_config.dart';
import 'country_bypass_store.dart';
import 'country_catalog.dart';

bool _isFa(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

class EasyCountryBypassItem extends StatelessWidget {
  const EasyCountryBypassItem({super.key});

  @override
  Widget build(BuildContext context) {
    final fa = _isFa(context);
    return ListItem.open(
      leading: const Icon(Icons.public),
      title: Text(fa ? 'عبور مستقیم کشور' : 'Country bypass'),
      subtitle: Text(
        fa
            ? 'IP و دامنه‌های یک کشور بدون پروکسی و مستقیم وصل شوند'
            : 'Send a country’s IPs and domains direct, not via the proxy',
      ),
      widget: const CountryBypassView(),
    );
  }
}

class CountryBypassView extends ConsumerStatefulWidget {
  const CountryBypassView({super.key});

  @override
  ConsumerState<CountryBypassView> createState() => _CountryBypassViewState();
}

class _CountryBypassViewState extends ConsumerState<CountryBypassView> {
  CountrySelection? _selection;
  final Map<String, ExternalProvider?> _status = {};
  String _filter = '';
  bool _updating = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final selection = await CountryBypassStore.load();
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _loaded = true;
    });
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final selection = _selection;
    if (selection == null) return;
    final core = ref.read(coreHandlerProvider);
    final status = <String, ExternalProvider?>{};
    for (final name in CountryBypassConfig.providerNames(selection)) {
      try {
        status[name] = await core.getExternalProvider(name);
      } catch (_) {
        status[name] = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _status
        ..clear()
        ..addAll(status);
    });
  }

  Future<void> _save(CountrySelection? selection) async {
    if (selection == null) {
      await CountryBypassStore.clear();
    } else {
      await CountryBypassStore.save(selection);
    }
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _status.clear();
    });
    ref.read(setupActionProvider.notifier).applyProfileDebounce();
    Timer(const Duration(seconds: 6), () {
      if (mounted) unawaited(_refreshStatus());
    });
  }

  Future<void> _updateNow() async {
    final selection = _selection;
    if (selection == null || _updating) return;
    setState(() => _updating = true);
    final fa = _isFa(context);
    final core = ref.read(coreHandlerProvider);
    final errors = <String>[];
    for (final name in CountryBypassConfig.providerNames(selection)) {
      try {
        final message = await core.updateExternalProvider(providerName: name);
        if (message.isNotEmpty) errors.add(message);
      } catch (e) {
        errors.add(compactError(e));
      }
    }
    await _refreshStatus();
    if (!mounted) return;
    setState(() => _updating = false);
    dialogs.showNotifier(
      errors.isEmpty
          ? (fa ? 'لیست‌ها به‌روز شدند' : 'Lists updated')
          : errors.first,
      level: errors.isEmpty ? MessageLevel.success : MessageLevel.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fa = _isFa(context);
    final selection = _selection;
    final country = CountryCatalog.byCode(selection?.code);
    final filter = _filter.toLowerCase();
    final countries = [
      for (final c in CountryCatalog.all)
        if (filter.isEmpty ||
            c.nameEn.toLowerCase().contains(filter) ||
            c.nameFa.contains(filter) ||
            c.code.contains(filter))
          c,
    ];
    return CommonScaffold(
      title: fa ? 'عبور مستقیم کشور' : 'Country bypass',
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                context.contentTopPadding,
                16,
                16,
              ),
              children: [
                Text(
                  fa
                      ? 'کشور را انتخاب کنید؛ جدیدترین لیست IP و دامنه‌ها از '
                            'منابع معتبر گیت‌هاب دانلود و خودکار هر روز به‌روز '
                            'می‌شود، و ترافیک آن‌ها مستقیم می‌رود (از پروکسی '
                            'رد نمی‌شود).'
                      : 'Pick a country. The latest IP and domain lists are '
                            'downloaded from maintained GitHub sources and '
                            'refreshed daily; that traffic goes direct, not '
                            'through the proxy.',
                ),
                const SizedBox(height: 12),
                if (selection != null && country != null) ...[
                  _selectedCard(context, fa, selection, country),
                  const SizedBox(height: 12),
                ],
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    labelText: fa ? 'جستجوی کشور' : 'Search country',
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
                const SizedBox(height: 4),
                for (final c in countries)
                  ListTile(
                    leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(fa ? c.nameFa : c.nameEn),
                    subtitle: Text(
                      c.domain != null
                          ? (fa ? 'IP و دامنه' : 'IPs and domains')
                          : (fa ? 'فقط IP' : 'IPs only'),
                    ),
                    selected: selection?.code == c.code,
                    trailing: selection?.code == c.code
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => _save(
                      (selection ?? CountrySelection(code: c.code)).copyWith(
                        code: c.code,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _selectedCard(
    BuildContext context,
    bool fa,
    CountrySelection selection,
    CountrySource country,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              leading: Text(country.flag, style: const TextStyle(fontSize: 28)),
              title: Text(fa ? country.nameFa : country.nameEn),
              trailing: TextButton(
                onPressed: () => _save(null),
                child: Text(fa ? 'غیرفعال' : 'Disable'),
              ),
            ),
            CheckboxListTile(
              value: selection.ip,
              title: Text(fa ? 'IPهای کشور' : 'Country IP ranges'),
              onChanged: (v) => _save(selection.copyWith(ip: v ?? true)),
            ),
            CheckboxListTile(
              value: country.domain != null && selection.domain,
              title: Text(fa ? 'دامنه‌های کشور' : 'Country domains'),
              subtitle: country.domain == null
                  ? Text(fa ? 'برای این کشور لیست دامنه نیست' : 'No list yet')
                  : null,
              onChanged: country.domain == null
                  ? null
                  : (v) => _save(selection.copyWith(domain: v ?? true)),
            ),
            SwitchListTile(
              value: selection.mirror,
              title: Text(fa ? 'دانلود از آینه (jsDelivr)' : 'Use mirror (jsDelivr)'),
              subtitle: Text(
                fa
                    ? 'اگر raw.githubusercontent.com باز نمی‌شود روشن کنید'
                    : 'Turn on if raw.githubusercontent.com is blocked',
              ),
              onChanged: (v) => _save(selection.copyWith(mirror: v)),
            ),
            const Divider(),
            for (final name in CountryBypassConfig.providerNames(selection))
              ListTile(
                dense: true,
                title: Text(name),
                subtitle: Text(_statusText(fa, _status[name])),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: _updating ? null : _updateNow,
                  icon: _updating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(fa ? 'به‌روزرسانی الان' : 'Update now'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(bool fa, ExternalProvider? provider) {
    if (provider == null) {
      return fa
          ? 'هنوز بارگذاری نشده (پروفایل را اعمال یا متصل شوید)'
          : 'Not loaded yet (apply the profile or connect)';
    }
    final t = provider.updateAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    return fa
        ? '${provider.count} مورد · آخرین به‌روزرسانی $stamp'
        : '${provider.count} entries · updated $stamp';
  }
}
