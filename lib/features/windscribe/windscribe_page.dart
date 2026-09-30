import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/profiles_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/util/file_io.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';

/// Windscribe: one WireGuard config from the user's own account (website
/// Config Generator) becomes every location the account can use, via the
/// public server list. No login is sent anywhere.
class WindscribePage extends ConsumerStatefulWidget {
  const WindscribePage({super.key});
  @override
  ConsumerState<WindscribePage> createState() => _WindscribePageState();
}

class _WindscribePageState extends ConsumerState<WindscribePage> {
  final _c = TextEditingController();
  bool _pro = false;
  bool _busy = false;

  static final _generator = Uri.parse(
    'https://windscribe.com/myaccount#configgenerator',
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final s = context.s;
    if (_c.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final r = await ref
        .read(profilesProvider.notifier)
        .addWindscribe(_c.text, pro: _pro);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      ref
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(activeProfileId: 'windscribe'));
      showSnack(context, s.t('ws.done', {'n': r.total}));
      Navigator.of(context).maybePop();
    } else {
      showSnack(
        context,
        r.error == 'windscribe_need_wg' ? s.t('ws.need_wg') : r.error!,
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ws.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('ws.desc')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new),
                label: Text(s.t('ws.open_site')),
                onPressed: () =>
                    launchUrl(_generator, mode: LaunchMode.externalApplication),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_open_outlined),
                label: Text(s.t('ws.pick_file')),
                onPressed: () async {
                  final t = await pickTextFile(extensions: ['conf', 'txt']);
                  if (t != null) setState(() => _c.text = t);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            minLines: 6,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              labelText: s.t('ws.paste'),
              hintText: '[Interface]\nPrivateKey = …\nAddress = …\n\n[Peer]\n…',
              border: const OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('ws.pro')),
            value: _pro,
            onChanged: (v) => setState(() => _pro = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.public),
            label: Text(s.t('ws.import')),
            onPressed: _busy ? null : _import,
          ),
          const SizedBox(height: 16),
          Text(s.t('ws.note'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
