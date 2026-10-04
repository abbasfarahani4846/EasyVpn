import 'dart:io';

import 'package:fl_clash/easy/home/connection_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LinkState eval({
    String? core,
    String? system,
    String? baseline,
    bool tun = true,
  }) => ConnectionVerifier.evaluate(
    coreIp: core,
    systemIp: system,
    baselineIp: baseline,
    tunOn: tun,
  );

  test('verified only when core and system see the same new IP', () {
    expect(
      eval(core: '1.1.1.1', system: '1.1.1.1', baseline: '9.9.9.9'),
      LinkState.verified,
    );
  });

  test('no answer from the core is not a connection', () {
    expect(eval(core: null, system: '1.1.1.1'), LinkState.noAnswer);
  });

  test('same IP as before connecting means nothing changed', () {
    expect(
      eval(core: '9.9.9.9', system: '9.9.9.9', baseline: '9.9.9.9'),
      LinkState.unchanged,
    );
  });

  test('proxy works but the system bypasses it', () {
    expect(
      eval(core: '1.1.1.1', system: '9.9.9.9', baseline: '9.9.9.9'),
      LinkState.mismatch,
    );
  });

  test('TUN on but system IP unreachable is not verified', () {
    expect(eval(core: '1.1.1.1', system: null), LinkState.noAnswer);
  });

  test('without TUN the core answer alone is enough', () {
    expect(
      eval(core: '1.1.1.1', system: null, baseline: '9.9.9.9', tun: false),
      LinkState.verified,
    );
  });

  test('recognises IPv4 and IPv6, rejects html', () {
    expect(ConnectionVerifier.looksLikeIp('203.0.113.7'), isTrue);
    expect(ConnectionVerifier.looksLikeIp('2606:4700::1111'), isTrue);
    expect(ConnectionVerifier.looksLikeIp('<html>blocked</html>'), isFalse);
    expect(ConnectionVerifier.looksLikeIp(''), isFalse);
  });

  // Real network; run with EASY_LIVE_IP=1 flutter test test/easy/connection_verifier_test.dart
  test(
    'live: fetchIp returns this machine\'s public IP',
    () async {
      final ip = await ConnectionVerifier.fetchIp();
      expect(ip, isNotNull);
      expect(ConnectionVerifier.looksLikeIp(ip!), isTrue);
    },
    skip: Platform.environment.containsKey('EASY_LIVE_IP')
        ? false
        : 'set EASY_LIVE_IP to run',
  );
}
