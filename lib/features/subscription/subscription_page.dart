import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/env.dart';
import '../../core/providers/profiles_provider.dart';
import '../../core/util/file_io.dart';
import '../../core/util/formatters.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';
import '../scan/scan_page.dart';

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final profiles = ref.watch(profilesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('subs.title')),
        actions: [
          IconButton(
            tooltip: s.t('subs.refresh_all'),
            icon: const Icon(Icons.sync),
            onPressed: () async {
              for (final p in (profiles.value ?? const <Profile>[]).where(
                (p) => p.isRemote,
              )) {
                await ref.read(profilesProvider.notifier).refresh(p.id);
              }
            },
          ),
        ],
      ),
      body: profiles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.cloud_download_outlined,
                title: s.t('subs.empty'),
                hint: s.t('proxies.empty.hint'),
                action: FilledButton.icon(
                  onPressed: () => showAddSheet(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(s.t('subs.add')),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ProfileCard(profile: list[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showAddSheet(context, ref),
        icon: const Icon(Icons.add),
        label: Text(s.t('subs.add')),
      ),
    );
  }
}

/// Shows the import options sheet; also used by deep links and onboarding.
///
/// The sheet reads providers through its OWN ref: the caller (e.g. the
/// onboarding page) may be disposed while the sheet is open, and a dead
/// WidgetRef made the first import silently fail.
Future<void> showAddSheet(
  BuildContext context,
  WidgetRef _, {
  String? prefillUrl,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _AddSheet(prefillUrl: prefillUrl),
    ),
  );
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({this.prefillUrl});
  final String? prefillUrl;
  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  late final _url = TextEditingController(text: widget.prefillUrl ?? '');
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _report(ImportResult r) async {
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context);
      showSnack(
        context,
        '${context.s.t('subs.imported', {'n': r.total})} · ${context.s.t('subs.import_stats', {'added': r.added, 'removed': r.removed})}',
      );
    } else {
      setState(() {
        _busy = false;
        _error = r.error;
      });
    }
  }

  Future<void> _run(Future<ImportResult> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    ImportResult r;
    try {
      r = await f();
    } catch (e) {
      r = ImportResult(error: '$e'); // never leave the sheet spinning
    }
    await _report(r);
  }

  Future<void> _submitUrl() async {
    final v = _url.text.trim();
    if (v.isEmpty) return;
    final notifier = ref.read(profilesProvider.notifier);
    if (v.startsWith('http://') || v.startsWith('https://')) {
      await _run(() => notifier.addSubscription(v, name: _name.text.trim()));
    } else {
      await _run(() => notifier.importText(v, name: _name.text.trim()));
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) return;
    if (t.startsWith('http://') || t.startsWith('https://')) {
      _url.text = t;
      return;
    }
    await _run(
      () => ref
          .read(profilesProvider.notifier)
          .importText(t, name: _name.text.trim()),
    );
  }

  Future<void> _file() async {
    final c = await pickTextFile();
    if (c == null || c.trim().isEmpty) return;
    await _run(
      () => ref
          .read(profilesProvider.notifier)
          .importText(c, name: _name.text.trim()),
    );
  }

  Future<void> _qr() async {
    final v = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (v == null || !mounted) return;
    final notifier = ref.read(profilesProvider.notifier);
    if (v.startsWith('http://') || v.startsWith('https://')) {
      await _run(() => notifier.addSubscription(v, name: _name.text.trim()));
    } else {
      await _run(() => notifier.importText(v, name: _name.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.t('subs.add'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: s.t('subs.url'),
                hintText: s.t('subs.paste_hint'),
                prefixIcon: const Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: s.t('subs.name'),
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _submitUrl,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download),
              label: Text(s.t('common.import')),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.content_paste),
                  label: Text(s.t('subs.from_clipboard')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _file,
                  icon: const Icon(Icons.folder_open),
                  label: Text(s.t('subs.from_file')),
                ),
                if (scanSupported)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _qr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(s.t('subs.from_qr')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final cs = Theme.of(context).colorScheme;
    final p = profile;
    final frac = p.usedFraction;
    final expired =
        p.expire > 0 &&
        DateTime.fromMillisecondsSinceEpoch(
          p.expire * 1000,
        ).isBefore(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  p.isRemote
                      ? Icons.cloud_outlined
                      : Icons.description_outlined,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (p.isRemote)
                  IconButton(
                    tooltip: s.t('subs.refresh'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      final r = await ref
                          .read(profilesProvider.notifier)
                          .refresh(p.id);
                      if (context.mounted)
                        showSnack(
                          context,
                          r.ok
                              ? s.t('subs.imported', {'n': r.total})
                              : (r.error ?? ''),
                          error: !r.ok,
                        );
                    },
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) => _action(context, ref, v),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(s.t('common.rename')),
                    ),
                    if (p.isRemote)
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(s.t('common.edit')),
                      ),
                    PopupMenuItem(
                      value: 'export',
                      child: Text(s.t('common.export')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(s.t('common.delete')),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _meta(
                  context,
                  Icons.dns_outlined,
                  s.t('subs.nodes', {'n': p.nodeCount}),
                ),
                _meta(
                  context,
                  Icons.schedule,
                  s.t('subs.updated', {
                    't': p.updatedAt == null
                        ? s.t('subs.never')
                        : _ago(p.updatedAt!),
                  }),
                ),
                if (p.expire > 0)
                  _meta(
                    context,
                    Icons.event,
                    expired
                        ? s.t('subs.expired')
                        : s.t('subs.expires', {
                            'd': _date(
                              DateTime.fromMillisecondsSinceEpoch(
                                p.expire * 1000,
                              ),
                            ),
                          }),
                    error: expired,
                  ),
              ],
            ),
            if (frac != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 4),
              Text(
                s.t('subs.usage', {
                  'used': fmtBytes(p.upload + p.download),
                  'total': fmtBytes(p.total),
                }),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
            if (p.lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${s.t('subs.failed')}: ${p.lastError}',
                style: TextStyle(color: cs.error, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (p.isRemote) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.t('subs.auto_refresh')} · ${s.t('subs.interval', {'h': p.intervalHours})}',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Switch(
                    value: p.autoRefresh,
                    onChanged: (v) => ref
                        .read(profilesProvider.notifier)
                        .saveProfile(p.copyWith(autoRefresh: v)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(
    BuildContext context,
    IconData i,
    String t, {
    bool error = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final c = error ? cs.error : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(i, size: 16, color: c),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 12, color: c)),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes} m';
    if (d.inDays < 1) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _action(BuildContext context, WidgetRef ref, String v) async {
    final s = context.s;
    final n = ref.read(profilesProvider.notifier);
    switch (v) {
      case 'rename':
        final name = await promptText(
          context,
          title: s.t('common.rename'),
          initial: profile.name,
        );
        if (name != null && name.isNotEmpty)
          await n.saveProfile(profile.copyWith(name: name));
      case 'edit':
        await _edit(context, ref);
      case 'delete':
        if (await confirm(
          context,
          s.t('subs.delete_confirm', {'name': profile.name}),
          okLabel: s.t('common.delete'),
        )) {
          await n.delete(profile.id);
        }
      case 'export':
        await exportNodesDialog(
          context,
          ref,
          profileId: profile.id,
          name: profile.name,
        );
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final url = TextEditingController(text: profile.url);
    final ua = TextEditingController(text: profile.userAgent);
    double hours = profile.intervalHours.toDouble();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(s.t('common.edit')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                decoration: InputDecoration(labelText: s.t('subs.url')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ua,
                decoration: InputDecoration(labelText: s.t('subs.user_agent')),
              ),
              const SizedBox(height: 10),
              Text(s.t('subs.interval', {'h': hours.round()})),
              Slider(
                value: hours,
                min: 1,
                max: 72,
                divisions: 71,
                onChanged: (v) => set(() => hours = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () {
                ref
                    .read(profilesProvider.notifier)
                    .saveProfile(
                      profile.copyWith(
                        url: url.text.trim(),
                        userAgent: ua.text.trim(),
                        intervalHours: hours.round(),
                      ),
                    );
                Navigator.pop(ctx);
              },
              child: Text(s.t('common.save')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Export a profile's (or all) nodes as share links / Clash YAML / sing-box JSON.
Future<void> exportNodesDialog(
  BuildContext context,
  WidgetRef ref, {
  String? profileId,
  required String name,
}) async {
  final s = context.s;
  final fmt = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(s.t('data.export_nodes')),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'uri'),
          child: Text(s.t('data.format.uri')),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'clash'),
          child: Text(s.t('data.format.clash')),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'singbox'),
          child: Text(s.t('data.format.singbox')),
        ),
      ],
    ),
  );
  if (fmt == null || !context.mounted) return;
  final env = ref.read(envProvider);
  try {
    final ids = await env.repo.allIds(profileId: profileId);
    final nodes = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 500) {
      nodes.addAll(
        await env.repo.rawNodes(
          ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500),
        ),
      );
    }
    final payload = await env.core.export(fmt, nodes);
    final ext = switch (fmt) {
      'clash' => 'yaml',
      'singbox' => 'json',
      _ => 'txt',
    };
    final safe = name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final where = await saveText(fileName: '$safe.$ext', content: payload);
    if (context.mounted && where != null)
      showSnack(context, s.t('common.done'));
  } catch (e) {
    if (context.mounted) showSnack(context, '$e', error: true);
  }
}
