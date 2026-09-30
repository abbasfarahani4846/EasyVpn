import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_provider.dart';
import '../../core/providers/env.dart';
import '../../core/util/formatters.dart';
import '../../l10n/strings.dart';
import '../../theme/brand.dart';

/// Checks, through the active connection, whether IP/region-sensitive
/// services (Gemini, ChatGPT, Claude, YouTube, Facebook...) load or block us.
class SiteCheckPage extends ConsumerStatefulWidget {
  const SiteCheckPage({super.key});
  @override
  ConsumerState<SiteCheckPage> createState() => _SiteCheckPageState();
}

class _SiteCheckPageState extends ConsumerState<SiteCheckPage> {
  List<Map<String, dynamic>>? _results;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (ref.read(coreControllerProvider).isConnected) _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(envProvider).core.siteCheck();
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final connected = ref.watch(
      coreControllerProvider.select((c) => c.isConnected),
    );
    final r = _results;
    final ok = r?.where((e) => e['status'] == 'ok').length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('sites.title')),
        actions: [
          IconButton(
            tooltip: s.t('sites.run'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _busy || !connected ? null : _run,
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: !connected
          ? Center(child: Text(s.t('sites.connect_first')))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  s.t('sites.desc'),
                  style: const TextStyle(color: Brand.textDim),
                ),
                if (r != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.t('sites.summary', {'ok': ok, 'n': r.length}),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Brand.bad),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final e in r ?? const <Map<String, dynamic>>[])
                  _SiteTile(e),
              ],
            ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile(this.e);
  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final st = e['status'] as String? ?? 'error';
    final (color, icon, label) = switch (st) {
      'ok' => (Brand.on, Icons.check_circle_rounded, s.t('sites.ok')),
      'blocked' => (Brand.busy, Icons.block_rounded, s.t('sites.blocked')),
      _ => (Brand.bad, Icons.error_outline_rounded, s.t('sites.error')),
    };
    final cc = (e['country'] as String?) ?? '';
    final detail = (e['detail'] as String?) ?? '';
    final ms = (e['ms'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: Brand.glass(radius: 18),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text('${e['name']}${cc.isNotEmpty ? '  ${flagEmoji(cc)}' : ''}'),
        subtitle: detail.isEmpty
            ? null
            : Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Brand.textDim),
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            if (ms > 0)
              Text(
                '$ms ms',
                style: const TextStyle(fontSize: 11, color: Brand.textDim),
              ),
          ],
        ),
      ),
    );
  }
}
