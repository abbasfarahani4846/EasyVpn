import 'dart:io';

import 'package:fl_clash/easy/country_bypass/country_bypass_config.dart';
import 'package:fl_clash/easy/country_bypass/country_rules_cache.dart';
import 'package:fl_clash/easy/country_bypass/country_rules_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('easy_country_test');
    CountryRulesCache.testDirectory = dir;
  });

  tearDown(() async {
    CountryRulesCache.testDirectory = null;
    await dir.delete(recursive: true);
  });

  Future<(int, List<int>)> get(String path, int port) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/$path'),
      );
      final response = await request.close();
      final bytes = <int>[];
      await for (final c in response) {
        bytes.addAll(c);
      }
      return (response.statusCode, bytes);
    } finally {
      client.close(force: true);
    }
  }

  test(
    'serves a cached list over loopback and refuses everything else',
    () async {
      await File('${dir.path}/ir-ip.mrs').writeAsBytes(List.filled(100, 7));
      final server = CountryRulesServer.forTest(0);
      addTearDown(server.stop);
      expect(await server.ensureStarted(), isTrue);
      final port = server.boundPort;
      final ok = await get('ir-ip.mrs', port);
      expect(ok.$1, 200);
      expect(ok.$2, hasLength(100));
      expect((await get('ir-domain.mrs', port)).$1, 404, reason: 'not cached');
      expect(
        (await get('..%2Fsecret.mrs', port)).$1,
        404,
        reason: 'no traversal',
      );
      expect(
        (await get('config.yaml', port)).$1,
        404,
        reason: 'only .mrs lists',
      );
    },
  );

  test(
    'every answer closes the connection so none is reused when idle',
    () async {
      await File('${dir.path}/ir-ip.mrs').writeAsBytes(List.filled(100, 7));
      final server = CountryRulesServer.forTest(0);
      addTearDown(server.stop);
      await server.ensureStarted();
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse(server.urlFor('ir-ip.mrs')),
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.persistentConnection, isFalse);
      expect(response.headers.value('connection'), 'close');
    },
  );

  test('a list that is not available is left out instead of waited for', () {
    final raw = {
      'rules': ['MATCH,Proxy'],
    };
    const selection = CountrySelection(code: 'ir');
    expect(
      identical(CountryBypassConfig.apply(raw, selection, urls: {}), raw),
      isTrue,
    );
    final onlyIp = CountryBypassConfig.apply(
      raw,
      selection,
      urls: {'easy-ir-ip': 'http://127.0.0.1:20841/ir-ip.mrs'},
    );
    expect((onlyIp['rule-providers'] as Map).keys, ['easy-ir-ip']);
    expect(onlyIp['rules'], [
      'RULE-SET,easy-ir-ip,DIRECT,no-resolve',
      'MATCH,Proxy',
    ]);
  });

  test('sources name both a primary and a mirror for every list', () {
    final s = CountryRulesCache.sources(const CountrySelection(code: 'ir'));
    expect(s.map((e) => e.provider), ['easy-ir-domain', 'easy-ir-ip']);
    for (final e in s) {
      expect(e.urls, hasLength(2));
      expect(e.urls.first, startsWith('https://raw.githubusercontent.com/'));
      expect(e.urls.last, startsWith('https://cdn.jsdelivr.net/'));
    }
    final mirrored = CountryRulesCache.sources(
      const CountrySelection(code: 'ir', mirror: true),
    );
    expect(mirrored.first.urls.first, startsWith('https://cdn.jsdelivr.net/'));
  });
}
