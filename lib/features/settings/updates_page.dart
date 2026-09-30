import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/update/update_service.dart';
import '../../l10n/strings.dart';

/// Updates from GitHub Releases: channel, auto-check, check / download /
/// install. Every download is verified against the release's SHA256SUMS.
class UpdatesPage extends ConsumerWidget {
  const UpdatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final st = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier);
    final u = ref.watch(updateProvider);
    final ctl = ref.read(updateProvider.notifier);

    Widget action() {
      switch (u.phase) {
        case UpdatePhase.checking:
          return ListTile(
            leading: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text(s.t('upd.checking')),
          );
        case UpdatePhase.available:
          return ListTile(
            leading: const Icon(Icons.new_releases_outlined),
            title: Text(s.t('upd.available', {'v': u.latest})),
            subtitle: Text(u.asset?['name'] as String? ?? ''),
            trailing: FilledButton(
              onPressed: ctl.download,
              child: Text(s.t('upd.download')),
            ),
          );
        case UpdatePhase.downloading:
          return ListTile(
            title: Text(
              s.t('upd.downloading', {'p': (u.progress * 100).round()}),
            ),
            subtitle: LinearProgressIndicator(
              value: u.progress == 0 ? null : u.progress,
            ),
          );
        case UpdatePhase.ready:
          return ListTile(
            leading: const Icon(Icons.verified_outlined, color: Colors.green),
            title: Text(s.t('upd.available', {'v': u.latest})),
            subtitle: Text(s.t('upd.verified')),
            trailing: FilledButton(
              onPressed: ctl.install,
              child: Text(s.t('upd.install')),
            ),
          );
        case UpdatePhase.error:
          return ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(u.error, maxLines: 4),
            trailing: TextButton(
              onPressed: ctl.check,
              child: Text(s.t('upd.check')),
            ),
          );
        case UpdatePhase.idle:
          return ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text(u.latest.isEmpty ? s.t('upd.check') : s.t('upd.none')),
            trailing: FilledButton.tonal(
              onPressed: ctl.check,
              child: Text(s.t('upd.check')),
            ),
          );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.t('upd.title'))),
      body: ListView(
        children: [
          ListTile(title: Text(s.t('upd.current')), subtitle: Text(buildLabel)),
          if (buildLabel == 'dev')
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(s.t('upd.dev')),
            ),
          ListTile(
            title: Text(s.t('upd.channel')),
            trailing: DropdownButton<String>(
              value: st.updateChannel,
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(s.t('upd.channel.auto', {'c': buildChannel})),
                ),
                DropdownMenuItem(
                  value: 'stable',
                  child: Text(s.t('upd.channel.stable')),
                ),
                DropdownMenuItem(
                  value: 'nightly',
                  child: Text(s.t('upd.channel.nightly')),
                ),
              ],
              onChanged: (v) =>
                  set.update((x) => x.copyWith(updateChannel: v ?? '')),
            ),
          ),
          SwitchListTile(
            title: Text(s.t('upd.auto')),
            value: st.autoUpdateCheck,
            onChanged: (v) => set.update((x) => x.copyWith(autoUpdateCheck: v)),
          ),
          const Divider(),
          action(),
          if (u.pageUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: Text(s.t('upd.notes')),
              onTap: () => launchUrl(
                Uri.parse(u.pageUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }
}
