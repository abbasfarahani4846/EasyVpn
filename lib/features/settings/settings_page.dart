import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_service.dart';
import '../chain/chain_page.dart';
import '../windscribe/windscribe_page.dart';
import 'updates_page.dart';

import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../core/providers/env.dart';
import '../../core/providers/settings_provider.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';
import 'about_page.dart';
import 'appearance_page.dart';
import 'backup_page.dart';
import 'connection_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final core = ref.watch(coreControllerProvider);
    final st = ref.watch(settingsProvider);

    Widget tile(
      IconData i,
      String title,
      String? sub,
      Widget Function() page,
    ) => ListTile(
      leading: Icon(i),
      title: Text(title),
      subtitle: sub == null ? null : Text(sub),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page())),
    );

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings.title'))),
      body: ListView(
        children: [
          if (core.status == CoreStatus.unavailable)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(s.t('core.unavailable')),
                  subtitle: Text(core.detail),
                ),
              ),
            ),
          SectionHeader(s.t('settings.appearance')),
          SwitchListTile(
            secondary: const Icon(Icons.radio_button_checked),
            title: Text(s.t('home.simple')),
            value: st.uiMode != 'advanced',
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((x) => x.copyWith(uiMode: v ? 'simple' : 'advanced')),
          ),
          tile(
            Icons.palette_outlined,
            s.t('settings.appearance'),
            '${s.t('appearance.theme.${st.appearance.themeMode}')} · ${st.appearance.locale == 'system' ? s.t('appearance.language.system') : st.appearance.locale}',
            () => const AppearancePage(),
          ),
          SectionHeader(s.t('settings.connection')),
          tile(
            Icons.settings_ethernet,
            s.t('settings.connection'),
            '${s.t('mode.${st.mode.wire}')} · :${st.localPort}',
            () => const ConnectionPage(),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(s.t('settings.logs')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/logs'),
          ),
          tile(
            Icons.link_rounded,
            s.t('menu.chain'),
            null,
            () => const ChainPage(),
          ),
          tile(
            Icons.air_rounded,
            s.t('menu.windscribe'),
            null,
            () => const WindscribePage(),
          ),
          SectionHeader(s.t('settings.data')),
          tile(
            Icons.backup_outlined,
            s.t('settings.data'),
            null,
            () => const BackupPage(),
          ),
          SectionHeader(s.t('settings.about')),
          tile(
            Icons.system_update_rounded,
            s.t('upd.title'),
            buildLabel,
            () => const UpdatesPage(),
          ),
          tile(
            Icons.info_outline,
            s.t('settings.about'),
            null,
            () => const AboutPage(),
          ),
          if (!ref.read(envProvider).keystoreBacked)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                s.t('data.keystore.warn'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
