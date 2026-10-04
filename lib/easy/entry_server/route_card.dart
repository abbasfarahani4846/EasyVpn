import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../home/selected_server.dart';
import 'entry_server_store.dart';

/// Shows "You -> entry server -> selected server -> Internet" while an entry
/// server (chain proxy) is set.
class EasyRouteCard extends ConsumerWidget {
  const EasyRouteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final running = ref.watch(isStartProvider);
    final leaf = easySelectedServer(ref);
    return ValueListenableBuilder<int>(
      valueListenable: EntryServerStore.version,
      builder: (context, _, _) => FutureBuilder<Map<String, Object?>?>(
        future: EntryServerStore.load(),
        builder: (context, snapshot) {
          final entry = snapshot.data;
          if (entry == null) return const SizedBox.shrink();
          final entryName = '${entry['name']}';
          final isEntryItself =
              leaf == entryName || leaf == '$entryName [entry]';
          final hops = <_Hop>[
            _Hop(label: fa ? 'شما' : 'You', icon: Icons.computer),
            _Hop(
              label: entryName,
              icon: Icons.login,
              caption: fa ? 'ورودی' : 'Entry',
            ),
            if (leaf != null && !isEntryItself)
              _Hop(
                label: leaf,
                icon: Icons.dns,
                caption: fa ? 'سرور' : 'Server',
              ),
            _Hop(label: fa ? 'اینترنت' : 'Internet', icon: Icons.public),
          ];
          final scheme = Theme.of(context).colorScheme;
          final accent = running ? scheme.primary : scheme.outline;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.alt_route, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          running
                              ? (fa
                                    ? 'مسیر زنجیره (فعال)'
                                    : 'Chain route (active)')
                              : (fa
                                    ? 'مسیر زنجیره (متصل نیست)'
                                    : 'Chain route (not connected)'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (var i = 0; i < hops.length; i++) ...[
                          if (i > 0)
                            Icon(Icons.arrow_forward, size: 16, color: accent),
                          _HopChip(hop: hops[i], active: running),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Hop {
  final String label;
  final IconData icon;
  final String? caption;

  const _Hop({required this.label, required this.icon, this.caption});
}

class _HopChip extends StatelessWidget {
  final _Hop hop;
  final bool active;

  const _HopChip({required this.hop, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hop.icon, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hop.caption != null)
                      Text(
                        hop.caption!,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    EmojiText(
                      hop.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
