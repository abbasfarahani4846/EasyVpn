import 'dart:convert';

import '../bridge/core_bridge.dart';
import '../models/models.dart';
import 'app_database.dart';

/// Sort orders offered by the proxies page.
enum NodeSort { latency, name, protocol }

/// One page of nodes plus the keyset cursor for the next page.
class NodePage {
  const NodePage(this.rows, this.cursor);
  final List<NodeRow> rows;
  final List<Object?>? cursor; // null => no more pages
}

/// Profiles + nodes persistence.
///
/// * Lists read only cheap columns; the full node JSON (which contains
///   secrets) is stored sealed with AES-GCM and opened on demand through the
///   Go core (fast batch crypto, key held in the OS keystore).
/// * Search uses a trigram FTS5 index; paging uses keyset (never OFFSET).
class NodeRepository {
  NodeRepository(this.db, this.core, this.keyB64);
  final AppDatabase db;
  final CoreBridge core;
  final String keyB64;

  // ---- profiles ------------------------------------------------------------

  Future<List<Profile>> profiles() async {
    final rows = await db.query('''
      SELECT p.*, (SELECT COUNT(*) FROM nodes n WHERE n.profile_id = p.id) AS node_count
      FROM profiles p ORDER BY p.sort, p.rowid''');
    return rows.map(Profile.fromMap).toList();
  }

  Future<void> saveProfile(Profile p) async {
    await db.exec(
      '''
      INSERT INTO profiles(id, name, url, user_agent, auto_refresh, interval_hours, updated_at,
                           upload, download, total, expire, last_error, fail_count, sort)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?, (SELECT COALESCE(MAX(sort),0)+1 FROM profiles))
      ON CONFLICT(id) DO UPDATE SET
        name=excluded.name, url=excluded.url, user_agent=excluded.user_agent,
        auto_refresh=excluded.auto_refresh, interval_hours=excluded.interval_hours,
        updated_at=excluded.updated_at, upload=excluded.upload, download=excluded.download,
        total=excluded.total, expire=excluded.expire, last_error=excluded.last_error,
        fail_count=excluded.fail_count''',
      [
        p.id,
        p.name,
        p.url,
        p.userAgent,
        p.autoRefresh ? 1 : 0,
        p.intervalHours,
        p.updatedAt?.millisecondsSinceEpoch,
        p.upload,
        p.download,
        p.total,
        p.expire,
        p.lastError,
        p.failCount,
      ],
    );
  }

  Future<void> deleteProfile(String id) =>
      db.exec('DELETE FROM profiles WHERE id = ?', [id]);

  // ---- import --------------------------------------------------------------

  /// Inserts/updates [nodes] (raw Go ProxyNode maps) for a profile. Existing
  /// nodes keep favorite + latency (identity is the content-hash id); nodes no
  /// longer present are removed when [replace] is true. Returns (added, removed).
  Future<({int added, int removed, int total})> importNodes(
    String profileId,
    List<Map<String, dynamic>> nodes, {
    bool replace = true,
    void Function(int done, int total)? onProgress,
  }) async {
    final generation = DateTime.now().microsecondsSinceEpoch;
    final before =
        (await db.query('SELECT COUNT(*) c FROM nodes WHERE profile_id = ?', [
              profileId,
            ])).first['c']
            as int;

    const chunk = 500;
    for (var i = 0; i < nodes.length; i += chunk) {
      final slice = nodes.sublist(
        i,
        i + chunk > nodes.length ? nodes.length : i + chunk,
      );
      final sealed = await core.seal(keyB64, slice.map(jsonEncode).toList());
      final sb = StringBuffer(
        'INSERT INTO nodes(id, profile_id, name, protocol, server, port, group_tag, requires, raw_enc, seen, created_at) VALUES ',
      );
      final args = <Object?>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var j = 0; j < slice.length; j++) {
        final n = slice[j];
        if (j > 0) sb.write(',');
        sb.write('(?,?,?,?,?,?,?,?,?,?,?)');
        args.addAll([
          n['id'],
          profileId,
          n['name'] ?? '',
          n['type'] ?? '',
          n['server'] ?? '',
          n['port'] ?? 0,
          n['group'] ?? '',
          ((n['requires'] as List?) ?? const []).join(','),
          sealed[j],
          generation,
          now,
        ]);
      }
      sb.write(
        ''' ON CONFLICT(profile_id, id) DO UPDATE SET
          name=excluded.name, protocol=excluded.protocol, server=excluded.server, port=excluded.port,
          group_tag=excluded.group_tag, requires=excluded.requires, raw_enc=excluded.raw_enc, seen=excluded.seen''',
      );
      await db.transaction(() => db.exec(sb.toString(), args));
      onProgress?.call(i + slice.length, nodes.length);
    }

