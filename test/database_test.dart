import 'package:easyvpn/core/bridge/core_bridge.dart';
import 'package:easyvpn/core/database/app_database.dart';
import 'package:easyvpn/core/database/node_repository.dart';
import 'package:easyvpn/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

Map<String, dynamic> node(int i, {String? name}) => {
  'id': 'id$i',
  'name': name ?? 'Node $i',
  'type': i.isEven ? 'vless' : 'trojan',
  'server': 'host$i.example.com',
  'port': 443,
  'uuid': 'secret-$i',
};

void main() {
  late AppDatabase db;
  late NodeRepository repo;

  setUp(() async {
    db = AppDatabase.memory();
    repo = NodeRepository(db, CoreBridge(FakeTransport()), 'key');
    await repo.saveProfile(const Profile(id: 'p1', name: 'Main'));
  });
  tearDown(() => db.close());

  test('imports 10k nodes quickly and pages with keyset cursors', () async {
    final nodes = [for (var i = 0; i < 10000; i++) node(i)];
    final sw = Stopwatch()..start();
    final r = await repo.importNodes('p1', nodes);
    sw.stop();
    expect(r.total, 10000);
    expect(r.added, 10000);
    // Budget is 5 s on a real device with the real core; the fake seals with base64.
    expect(
      sw.elapsedMilliseconds,
      lessThan(8000),
      reason: 'import took ${sw.elapsedMilliseconds} ms',
    );

    var seen = 0;
    List<Object?>? cursor;
    var pages = 0;
    do {
      final p = await repo.query(profileId: 'p1', after: cursor, limit: 500);
      seen += p.rows.length;
      cursor = p.cursor;
      pages++;
    } while (cursor != null);
    expect(seen, 10000);
    expect(pages, 20);
  });

  test('search uses FTS for >=3 chars and LIKE for short queries', () async {
    await repo.importNodes('p1', [
      node(1, name: 'Tehran Reality'),
      node(2, name: 'Berlin Hy2'),
      node(3, name: 'Tokyo TUIC'),
    ]);
    expect((await repo.query(search: 'reality')).rows.map((r) => r.name), [
      'Tehran Reality',
    ]);
    expect((await repo.query(search: 'host2')).rows.single.id, 'id2');
    expect(
      (await repo.query(search: 'To')).rows.single.name,
      'Tokyo TUIC',
    ); // short query => LIKE
    expect((await repo.query(search: 'nomatch')).rows, isEmpty);
    // quotes must not break the FTS expression
    expect((await repo.query(search: 'a"b"c')).rows, isEmpty);
  });

  test(
    're-import keeps favorites and latency, removes missing nodes',
    () async {
      await repo.importNodes('p1', [node(1), node(2), node(3)]);
      await repo.setFavorite('id2', true);
      await repo.setLatencies({'id2': 120, 'id1': 300});

      final r = await repo.importNodes('p1', [node(2), node(3), node(4)]);
      expect(r.removed, 1);
      expect(r.added, 1);
      expect(r.total, 3);

      final p = await repo.query(profileId: 'p1', sort: NodeSort.name);
      final n2 = p.rows.firstWhere((n) => n.id == 'id2');
      expect(n2.isFavorite, isTrue);
      expect(n2.latency, 120);
      expect(p.rows.any((n) => n.id == 'id1'), isFalse);
    },
  );

  test('sorting puts favorites first and untested nodes last', () async {
    await repo.importNodes('p1', [node(1), node(2), node(3), node(4)]);
    await repo.setLatencies({'id1': 200, 'id2': 50});
    await repo.setFavorite('id1', true);
    final ids = (await repo.query()).rows.map((r) => r.id).toList();
    expect(ids.first, 'id1'); // favorite
    expect(ids[1], 'id2'); // then fastest
    expect(ids.sublist(2).toSet(), {'id3', 'id4'}); // untested last
  });

  test('raw node JSON round-trips through sealing', () async {
    await repo.importNodes('p1', [node(7)]);
    final raw = await repo.rawNode('id7');
    expect(raw!['uuid'], 'secret-7');
    // The stored column is not plaintext.
    final row = await db.query('SELECT raw_enc FROM nodes WHERE id = ?', [
      'id7',
    ]);
    expect(row.first['raw_enc'] as String, isNot(contains('secret-7')));
  });

  test('deleting a profile cascades to its nodes', () async {
    await repo.importNodes('p1', [node(1), node(2)]);
    await repo.deleteProfile('p1');
    expect(await repo.count(), 0);
  });
}
