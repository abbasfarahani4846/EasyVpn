import 'dart:convert';

import 'package:fl_clash/easy/psiphon/psiphon_constants.dart';
import 'package:fl_clash/easy/psiphon/psiphon_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> build(String rung) => PsiphonLadder.buildConfig(
  rung: PsiphonLadder.byName(rung)!,
  dataDir: 'C:/data',
  socksPort: 20830,
);

void main() {
  test('every rung is present and the winner goes first', () {
    expect(PsiphonLadder.rungs.map((r) => r.name), ['A', 'D', 'C']);
    expect(PsiphonLadder.order().map((r) => r.name), ['A', 'D', 'C']);
    expect(PsiphonLadder.order(winner: 'C').map((r) => r.name), ['C', 'A', 'D']);
    expect(PsiphonLadder.order(winner: 'zz').map((r) => r.name), ['A', 'D', 'C']);
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
    expect(psiphonRemoteServerListSignatureKey, startsWith('MIICIDANBgkqhkiG9w0'));
    expect(psiphonServerEntrySignatureKey, hasLength(44));
    expect(psiphonExchangeObfuscationKey, hasLength(44));
    expect(psiphonAlternateDns, hasLength(3));
  });
}
