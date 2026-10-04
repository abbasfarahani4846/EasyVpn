import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../home/selected_server.dart';
import 'entry_server_store.dart';

/// One line: You -> entry server -> selected server -> Internet, shown while
/// an entry server (chain proxy) is set.
class EasyRouteCard extends ConsumerWidget {
  /// As a dashboard widget it stays visible with a hint when no entry is set.
  final bool alwaysShow;

  const EasyRouteCard({super.key, this.alwaysShow = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final running = ref.watch(isStartProvider);
    final leaf = easySelectedServer(ref);
    final scheme = Theme.of(context).colorScheme;
    final accent = running ? scheme.primary : scheme.outline;
    return ValueListenableBuilder<int>(
      valueListenable: EntryServerStore.version,
      builder: (context, _, _) => FutureBuilder<Map<String, Object?>?>(
        future: EntryServerStore.load(),
        builder: (context, snapshot) {
          final entry = snapshot.data;
          if (entry == null) {
            if (!alwaysShow) return const SizedBox.shrink();
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(Icons.alt_route, size: 16, color: scheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fa
                            ? 'مسیر زنجیره: سرور ورودی انتخاب نشده'
                            : 'Chain route: no entry server',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final entryName = '${entry['name']}';
          final isEntryItself =
              leaf == entryName || leaf == '$entryName [entry]';
          final hops = <String>[
            fa ? 'شما' : 'You',
            entryName,
            if (leaf != null && !isEntryItself) leaf,
            fa ? 'اینترنت' : 'Internet',
          ];
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.alt_route, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < hops.length; i++) ...[
                            if (i > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: accent,
                                ),
                              ),
                            _Hop(label: hops[i], active: running),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Hop extends StatelessWidget {
  final String label;
  final bool active;

  const _Hop({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: EmojiText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}
