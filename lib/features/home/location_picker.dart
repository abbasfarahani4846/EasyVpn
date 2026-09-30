import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../core/providers/env.dart';
import '../../core/providers/node_list_provider.dart';
import '../../core/providers/ping_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../l10n/strings.dart';
import '../../theme/brand.dart';
import 'home_menu.dart';

/// Full-height location sheet: search, favorites, flags and signal bars.
/// Pages through the repository (keyset) so 10k nodes stay smooth.
Future<void> showLocationPicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Brand.night2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.radius)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _Picker(scroll: scroll),
    ),
  );
}

class _Picker extends ConsumerStatefulWidget {
  const _Picker({required this.scroll});
  final ScrollController scroll;
  @override
  ConsumerState<_Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_Picker> {
  final _rows = <NodeRow>[];
  List<Object?>? _cursor;
  bool _loading = false;
  bool _favOnly = false;
  String _q = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (widget.scroll.position.extentAfter < 600) _more();
  }

  Future<void> _reload() async {
    _rows.clear();
    _cursor = null;
    await _more(first: true);
  }

  Future<void> _more({bool first = false}) async {
    if (_loading || (!first && _cursor == null)) return;
    _loading = true;
    final page = await ref
        .read(envProvider)
        .repo
        .query(
          profileId: ref.read(settingsProvider).activeProfileId,
          search: _q,
          onlyFavorites: _favOnly,
          after: _cursor,
          limit: 80,
        );
    if (!mounted) return;
    setState(() {
      _rows.addAll(page.rows);
      _cursor = page.cursor;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final active = ref.watch(settingsProvider.select((x) => x.activeNodeId));
    final ping = ref.watch(pingProvider);
    ref.listen<NodeListState>(nodeListProvider, (_, next) {
      if (!mounted || _rows.isEmpty) return;
      final latMap = {for (final r in next.rows) r.id: r.latency};
      setState(() {
        for (var i = 0; i < _rows.length; i++) {
          final lat = latMap[_rows[i].id];
          if (lat != null && lat != _rows[i].latency) {
            _rows[i] = _rows[i].copyWith(latency: lat);
          }
        }
      });
    });
    return Theme(
      data: Brand.theme(Theme.of(context)),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.t('home.search'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Brand.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  _q = v;
                  _reload();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(s.t('home.all')),
                  selected: !_favOnly,
                  onSelected: (_) {
                    _favOnly = false;
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(s.t('home.favorites')),
                  selected: _favOnly,
                  onSelected: (_) {
                    _favOnly = true;
                    _reload();
                  },
                ),
                const Spacer(),
                TextButton.icon(
                  icon: ping.running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed_rounded, size: 18),
                  label: Text(s.t('home.test_all')),
                  onPressed: ping.running
                      ? null
                      : () async {
                          await ref
                              .read(pingProvider.notifier)
                              .run(
                                profileId: ref
                                    .read(settingsProvider)
                                    .activeProfileId,
                                mode: 'url',
                              );
                          if (mounted) _reload();
                        },
                ),
              ],
            ),
          ),
          Expanded(
            child: _rows.isEmpty && !_loading
                ? _Empty(
                    onAdd: () {
                      Navigator.pop(context);
                      openMenuPage(context, MenuTarget.servers);
                    },
                  )
                : ListView.builder(
                    controller: widget.scroll,
                    itemCount: _rows.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return _FastestTile(
                          onTap: () {
                            Navigator.pop(context);
                            ref
                                .read(coreControllerProvider.notifier)
                                .connectFastest();
                          },
                        );
                      }
                      final r = _rows[i - 1];
                      return _NodeTile(
                        row: r,
                        selected: r.id == active,
                        onTap: () async {
                          Navigator.pop(context);
                          final ctl = ref.read(coreControllerProvider.notifier);
                          await ctl.selectNode(r.id);
                          if (!ref.read(coreControllerProvider).isConnected) {
                            await ctl.connect(nodeId: r.id);
                          }
                        },
                        onFav: () async {
                          await ref
                              .read(envProvider)
                              .repo
                              .setFavorite(r.id, !r.isFavorite);
                          setState(
                            () => _rows[i - 1] = r.copyWith(
                              isFavorite: !r.isFavorite,
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

class _FastestTile extends StatelessWidget {
  const _FastestTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: Brand.orbGradient(CoreStatus.connected),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.bolt_rounded, color: Brand.text),
    ),
    title: Text(
      context.s.t('home.fastest'),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    onTap: onTap,
  );
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.row,
    required this.selected,
    required this.onTap,
    required this.onFav,
  });
  final NodeRow row;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    final flag = leadingFlag(row.name);
    return ListTile(
      selected: selected,
      selectedTileColor: Brand.on.withValues(alpha: 0.08),
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Brand.panel,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: Brand.on) : null,
        ),
        child: flag != null
            ? Text(flag, style: const TextStyle(fontSize: 22))
            : const Icon(Icons.public_rounded, size: 20),
      ),
      title: Text(
        cleanName(row.name),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        row.protocol.toUpperCase(),
        style: const TextStyle(fontSize: 11.5, color: Brand.textDim),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SignalBars(row.latency, showLabel: true),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              row.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: row.isFavorite ? Brand.busy : Brand.textDim,
            ),
            onPressed: onFav,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.travel_explore_rounded, size: 48, color: Brand.off),
          const SizedBox(height: 12),
          Text(context.s.t('home.no_nodes'), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: Text(context.s.t('home.add')),
            onPressed: onAdd,
          ),
        ],
      ),
    ),
  );
}
