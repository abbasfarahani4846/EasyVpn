import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/env.dart';
import '../../core/providers/node_list_provider.dart';
import '../../core/providers/profiles_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/util/backup_service.dart';
import '../../core/util/file_io.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';
import '../subscription/subscription_page.dart';

class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});

  BackupService _svc(WidgetRef ref) {
    final env = ref.read(envProvider);
    return BackupService(env.db, env.repo, env.core);
  }

  Future<String?> _askPass(
    BuildContext context, {
    bool confirmPass = false,
  }) async {
    final s = context.s;
    final a = TextEditingController();
    final b = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('data.passphrase')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: s.t('data.passphrase')),
            ),
            if (confirmPass) ...[
              const SizedBox(height: 10),
              TextField(
                controller: b,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: s.t('data.passphrase.confirm'),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (a.text.length < 4 || (confirmPass && a.text != b.text))
                return;
              Navigator.pop(ctx, a.text);
            },
            child: Text(s.t('common.ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings.data'))),
      body: ListView(
        children: [
          SectionHeader(s.t('settings.data')),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(s.t('data.backup')),
            subtitle: const Text('AES-256-GCM · Argon2id'),
            onTap: () async {
              final pass = await _askPass(context, confirmPass: true);
              if (pass == null || !context.mounted) return;
              try {
                final blob = await _svc(ref)
                    .create(ref.read(settingsProvider), pass);
                final stamp = DateTime.now().toIso8601String().substring(0, 10);
                await saveText(fileName: 'easyvpn-$stamp.ezbak', content: blob);
                if (context.mounted)
                  showSnack(context, s.t('data.backup.done'));
              } catch (e) {
                if (context.mounted) showSnack(context, '$e', error: true);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(s.t('data.restore')),
            onTap: () => _restore(context, ref),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: Text(s.t('data.export_settings')),
            onTap: () async {
              final json = _svc(ref).exportSettings(ref.read(settingsProvider));
              await saveText(fileName: 'easyvpn-settings.json', content: json);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(s.t('data.import_settings')),
            onTap: () async {
              final c = await pickTextFile(extensions: ['json']);
              if (c == null) return;
              try {
                await ref
                    .read(settingsProvider.notifier)
                    .replace(_svc(ref).importSettings(c));
                if (context.mounted) showSnack(context, s.t('common.done'));
              } catch (e) {
                if (context.mounted) showSnack(context, '$e', error: true);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(s.t('data.export_nodes')),
            onTap: () => exportNodesDialog(context, ref, name: 'easyvpn-all'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.t('data.restore')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'file'),
            child: Text(s.t('subs.from_file')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'clip'),
            child: Text(s.t('subs.from_clipboard')),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final blob = choice == 'file' ? await pickTextFile() : clip?.text;
    if (blob == null || blob.trim().isEmpty || !context.mounted) return;
    final pass = await _askPass(context);
    if (pass == null || !context.mounted) return;
    try {
      final r = await _svc(ref).restore(blob, pass);
      await ref.read(settingsProvider.notifier).replace(r.settings);
      await ref.read(profilesProvider.notifier).reload();
      await ref.read(nodeListProvider.notifier).reload();
      if (context.mounted)
        showSnack(
          context,
          s.t('data.restore.done', {'p': r.profiles, 'n': r.nodes}),
        );
    } catch (e) {
      final bad = '$e'.contains('wrong passphrase');
      if (context.mounted)
        showSnack(context, bad ? s.t('data.restore.bad') : '$e', error: true);
    }
  }
}
