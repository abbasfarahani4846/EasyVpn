import 'package:fl_clash/easy/entry_server/entry_server_chain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> base() => {
    'proxies': <Map<String, dynamic>>[
      {'name': 'A', 'type': 'ss', 'server': 'a.com', 'port': 1},
      {
        'name': 'B',
        'type': 'ss',
        'server': 'b.com',
        'port': 2,
        'dialer-proxy': 'X',
      },
    ],
    'proxy-providers': {
      'p': {'type': 'http', 'url': 'u'},
      'q': {
        'type': 'http',
        'url': 'v',
        'override': {'udp': true},
      },
    },
  };
  final entry = <String, Object?>{
    'name': 'E',
    'type': 'vless',
    'server': 'e.com',
    'port': 3,
  };

  test('no entry leaves config untouched', () {
    final raw = base();
    expect(identical(EntryServerChain.apply(raw, null), raw), isTrue);
  });

  test('every other proxy and provider dials through the entry', () {
    final out = EntryServerChain.apply(base(), entry);
    final byName = {for (final p in out['proxies'] as List) p['name']: p};
    expect(byName['E'].containsKey('dialer-proxy'), isFalse);
    expect(byName['A']['dialer-proxy'], 'E');
    expect(byName['B']['dialer-proxy'], 'X', reason: 'explicit chains stay');
    final providers = out['proxy-providers'] as Map;
    expect(providers['p']['override']['dialer-proxy'], 'E');
    expect(providers['q']['override'], {'udp': true, 'dialer-proxy': 'E'});
  });

  test('clashing name is renamed, same server is reused', () {
    final clash = base();
    (clash['proxies'] as List).add({
      'name': 'E',
      'type': 'ss',
      'server': 'other.com',
      'port': 9,
    });
    final out = EntryServerChain.apply(clash, entry);
    final proxies = out['proxies'] as List;
    expect(proxies.map((p) => p['name']), contains('E [entry]'));
    final other = proxies.firstWhere((p) => p['server'] == 'other.com');
    expect(other['dialer-proxy'], 'E [entry]');

    final same = base();
    (same['proxies'] as List).add(
      Map<String, dynamic>.from(entry)..['dialer-proxy'] = 'A',
    );
    final out2 = EntryServerChain.apply(same, entry);
    final named = (out2['proxies'] as List).where((p) => p['name'] == 'E');
    expect(named, hasLength(1));
    expect(named.single.containsKey('dialer-proxy'), isFalse);
  });

  test('local proxies (Psiphon socks) are never routed through the entry', () {
    final raw = base();
    (raw['proxies'] as List).add({
      'name': 'Psiphon',
      'type': 'socks5',
      'server': '127.0.0.1',
      'port': 20830,
    });
    final out = EntryServerChain.apply(raw, entry);
    final psiphon = (out['proxies'] as List).firstWhere(
      (p) => p['name'] == 'Psiphon',
    );
    expect(psiphon.containsKey('dialer-proxy'), isFalse);
    final remote = (out['proxies'] as List).firstWhere((p) => p['name'] == 'A');
    expect(remote['dialer-proxy'], 'E');
  });

  test('input config is not mutated', () {
    final raw = base();
    EntryServerChain.apply(raw, entry);
    expect((raw['proxies'] as List).first.containsKey('dialer-proxy'), isFalse);
  });
}
