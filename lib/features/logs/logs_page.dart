import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});
  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  String _level = 'all';
  String _q = '';

  static const _order = [
    'trace',
    'debug',
    'info',
    'warn',
    'error',
    'fatal',
    'panic',
  ];

  bool _pass(LogLine l) {
    if (_level != 'all' &&
        _order.indexOf(l.level.toLowerCase()) < _order.indexOf(_level))
      return false;
    return _q.isEmpty || l.message.toLowerCase().contains(_q.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final all = ref.watch(logProvider);
    final lines = all.where(_pass).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('logs.title')),
        actions: [
          PopupMenuButton<String>(
            tooltip: s.t('logs.filter'),
            icon: const Icon(Icons.filter_alt_outlined),
            onSelected: (v) => setState(() => _level = v),
            itemBuilder: (_) => [
              for (final l in ['all', 'debug', 'info', 'warn', 'error'])
                CheckedPopupMenuItem(
                  value: l,
                  checked: _level == l,
                  child: Text(l),
                ),
            ],
          ),
          IconButton(
            tooltip: s.t('logs.copy'),
            icon: const Icon(Icons.copy_all),
            onPressed: () => copyText(
              context,
              lines.reversed
                  .map(
                    (l) =>
                        '${l.time.toIso8601String()} [${l.level}] ${l.message}',
                  )
                  .join('\n'),
            ),
          ),
          IconButton(
            tooltip: s.t('logs.clear'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: ref.read(logProvider.notifier).clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.t('common.search'),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: lines.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: s.t('logs.empty'),
                  )
                : ListView.builder(
                    itemCount: lines.length,
                    itemExtent: 28,
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      final cs = Theme.of(context).colorScheme;
                      final c = switch (l.level.toLowerCase()) {
                        'error' || 'fatal' || 'panic' => cs.error,
                        'warn' || 'warning' => Colors.amber,
                        'debug' || 'trace' => cs.outline,
                        _ => cs.onSurface,
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${_t(l.time)} ${l.message}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: c,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _t(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
