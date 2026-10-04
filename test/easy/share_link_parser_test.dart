import 'dart:convert';
import 'package:fl_clash/easy/single_config/default_profile_config.dart';
import 'package:fl_clash/easy/single_config/share_link_parser.dart';
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
