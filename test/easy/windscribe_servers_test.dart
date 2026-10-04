import 'package:fl_clash/easy/windscribe/windscribe_servers.dart';
import 'package:flutter_test/flutter_test.dart';

// Trimmed from the shape of assets.windscribe.com/serverlist/mob-v2/1/1.
final _list = {
  'data': [
    {
      'id': 65,
      'name': 'US Central',
      'country_code': 'US',
      'status': 1,
      'groups': [
        {
          'id': 86,
          'city': 'Dallas',
          'nick': 'Ranch',
          'pro': 1,
          'wg_pubkey': 'DALLASPUBKEY=',
          'wg_endpoint': 'dfw-86-wg.example.com',
          'nodes': [
            {
              'ip': '1.1.1.1',
              'ip2': '1.1.1.2',
              'ip3': '1.1.1.3',
              'hostname': 'a',
            },
          ],
        },
        {
          'id': 87,
          'city': 'Atlanta',
          'nick': 'Mountain',
          'pro': 0,
          'wg_pubkey': 'ATLPUBKEY=',
          'wg_endpoint': 'atl-87-wg.example.com',
          'nodes': [
            {
              'ip': '2.2.2.1',
              'ip2': '2.2.2.2',
              'ip3': '2.2.2.3',
              'hostname': 'b',
            },
          ],
        },
      ],
    },
    {
      'id': 70,
      'name': 'Germany',
      'country_code': 'DE',
      'status': 1,
      'groups': [
        {
          'id': 5,
          'city': 'Frankfurt',
          'nick': 'Gold',
          'pro': 0,
          'wg_pubkey': 'FRAPUBKEY=',
          'wg_endpoint': 'fra-5-wg.example.com',
        },
        {'id': 6, 'city': 'Broken', 'nick': 'NoKey', 'pro': 0, 'wg_pubkey': ''},
      ],
    },
    {
      'id': 71,
      'name': 'Offline',
      'country_code': 'XX',
      'status': 0,
      'groups': [],
    },
  ],
};

final _account = <String, Object?>{
  'name': 'my',
  'type': 'wireguard',
  'server': 'old.example.com',
  'port': 443,
  'ip': '100.64.1.2',
  'private-key': 'PRIV=',
  'public-key': 'OLDPUB=',
  'pre-shared-key': 'PSK=',
  'allowed-ips': ['0.0.0.0/0'],
  'dns': ['10.255.255.1'],
  'udp': true,
};

void main() {
  test(
    'parses cities with key and endpoint, skipping broken or offline ones',
    () {
      final cities = WindscribeServers.parse(_list);
      expect(cities.map((c) => c.city), ['Dallas', 'Atlanta', 'Frankfurt']);
      expect(cities[0].endpoint, '1.1.1.3', reason: 'node ip3 when present');
      expect(
        cities[2].endpoint,
        'fra-5-wg.example.com',
        reason: 'else the hostname',
      );
      expect(cities.map((c) => c.pro), [true, false, false]);
      expect(cities[0].label, startsWith(cities[0].flag));
      expect(cities[0].label, contains('Dallas (Ranch)'));
    },
  );

  test('free accounts get only the free cities', () {
    final cities = WindscribeServers.parse(_list);
    final free = WindscribeServers.expand(_account, cities, proAccount: false);
    expect(free.map((p) => p['public-key']), ['ATLPUBKEY=', 'FRAPUBKEY=']);
    final pro = WindscribeServers.expand(_account, cities, proAccount: true);
    expect(pro, hasLength(3));
  });

  test('every node keeps the account material and swaps only the server', () {
    final cities = WindscribeServers.parse(_list);
    final p = WindscribeServers.expand(
      _account,
      cities,
      proAccount: true,
    ).first;
    expect(p['private-key'], 'PRIV=');
    expect(p['pre-shared-key'], 'PSK=');
    expect(p['ip'], '100.64.1.2');
    expect(p['dns'], ['10.255.255.1']);
    expect(p['server'], '1.1.1.3');
    expect(p['public-key'], 'DALLASPUBKEY=');
    expect(p['port'], 443);
    expect(p['name'], contains('Dallas'));
  });

  test('free city ids come from the free list, not the all-pro list', () {
    final allList = WindscribeServers.parse(_list);
    expect(
      allList.every((c) => c.pro) == false,
      isTrue,
      reason: 'fixture mixes',
    );
    // As the real full list: every city says pro.
    final realistic = WindscribeServers.parse({
      'data': [
        {
          'name': 'X',
          'country_code': 'US',
          'status': 1,
          'groups': [
            {
              'id': 1,
              'city': 'A',
              'nick': 'a',
              'pro': 1,
              'wg_pubkey': 'K',
              'wg_endpoint': 'h',
            },
            {
              'id': 2,
              'city': 'B',
              'nick': 'b',
              'pro': 1,
              'wg_pubkey': 'K2',
              'wg_endpoint': 'h2',
            },
          ],
        },
      ],
    });
    expect(realistic.every((c) => c.pro), isTrue);
    final free = WindscribeServers.freeGroupIds({
      'data': [
        {
          'name': 'X',
          'country_code': 'US',
          'status': 1,
          'groups': [
            {
              'id': 2,
              'city': 'B',
              'nick': 'b',
              'pro': 0,
              'wg_pubkey': 'K2',
              'wg_endpoint': 'h2',
            },
          ],
        },
      ],
    });
    expect(free, {'2'});
    final marked = [
      for (final c in realistic) c.withPro(!free.contains(c.groupId)),
    ];
    final out = WindscribeServers.expand(_account, marked, proAccount: false);
    expect(out.map((p) => p['public-key']), ['K2']);
  });

  test('names stay unique', () {
    final twin = WindscribeServers.parse({
      'data': [
        {
          'name': 'Dup',
          'country_code': 'US',
          'status': 1,
          'groups': [
            {
              'id': 1,
              'city': 'A',
              'nick': 'B',
              'pro': 0,
              'wg_pubkey': 'K1',
              'wg_endpoint': 'h1',
            },
            {
              'id': 2,
              'city': 'A',
              'nick': 'B',
              'pro': 0,
              'wg_pubkey': 'K2',
              'wg_endpoint': 'h2',
            },
          ],
        },
      ],
    });
    final out = WindscribeServers.expand(_account, twin, proAccount: true);
    expect(out.map((p) => p['name']).toSet(), hasLength(2));
  });
}
