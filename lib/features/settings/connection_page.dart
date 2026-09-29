import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../core/providers/env.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/util/platform_service.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';
import '../dashboard/dashboard_page.dart';

class ConnectionPage extends ConsumerWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final st = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier);
    final env = ref.read(envProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings.connection'))),
      body: ListView(
        children: [
          SectionHeader(s.t('conn.mode')),
          RadioGroup<ConnMode>(
            groupValue: st.mode,
            onChanged: (v) => v == null
                ? null
                : ref.read(coreControllerProvider.notifier).setMode(v),
            child: Column(
              children: [
                for (final m in availableModes())
                  RadioListTile<ConnMode>(
                    value: m,
                    title: Text(s.t('mode.${m.wire}')),
                    subtitle: Text(s.t('mode.${m.wire}.desc')),
                  ),
              ],
            ),
          ),
          SectionHeader(s.t('settings.core')),
          ListTile(
            title: Text(s.t('conn.port')),
            trailing: SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: '${st.localPort}',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  final p = int.tryParse(v);
                  if (p != null && p >= 1024 && p <= 65535)
                    set.update((x) => x.copyWith(localPort: p));
                },
              ),
            ),
          ),
          SwitchListTile(
            title: Text(s.t('conn.allow_lan')),
            value: st.allowLan,
            onChanged: (v) => set.update((x) => x.copyWith(allowLan: v)),
          ),
          SwitchListTile(
            title: Text(s.t('conn.local_auth')),
            subtitle: Text(
              '${s.t('conn.local_auth.desc')} · ${st.localAuth ? env.localPass : ''}',
            ),
            value: st.localAuth,
            onChanged: (v) => set.update((x) => x.copyWith(localAuth: v)),
          ),
          ListTile(
            title: Text(s.t('conn.test_url')),
            subtitle: Text(st.testUrl),
            onTap: () async {
              final t = await promptText(
                context,
                title: s.t('conn.test_url'),
                initial: st.testUrl,
              );
              if (t != null && t.startsWith('http'))
                set.update((x) => x.copyWith(testUrl: t));
            },
          ),
          ListTile(
            title: Text(s.t('conn.log_level')),
            trailing: DropdownButton<String>(
              value: st.logLevel,
              items: [
                for (final l in ['debug', 'info', 'warn', 'error'])
                  DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) => set.update((x) => x.copyWith(logLevel: v)),
            ),
          ),
          SectionHeader(s.t('conn.tun')),
          ListTile(
            title: Text(s.t('conn.mtu')),
            trailing: SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: '${st.tunMtu}',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  final p = int.tryParse(v);
                  if (p != null && p >= 1280 && p <= 65535)
                    set.update((x) => x.copyWith(tunMtu: p));
                },
              ),
            ),
          ),
          SwitchListTile(
            title: Text(s.t('conn.strict_route')),
            value: st.tunStrictRoute,
            onChanged: (v) => set.update((x) => x.copyWith(tunStrictRoute: v)),
          ),
          SwitchListTile(
            title: Text(s.t('conn.ipv6')),
            value: st.tunIpv6,
            onChanged: (v) => set.update((x) => x.copyWith(tunIpv6: v)),
          ),
          if (PlatformService.isAndroid) ...[
            SectionHeader(s.t('conn.per_app')),
            RadioGroup<String>(
              groupValue: st.perAppMode,
              onChanged: (v) => v == null
                  ? null
                  : set.update((x) => x.copyWith(perAppMode: v)),
              child: Column(
                children: [
                  for (final m in ['off', 'include', 'exclude'])
                    RadioListTile<String>(
                      value: m,
                      title: Text(s.t('conn.per_app.$m')),
                    ),
                ],
              ),
            ),
            if (st.perAppMode != 'off')
              ListTile(
                leading: const Icon(Icons.apps),
                title: Text(s.t('conn.per_app.pick')),
                subtitle: Text('${st.perAppPackages.length}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const _AppPicker()),
                ),
              ),
          ],
          SectionHeader(s.t('settings.system')),
          SwitchListTile(
            title: Text(s.t('conn.auto_connect')),
            value: st.autoConnect,
            onChanged: (v) => set.update((x) => x.copyWith(autoConnect: v)),
          ),
          SwitchListTile(
            title: Text(s.t('conn.auto_failover')),
            value: st.autoFailover,
            onChanged: (v) => set.update((x) => x.copyWith(autoFailover: v)),
          ),
          SwitchListTile(
            title: Text(s.t('conn.auto_start')),
            value: st.autoLaunch,
            onChanged: (v) {
              set.update((x) => x.copyWith(autoLaunch: v));
              PlatformService.setAutoStart(v);
            },
          ),
          if (PlatformService.isDesktop) ...[
            SwitchListTile(
              title: Text(s.t('conn.close_to_tray')),
              value: st.closeToTray,
              onChanged: (v) => set.update((x) => x.copyWith(closeToTray: v)),
            ),
            SwitchListTile(
              title: Text(s.t('conn.start_minimized')),
              value: st.startMinimized,
              onChanged: (v) =>
                  set.update((x) => x.copyWith(startMinimized: v)),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AppPicker extends ConsumerStatefulWidget {
  const _AppPicker();
  @override
  ConsumerState<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends ConsumerState<_AppPicker> {
  late final Future<List<InstalledApp>> _apps = PlatformService.installedApps();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final picked = ref.watch(settingsProvider.select((x) => x.perAppPackages));
    return Scaffold(
      appBar: AppBar(title: Text(s.t('conn.per_app.pick'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.t('common.search'),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InstalledApp>>(
              future: _apps,
              builder: (context, snap) {
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final apps = snap.data!
                    .where(
                      (a) =>
                          _q.isEmpty ||
                          a.label.toLowerCase().contains(_q) ||
                          a.package.contains(_q),
                    )
                    .toList();
                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (_, i) {
                    final a = apps[i];
                    final on = picked.contains(a.package);
                    return CheckboxListTile(
                      value: on,
                      title: Text(a.label),
                      subtitle: Text(
                        a.package,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onChanged: (v) => ref
                          .read(settingsProvider.notifier)
                          .update(
                            (x) => x.copyWith(
                              perAppPackages: v == true
                                  ? [...x.perAppPackages, a.package]
                                  : x.perAppPackages
                                        .where((p) => p != a.package)
                                        .toList(),
                            ),
                          ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
