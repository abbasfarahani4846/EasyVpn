import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/node_repository.dart';
import '../models/models.dart';
import 'env.dart';

class NodeListState {
  const NodeListState({
    this.rows = const [],
    this.cursor,
    this.loading = false,
    this.query = '',
    this.profileId,
    this.sort = NodeSort.latency,
    this.favoritesFirst = true,
    this.onlyFavorites = false,
    this.protocol,
    this.total = 0,
  });

  final List<NodeRow> rows;
  final List<Object?>? cursor;
  final bool loading;
  final String query;
  final String? profileId;
  final NodeSort sort;
  final bool favoritesFirst;
  final bool onlyFavorites;
  final String? protocol;
  final int total;

  bool get hasMore => cursor != null;

  NodeListState copyWith({
    List<NodeRow>? rows,
    Object? cursor = _keep,
    bool? loading,
    String? query,
    Object? profileId = _keep,
    NodeSort? sort,
    bool? favoritesFirst,
    bool? onlyFavorites,
    Object? protocol = _keep,
    int? total,
  }) => NodeListState(
    rows: rows ?? this.rows,
    cursor: identical(cursor, _keep) ? this.cursor : cursor as List<Object?>?,
    loading: loading ?? this.loading,
    query: query ?? this.query,
    profileId: identical(profileId, _keep)
        ? this.profileId
        : profileId as String?,
    sort: sort ?? this.sort,
    favoritesFirst: favoritesFirst ?? this.favoritesFirst,
    onlyFavorites: onlyFavorites ?? this.onlyFavorites,
    protocol: identical(protocol, _keep) ? this.protocol : protocol as String?,
    total: total ?? this.total,
  );

  static const Object _keep = Object();
}

/// Virtualization-friendly node list: filters/search reset the keyset cursor
/// and pages are appended on scroll. Search is debounced (150 ms).
class NodeListController extends Notifier<NodeListState> {
  Timer? _debounce;
  int _gen = 0;

  @override
  NodeListState build() {
    ref.onDispose(() => _debounce?.cancel());
    Future.microtask(reload);
    return const NodeListState();
  }

  NodeRepository get _repo => ref.read(envProvider).repo;

  Future<void> reload() async {
    final gen = ++_gen;
    state = state.copyWith(loading: true);
    final s = state;
    final page = await _repo.query(
      profileId: s.profileId,
      search: s.query,
      sort: s.sort,
      favoritesFirst: s.favoritesFirst,
      onlyFavorites: s.onlyFavorites,
      protocol: s.protocol,
    );
    final total = await _repo.count(profileId: s.profileId);
    if (gen != _gen) return; // a newer query superseded this one
    state = state.copyWith(
      rows: page.rows,
      cursor: page.cursor,
      loading: false,
      total: total,
    );
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.loading || s.cursor == null) return;
    final gen = _gen;
    state = s.copyWith(loading: true);
    final page = await _repo.query(
      profileId: s.profileId,
      search: s.query,
      sort: s.sort,
      favoritesFirst: s.favoritesFirst,
      onlyFavorites: s.onlyFavorites,
      protocol: s.protocol,
      after: s.cursor,
    );
    if (gen != _gen) return;
    state = state.copyWith(
      rows: [...state.rows, ...page.rows],
      cursor: page.cursor,
      loading: false,
    );
  }

  void setQuery(String q) {
    _debounce?.cancel();
    state = state.copyWith(query: q);
    _debounce = Timer(const Duration(milliseconds: 150), reload);
  }

  void setProfile(String? id) {
    state = state.copyWith(profileId: id);
    reload();
  }

  void setSort(NodeSort s) {
    state = state.copyWith(sort: s);
    reload();
  }

  void setFavoritesFirst(bool v) {
    state = state.copyWith(favoritesFirst: v);
    reload();
  }

  void setOnlyFavorites(bool v) {
    state = state.copyWith(onlyFavorites: v);
    reload();
  }

  void setProtocol(String? p) {
    state = state.copyWith(protocol: p);
    reload();
  }

  /// In-place latency update from ping events (no re-query, no scroll jump).
  void applyLatency(Map<String, int> ms) {
    if (ms.isEmpty) return;
    state = state.copyWith(
      rows: [
        for (final r in state.rows)
          ms.containsKey(r.id) ? r.copyWith(latency: ms[r.id]) : r,
      ],
    );
  }

  Future<void> toggleFavorite(NodeRow r) async {
    await _repo.setFavorite(r.id, !r.isFavorite);
    state = state.copyWith(
      rows: [
        for (final x in state.rows)
          x.id == r.id ? x.copyWith(isFavorite: !r.isFavorite) : x,
      ],
    );
  }

  Future<void> rename(NodeRow r, String name) async {
    await _repo.rename(r.id, name);
    state = state.copyWith(
      rows: [
        for (final x in state.rows) x.id == r.id ? x.copyWith(name: name) : x,
      ],
    );
  }

  Future<void> delete(NodeRow r) async {
    await _repo.deleteNode(r.id);
    state = state.copyWith(
      rows: state.rows.where((x) => x.id != r.id).toList(),
      total: state.total - 1,
    );
  }
}

final nodeListProvider = NotifierProvider<NodeListController, NodeListState>(
  NodeListController.new,
);
