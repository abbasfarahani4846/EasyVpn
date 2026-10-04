import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/yaml.dart';
import 'package:fl_clash/easy/warp/warp_registration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final response = {
    'config': {
      'client_id': base64.encode([1, 2, 3]),
      'peers': [
        {
          'public_key': 'PEERPUB',
          'endpoint': {'host': 'engage.cloudflareclient.com:2408'},
        },
      ],
      'interface': {
        'addresses': {'v4': '172.16.0.2', 'v6': '2606:4700::1'},
      },
    },
  };

  test('maps the registration answer to a wireguard proxy', () {
    final p = WarpRegistration.buildProxy(
      privateKey: 'PRIV',
      response: response,
      name: 'WARP',
    );
    expect(p['type'], 'wireguard');
    expect(p['server'], 'engage.cloudflareclient.com');
    expect(p['port'], 2408);
    expect(p['ip'], '172.16.0.2');
    expect(p['ipv6'], '2606:4700::1');
    expect(p['private-key'], 'PRIV');
    expect(p['public-key'], 'PEERPUB');
    expect(p['reserved'], [1, 2, 3]);
  });

  test('unexpected answers become a WarpException', () {
    expect(
      () => WarpRegistration.buildProxy(
        privateKey: 'k',
        response: {'nope': 1},
        name: 'WARP',
      ),
      throwsA(isA<WarpException>()),
    );
  });

  // Calls the real Cloudflare API, so it only runs when asked:
  //   EASY_LIVE_WARP=<yaml output path> flutter test test/easy/warp_registration_test.dart
  final livePath = Platform.environment['EASY_LIVE_WARP'];
  test(
    'live registration writes a usable proxy',
    () async {
      final proxy = await WarpRegistration.register(name: 'WARP');
      File(livePath!).writeAsStringSync(
        yaml.encode({
          'proxies': [proxy],
        }),
      );
      expect(proxy['type'], 'wireguard');
    },
    skip: livePath == null ? 'set EASY_LIVE_WARP to run' : false,
  );
}