    var removed = 0;
    if (replace) {
      final r = await db.query(
        'SELECT COUNT(*) c FROM nodes WHERE profile_id = ? AND seen <> ?',
        [profileId, generation],
      );
      removed = r.first['c'] as int;
      await db.exec('DELETE FROM nodes WHERE profile_id = ? AND seen <> ?', [
        profileId,
        generation,
      ]);
    }
    final after =
        (await db.query('SELECT COUNT(*) c FROM nodes WHERE profile_id = ?', [
              profileId,
            ])).first['c']
            as int;
    final added = after - (before - removed);
    return (added: added < 0 ? 0 : added, removed: removed, total: after);
  }

  // ---- queries -------------------------------------------------------------

  static String _orderKeys(NodeSort sort, bool favFirst) {
    final fav = favFirst ? '(1 - is_favorite)' : '0';
    switch (sort) {
      case NodeSort.latency:
        return '$fav AS k1, (CASE WHEN latency > 0 THEN 0 ELSE 1 END) * 1000000 + (CASE WHEN latency > 0 THEN latency ELSE 0 END) AS k2';
      case NodeSort.name:
        return "$fav AS k1, LOWER(name) AS k2";
      case NodeSort.protocol:
        return "$fav AS k1, protocol || '|' || LOWER(name) AS k2";
    }
  }

  /// Keyset-paginated node query.
  Future<NodePage> query({
    String? profileId,
    String search = '',
    NodeSort sort = NodeSort.latency,
    bool favoritesFirst = true,
    bool onlyFavorites = false,
    String? protocol,
    List<Object?>? after,
    int limit = 100,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (profileId != null) {
      where.add('profile_id = ?');
      args.add(profileId);
    }
    if (protocol != null) {
      where.add('protocol = ?');
      args.add(protocol);
    }
    if (onlyFavorites) where.add('is_favorite = 1');

    final q = search.trim();
    if (q.isNotEmpty) {
      if (q.length >= 3) {
        where.add(
          'rowid IN (SELECT rowid FROM nodes_fts WHERE nodes_fts MATCH ?)',
        );
        args.add('"${q.replaceAll('"', '""')}"');
      } else {
        where.add('(name LIKE ? ESCAPE \'\\\' OR server LIKE ? ESCAPE \'\\\')');
        final like =
            '%${q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
        args
          ..add(like)
          ..add(like);
      }
    }

    final keys = _orderKeys(sort, favoritesFirst);
    final inner = StringBuffer('SELECT *, $keys FROM nodes');
    if (where.isNotEmpty) inner.write(' WHERE ${where.join(' AND ')}');

    final sb = StringBuffer('SELECT * FROM ($inner)');
    if (after != null) {
      sb.write(' WHERE (k1, k2, rowid) > (?, ?, ?)');
      args.addAll(after);
    }
    sb.write(' ORDER BY k1, k2, rowid LIMIT ?');
    args.add(limit + 1);

    final rows = await db.query(sb.toString(), args);
    final hasMore = rows.length > limit;
    final page = hasMore ? rows.sublist(0, limit) : rows;
    final cursor = hasMore
        ? [page.last['k1'], page.last['k2'], page.last['rowid']]
        : null;
    return NodePage(page.map(NodeRow.fromMap).toList(), cursor);
  }

  Future<int> count({String? profileId}) async {
    final r = profileId == null
        ? await db.query('SELECT COUNT(*) c FROM nodes')
        : await db.query('SELECT COUNT(*) c FROM nodes WHERE profile_id = ?', [
            profileId,
          ]);
    return r.first['c'] as int;
  }

  Future<NodeRow?> nodeRow(String id) async {
    final r = await db.query('SELECT * FROM nodes WHERE id = ? LIMIT 1', [id]);
    return r.isEmpty ? null : NodeRow.fromMap(r.first);
  }

  /// Full (decrypted) ProxyNode JSON for [ids]; order preserved, missing skipped.
  Future<List<Map<String, dynamic>>> rawNodes(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final rows = await db.query(
        'SELECT id, raw_enc FROM nodes WHERE id IN (${List.filled(part.length, '?').join(',')}) GROUP BY id',
        part,
      );
      if (rows.isEmpty) continue;
      final plain = await core.open(
        keyB64,
        rows.map((r) => r['raw_enc'] as String).toList(),
      );
      for (var j = 0; j < rows.length; j++) {
        out[rows[j]['id'] as String] = (jsonDecode(plain[j]) as Map)
            .cast<String, dynamic>();
      }
    }
    return [
      for (final id in ids)
        if (out[id] != null) out[id]!,
    ];
  }

  Future<Map<String, dynamic>?> rawNode(String id) async {
    final l = await rawNodes([id]);
    return l.isEmpty ? null : l.first;
  }

  /// Best-latency nodes of a profile (used as hot-switch candidates).
  Future<List<String>> topNodeIds({
    String? profileId,
    int limit = 49,
    String? exclude,
  }) async {
    final args = <Object?>[];
    final where = <String>['latency > 0'];
    if (profileId != null) {
      where.add('profile_id = ?');
      args.add(profileId);
    }
    if (exclude != null) {
      where.add('id <> ?');
      args.add(exclude);
    }
    args.add(limit);
    final r = await db.query(
      'SELECT DISTINCT id FROM nodes WHERE ${where.join(' AND ')} ORDER BY is_favorite DESC, latency LIMIT ?',
      args,
    );
    return r.map((e) => e['id'] as String).toList();
  }

  Future<List<String>> allIds({String? profileId}) async {
    final r = profileId == null
        ? await db.query('SELECT DISTINCT id FROM nodes')
        : await db.query('SELECT DISTINCT id FROM nodes WHERE profile_id = ?', [
            profileId,
          ]);
    return r.map((e) => e['id'] as String).toList();
  }

  // ---- mutations -----------------------------------------------------------

  Future<void> setLatencies(Map<String, int> ms) async {
    if (ms.isEmpty) return;
    await db.transaction(() async {
      for (final e in ms.entries) {
        await db.exec('UPDATE nodes SET latency = ?, alive = ? WHERE id = ?', [
          e.value,
          e.value > 0 ? 1 : 0,
          e.key,
        ]);
      }
    });
  }

  Future<void> setFavorite(String id, bool fav) => db.exec(
    'UPDATE nodes SET is_favorite = ? WHERE id = ?',
    [fav ? 1 : 0, id],
  );

  Future<void> rename(String id, String name) =>
      db.exec('UPDATE nodes SET name = ? WHERE id = ?', [name, id]);

  Future<void> deleteNode(String id) =>
      db.exec('DELETE FROM nodes WHERE id = ?', [id]);

  Future<void> clearLatencies() => db.exec('UPDATE nodes SET latency = -1');
}
