import 'dart:io';

import 'package:easy_vpn/easy/endpoint_healer/endpoint_healer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _yaml = '''
mode: rule
proxies:
- name: "🇺🇸 USA"
  type: vless
  server: us.example.com
  port: 1108
  tls: true
  servername: sni.example.com
  network: xhttp
- name: down
  type: vless
  server: down.example.com
  port: 1108
  network: ws
- name: fine
  type: trojan
  server: ok.example.com
  port: 443
- name: udp
  type: hysteria2
  server: h.example.com
  port: 1108
proxy-groups:
- name: PROXY
  type: select
  proxies:
  - "🇺🇸 USA"
''';

void main() {
  Future<bool> probeOpen(Set<String> open, String host, int port) async =>
      open.contains('$host:$port');

  test('moves a dead port to the fallback that answers', () async {
    final seen = <String>[];
    final report = await EndpointHealer.heal(
      _yaml,
      probe: (host, port, {required tls, sni}) async {
        seen.add('$host:$port:$tls:${sni ?? ''}');
        return probeOpen(
          {'us.example.com:1001', 'ok.example.com:443'},
          host,
          port,
        );
      },
    );

    expect(report.repaired.single.name, '🇺🇸 USA');
    expect(report.repaired.single.from, 1108);
    expect(report.repaired.single.to, 1001);
    expect(report.failed.single.name, 'down');
    expect(report.failed.single.tried, [1108, 1001]);
    expect(seen, contains('us.example.com:1001:true:sni.example.com'));
    expect(seen.any((s) => s.startsWith('h.example.com')), isFalse);

    final doc = loadYaml(report.yaml) as YamlMap;
    final proxies = doc['proxies'] as YamlList;
    expect(proxies[0]['port'], 1001);
    expect(proxies[1]['port'], 1108);
    expect(proxies[3]['port'], 1108);
    expect(report.yaml.replaceFirst('port: 1001', 'port: 1108'), _yaml);
  });

  test('a node that answers on its own port is left alone', () async {
    final report = await EndpointHealer.heal(
      _yaml,
      probe: (host, port, {required tls, sni}) async =>
          port == 1108 || port == 443,
    );
    expect(report.changed, isFalse);
    expect(report.failed, isEmpty);
    expect(report.yaml, _yaml);
  });

  test('probes each distinct endpoint once and respects the pool', () async {
    var running = 0;
    var peak = 0;
    var calls = 0;
    final many = StringBuffer('proxies:\n');
    for (var i = 0; i < 10; i++) {
      many.write(
        '- name: n$i\n  type: vless\n  server: h$i.example.com\n  port: 1108\n',
      );
    }
    many.write(
      '- name: dup\n  type: vless\n  server: h0.example.com\n  port: 1108\n',
    );
    final report = await EndpointHealer.heal(
      many.toString(),
      concurrency: 3,
      probe: (host, port, {required tls, sni}) async {
        calls++;
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        return true;
      },
    );
    expect(report.failed, isEmpty);
    expect(peak, lessThanOrEqualTo(3));
    expect(calls, 10);
  });

  test('unparsable or proxy-less text is returned untouched', () async {
    for (final text in ['', 'mode: rule', 'a: [', 'proxies: 3']) {
      final report = await EndpointHealer.heal(
        text,
        probe: (host, port, {required tls, sni}) async => false,
      );
      expect(report.yaml, text);
      expect(report.failed, isEmpty);
    }
  });

  test('tcpProbe tells an open port from a closed one', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = closed.port;
    await closed.close();

    expect(
      await EndpointHealer.tcpProbe('127.0.0.1', server.port, tls: false),
      isTrue,
    );
    expect(
      await EndpointHealer.tcpProbe('127.0.0.1', closedPort, tls: false),
      isFalse,
    );
    expect(
      await EndpointHealer.tcpProbe('127.0.0.1', server.port, tls: true),
      isFalse,
    );
  });
}
