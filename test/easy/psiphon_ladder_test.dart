import 'dart:convert';

import 'package:fl_clash/easy/psiphon/psiphon_constants.dart';
import 'package:fl_clash/easy/psiphon/psiphon_ladder.dart';
import 'package:fl_clash/easy/psiphon/network_fingerprint.dart';
import 'package:fl_clash/easy/psiphon/psiphon_manager.dart';
import 'package:fl_clash/easy/psiphon/psiphon_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> build(String rung) => PsiphonLadder.buildConfig(
  rung: PsiphonLadder.byName(rung)!,
  dataDir: 'C:/data',
  socksPort: 20830,
);

void main() {
  psiphonNodeTests();
  psiphonRegionTests();
  psiphonSpeedTests();
  test('every rung is present and the winner goes first', () {
    expect(PsiphonLadder.rungs.map((r) => r.name), ['A', 'D', 'C']);
    expect(PsiphonLadder.order().map((r) => r.name), ['A', 'D', 'C']);
    expect(PsiphonLadder.order(winner: 'C').map((r) => r.name), [
      'C',
      'A',
      'D',
    ]);
    expect(PsiphonLadder.order(winner: 'zz').map((r) => r.name), [
      'A',
      'D',
      'C',
    ]);
  });

  test('base config carries the drops and keys, URLs base64 encoded', () {
    final c = build('A');
    final drops = c['RemoteServerListURLs'] as List;
    expect(drops, hasLength(4));
    expect(
      utf8.decode(base64.decode((drops.first as Map)['URL'] as String)),
      startsWith('https://s3.amazonaws.com/psiphon/'),
    );
    expect(c['RemoteServerListSignaturePublicKey'], hasLength(732));
    expect((c['ObfuscatedServerListRootURLs'] as List), hasLength(4));
    expect(c['LocalSocksProxyPort'], 20830);
    expect(c['RemoteServerListDownloadFilename'], 'C:/data/remote_server_list');
  });

  test('rung A is fronted-only without tactics or in-proxy', () {
    final c = build('A');
    expect(c['LimitTunnelProtocols'], PsiphonLadder.fronted);
    expect(c['DisableTactics'], true);
    expect(c['InproxyEnabled'], false);
  });

  test('rung D has no protocol limit, rung C enables in-proxy', () {
    final d = build('D');
    expect(d.containsKey('LimitTunnelProtocols'), isFalse);
    expect(d['DisableTactics'], true);
    final c = build('C');
    expect(c['InproxyEnabled'], true);
    expect(c['InproxyAllowClient'], true);
    expect(c.containsKey('DisableTactics'), isFalse);
  });

  test('constants are intact', () {
    expect(
      psiphonRemoteServerListSignatureKey,
      startsWith('MIICIDANBgkqhkiG9w0'),
    );
    expect(psiphonServerEntrySignatureKey, hasLength(44));
    expect(psiphonExchangeObfuscationKey, hasLength(44));
    expect(psiphonAlternateDns, hasLength(3));
  });
}

void psiphonSpeedTests() {
  test('budgets start short and grow with each pass', () {
    final a = PsiphonLadder.byName('A')!;
    final d = PsiphonLadder.byName('D')!;
    expect(PsiphonLadder.budgetFor(a, 0), lessThanOrEqualTo(10));
    expect(PsiphonLadder.budgetFor(d, 0), lessThanOrEqualTo(10));
    expect(
      PsiphonLadder.budgetFor(a, 1),
      greaterThan(PsiphonLadder.budgetFor(a, 0)),
    );
    expect(
      PsiphonLadder.budgetFor(a, 2),
      greaterThan(PsiphonLadder.budgetFor(a, 1)),
    );
  });

  test('chained runs drop the in-proxy rung and use an upstream proxy', () {
    expect(PsiphonLadder.orderFor(chained: true).map((r) => r.name), [
      'A',
      'D',
    ]);
    expect(
      PsiphonLadder.orderFor(winner: 'C', chained: true).map((r) => r.name),
      ['A', 'D'],
    );
    expect(PsiphonLadder.orderFor().map((r) => r.name), ['A', 'D', 'C']);
    final c = PsiphonLadder.buildConfig(
      rung: PsiphonLadder.byName('D')!,
      dataDir: 'C:/d',
      socksPort: 20830,
      upstreamProxyUrl: 'socks5://127.0.0.1:20840',
    );
    expect(c['UpstreamProxyURL'], 'socks5://127.0.0.1:20840');
    expect(c['LimitTunnelProtocols'], PsiphonLadder.chainable);
    expect(c['InproxyEnabled'], false);
    expect((c['LimitTunnelProtocols'] as List).contains('QUIC-OSSH'), isFalse);
  });
}

