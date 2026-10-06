import 'dart:convert';
import 'package:easy_vpn/easy/single_config/default_profile_config.dart';
import 'package:easy_vpn/easy/single_config/share_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uuid = '11111111-2222-3333-4444-555555555555';

  test('vless xhttp with mlkem encryption', () {
    final r = ShareLinkParser.parse(
      'vless://$uuid@example.com:1001?encryption=mlkem768x25519plus.native.0rtt.KEY'
      '&security=tls&sni=sni.example.com&type=xhttp&host=h.example.com&path=%2F'
      '&mode=stream-up&extra=%7B%22xPaddingBytes%22%3A%22100-1000%22%2C%22xPaddingObfsMode%22%3Atrue%7D#Node%201',
    );
    expect(r.errors, isEmpty);
    final p = r.proxies.single;
    expect(p['name'], 'Node 1');
    expect(p['type'], 'vless');
    expect(p['port'], 1001);
    expect(p['encryption'], startsWith('mlkem768x25519plus'));
    expect(p['network'], 'xhttp');
    expect(p['tls'], true);
    final opts = p['xhttp-opts'] as Map;
    expect(opts['mode'], 'stream-up');
    expect(opts['x-padding-bytes'], '100-1000');
    expect(opts['x-padding-obfs-mode'], true);
  });

  test(
    'vless xhttp extra with ranges, xmux, headers and download settings',
    () {
      final extra = jsonEncode({
        'xPaddingBytes': {'from': 100, 'to': 1000},
        'scMaxEachPostBytes': 1000000,
        'scMinPostsIntervalMs': {'from': 10, 'to': 10},
        'uplinkHTTPMethod': 'PUT',
        'sessionIDPlacement': 'header',
        'headers': {'X-Test': 'a'},
        'xmux': {
          'maxConcurrency': {'from': 16, 'to': 32},
          'cMaxReuseTimes': 0,
          'hKeepAlivePeriod': 30,
        },
        'downloadSettings': {
          'address': 'dl.example.com',
          'port': 8443,
          'security': 'reality',
          'realitySettings': {
            'publicKey': 'PUB',
            'shortId': 'ab',
            'serverName': 'cdn.example.com',
            'fingerprint': 'chrome',
          },
          'xhttpSettings': {
            'path': '/down',
            'host': 'd.example.com',
            'extra': {
              'xmux': {'maxConnections': '4'},
            },
          },
        },
      });
      final r = ShareLinkParser.parse(
        'vless://$uuid@example.com:443?security=tls&type=xhttp&path=%2Fx'
        '&extra=${Uri.encodeQueryComponent(extra)}#n',
      );
      expect(r.errors, isEmpty);
      final opts = r.proxies.single['xhttp-opts'] as Map;
      expect(opts['path'], '/x');
      expect(opts['x-padding-bytes'], '100-1000');
      expect(opts['sc-max-each-post-bytes'], '1000000');
      expect(opts['sc-min-posts-interval-ms'], '10');
      expect(opts['uplink-http-method'], 'PUT');
      expect(opts['session-placement'], 'header');
      expect(opts['headers'], {'X-Test': 'a'});
      expect(opts['reuse-settings'], {
        'max-concurrency': '16-32',
        'c-max-reuse-times': '0',
        'h-keep-alive-period': 30,
      });
      final ds = opts['download-settings'] as Map;
      expect(ds['server'], 'dl.example.com');
      expect(ds['port'], 8443);
      expect(ds['tls'], true);
      expect(ds['reality-opts'], {'public-key': 'PUB', 'short-id': 'ab'});
      expect(ds['servername'], 'cdn.example.com');
      expect(ds['path'], '/down');
      expect(ds['host'], 'd.example.com');
      expect(ds['reuse-settings'], {'max-connections': '4'});
    },
  );

  test('xhttp obfuscated padding gets Xray defaults in link and YAML', () {
    final link =
        ShareLinkParser.parse(
              'vless://$uuid@e.com:443?security=tls&type=xhttp&mode=stream-up'
              '&extra=%7B%22xPaddingObfsMode%22%3Atrue%2C%22xPaddingKey%22%3A%22k%22%7D#n',
            ).proxies.single['xhttp-opts']
            as Map;
    expect(link['x-padding-key'], 'k');
    expect(link['x-padding-header'], 'X-Padding');
    expect(link['x-padding-placement'], 'queryInHeader');
    expect(link['x-padding-method'], 'repeat-x');

    final yaml =
        ShareLinkParser.parse('''
proxies:
- name: a
  type: vless
  server: e.com
  port: 443
  uuid: $uuid
  network: xhttp
  xhttp-opts:
    path: /
    x-padding-obfs-mode: true
''').proxies.single['xhttp-opts']
            as Map;
    expect(yaml['x-padding-key'], 'x_padding');
    expect(yaml['x-padding-header'], 'X-Padding');

    final plain =
        ShareLinkParser.parse(
              'vless://$uuid@e.com:443?security=tls&type=xhttp#n',
            ).proxies.single['xhttp-opts']
            as Map;
    expect(plain.containsKey('x-padding-key'), isFalse);
  });

  test('vless xhttp extra that is not valid JSON is reported', () {
    final r = ShareLinkParser.parse(
      'vless://$uuid@example.com:443?security=tls&type=xhttp&extra=%7Bbroken#n',
    );
    expect(r.proxies, isEmpty);
    expect(r.errors.single, contains('invalid xhttp extra'));
  });

  test('vless xhttp extra encoded twice is still read', () {
    final extra = Uri.encodeComponent('{"xPaddingBytes":"1-2"}');
    final r = ShareLinkParser.parse(
      'vless://$uuid@example.com:443?security=tls&type=xhttp'
      '&extra=${Uri.encodeQueryComponent(extra)}#n',
    );
    expect(r.errors, isEmpty);
    expect((r.proxies.single['xhttp-opts'] as Map)['x-padding-bytes'], '1-2');
  });

  test('vless tcp http header becomes http network', () {
    final p = ShareLinkParser.parse(
      'vless://$uuid@e.com:33017?type=tcp&headerType=http&host=a.com&path=%2F#x',
    ).proxies.single;
    expect(p['network'], 'http');
    expect((p['http-opts'] as Map)['headers'], {
      'Host': ['a.com'],
    });
  });

  test('vless reality', () {
    final p = ShareLinkParser.parse(
      'vless://$uuid@e.com:443?security=reality&pbk=PUB&sid=ab&sni=s.com&flow=xtls-rprx-vision&type=tcp#r',
    ).proxies.single;
    expect(p['reality-opts'], {'public-key': 'PUB', 'short-id': 'ab'});
    expect(p['flow'], 'xtls-rprx-vision');
  });

  test('vmess base64 json', () {
    const json =
        '{"v":"2","ps":"vm","add":"e.com","port":"443","id":"$uuid","aid":"0","net":"ws","host":"h.com","path":"/p","tls":"tls","sni":"s.com"}';
    final b64 = base64Encode(utf8.encode(json));
    final p = ShareLinkParser.parse('vmess://$b64').proxies.single;
    expect(p['type'], 'vmess');
    expect(p['network'], 'ws');
    expect(p['tls'], true);
    expect((p['ws-opts'] as Map)['path'], '/p');
  });

  test('shadowsocks sip002', () {
    final cred = base64Encode(utf8.encode('aes-256-gcm:pass'));
    final p = ShareLinkParser.parse(
      'ss://$cred@1.2.3.4:8388#ss1',
    ).proxies.single;
    expect(p['type'], 'ss');
    expect(p['cipher'], 'aes-256-gcm');
    expect(p['password'], 'pass');
    expect(p['port'], 8388);
  });

  test('trojan, hysteria2, tuic, anytls', () {
    final r = ShareLinkParser.parse('''
trojan://pw@t.com:443?sni=t.com&type=ws&path=%2Fw#t
hy2://auth@h.com:8443?sni=h.com&insecure=1&obfs=salamander&obfs-password=o#h
tuic://$uuid:pw@u.com:443?congestion_control=bbr&alpn=h3&sni=u.com#u
anytls://pw@a.com:443?sni=a.com#a
''');
    expect(r.errors, isEmpty);
    expect(r.proxies.map((p) => p['type']), [
      'trojan',
      'hysteria2',
      'tuic',
      'anytls',
    ]);
    expect(r.proxies[1]['skip-cert-verify'], true);
    expect(r.proxies[1]['obfs-password'], 'o');
  });

  test('clash yaml proxy map and unsupported link', () {
    final y = ShareLinkParser.parse('''
proxies:
  - name: a
    type: vless
    server: s.com
    port: 1
    uuid: $uuid
''');
    expect(y.proxies.single['name'], 'a');
    final bad = ShareLinkParser.parse('foo://bar');
    expect(bad.proxies, isEmpty);
    expect(bad.errors, hasLength(1));
  });

  test('default profile merge dedupes and renames', () {
    final a = {'name': 'n', 'type': 'ss', 'server': 's', 'port': 1};
    final dup = {'name': 'other', 'type': 'ss', 'server': 's', 'port': 1};
    final clash = {'name': 'n', 'type': 'ss', 'server': 's2', 'port': 1};
    final m = DefaultProfileConfig.merge([a], [dup, clash]);
    expect(m.skipped, 1);
    expect(m.added, 1);
    expect(m.proxies.map((p) => p['name']), ['n', 'n (2)']);
    final yaml = DefaultProfileConfig.build(m.proxies);
    expect(DefaultProfileConfig.readProxies(yaml), hasLength(2));
  });
}