void psiphonRegionTests() {
  test('profile lists Auto plus one node per region, each parseable', () {
    final nodes = PsiphonNodes.build();
    expect(nodes, hasLength(1 + PsiphonNodes.regions.length));
    expect(nodes.map((n) => n['name']).toSet(), hasLength(nodes.length));
    expect(PsiphonNodes.parse(PsiphonNodes.autoName), (
      isPsiphon: true,
      region: null,
    ));
    expect(PsiphonNodes.parse(PsiphonNodes.nameFor('DE')), (
      isPsiphon: true,
      region: 'DE',
    ));
    expect(PsiphonNodes.parse('some other node'), (
      isPsiphon: false,
      region: null,
    ));
    expect(PsiphonNodes.nameFor('DE'), startsWith(PsiphonNodes.flag('DE')));
  });

  test(
    'a chosen region sets EgressRegion; fronted limit only where it fits',
    () {
      Map<String, Object?> forRegion(String? r) => PsiphonLadder.buildConfig(
        rung: PsiphonLadder.byName('A')!,
        dataDir: 'C:/d',
        socksPort: 20830,
        egressRegion: r,
      );
      expect(forRegion(null)['EgressRegion'], '');
      final de = forRegion('DE');
      expect(de['EgressRegion'], 'DE');
      expect(de['LimitTunnelProtocols'], PsiphonLadder.fronted);
      final jp = forRegion('JP');
      expect(jp['EgressRegion'], 'JP');
      expect(jp.containsKey('LimitTunnelProtocols'), isFalse);
      expect(jp.containsKey('InitialLimitTunnelProtocols'), isFalse);
    },
  );

  test('network fingerprint ignores virtual adapters and is stable', () {
    final wifi = {
      'Wi-Fi': ['192.168.1.20'],
    };
    final a = NetworkFingerprint.of(wifi);
    final withTun = NetworkFingerprint.of({
      ...wifi,
      'Meta': ['198.18.0.1'],
      'sing-tun': ['172.19.0.1'],
    });
    expect(withTun, a);
    expect(
      NetworkFingerprint.of({
        'Wi-Fi': ['192.168.1.99'],
      }),
      a,
      reason: 'same /24',
    );
    expect(
      NetworkFingerprint.of({
        'Wi-Fi': ['10.0.0.5'],
      }),
      isNot(a),
    );
    expect(
      NetworkFingerprint.of({
        'Ethernet': ['192.168.1.20'],
      }),
      isNot(a),
    );
    expect(NetworkFingerprint.of({}), 'offline');
  });
}

void psiphonNodeTests() {
  test('detects the Psiphon socks node in a config', () {
    expect(
      PsiphonManager.isPsiphonNodeIn({
        'proxies': [
          {'name': 'x', 'type': 'ss', 'server': 'a', 'port': 1},
          {
            'name': 'Psiphon',
            'type': 'socks5',
            'server': '127.0.0.1',
            'port': 20830,
          },
        ],
      }),
      isTrue,
    );
    expect(PsiphonManager.isPsiphonNodeIn({'proxies': []}), isFalse);
    expect(
      PsiphonManager.isPsiphonNodeIn({
        'proxies': [
          {'name': 'o', 'type': 'socks5', 'server': '127.0.0.1', 'port': 1080},
        ],
      }),
      isFalse,
    );
  });
}
