import 'package:fl_clash/easy/windscribe/vpn_config_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _wg = '''
[Interface]
PrivateKey = cFJpdmF0ZUtleUZvclRlc3RpbmdPbmx5MTIzNDU2Nzg5MA=
Address = 100.64.1.2/32, fd00:64::2/128
DNS = 10.255.255.2
MTU = 1280

[Peer]
PublicKey = UHVibGljS2V5Rm9yVGVzdGluZ09ubHkxMjM0NTY3ODkwMTI=
PresharedKey = UHJlU2hhcmVkS2V5Rm9yVGVzdGluZzEyMzQ1Njc4OTAxMg==
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = de-001.example.net:443
PersistentKeepalive = 25
''';

const _ovpn = '''
client
dev tun
proto udp
remote de-001.example.net 443
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-GCM
auth SHA512
auth-user-pass
key-direction 1
verb 3
<ca>
-----BEGIN CERTIFICATE-----
Q0FGb3JUZXN0aW5n
-----END CERTIFICATE-----
</ca>
<tls-auth>
-----BEGIN OpenVPN Static key V1-----
00112233445566778899aabbccddeeff
-----END OpenVPN Static key V1-----
</tls-auth>
''';

void main() {
  test('wireguard conf becomes a wireguard proxy', () {
    final p = VpnConfigParser.parse(_wg, name: 'Germany');
    expect(p['type'], 'wireguard');
    expect(p['name'], 'Germany');
    expect(p['server'], 'de-001.example.net');
    expect(p['port'], 443);
    expect(p['ip'], '100.64.1.2');
    expect(p['ipv6'], 'fd00:64::2');
    expect(p['private-key'], startsWith('cFJpdmF0'));
    expect(p['public-key'], startsWith('UHVibGlj'));
    expect(p['pre-shared-key'], isNotNull);
    expect(p['allowed-ips'], ['0.0.0.0/0', '::/0']);
    expect(p['persistent-keepalive'], 25);
    expect(p['mtu'], 1280);
    expect(p['dns'], ['10.255.255.2']);
  });

  test('wireguard endpoint with an IPv6 literal', () {
    final p = VpnConfigParser.parseWireGuard(
      _wg.replaceFirst('de-001.example.net:443', '[2001:db8::1]:51820'),
    );
    expect(p['server'], '2001:db8::1');
    expect(p['port'], 51820);
  });

  test('openvpn keeps inline certificates, cipher, auth and credentials', () {
    final p = VpnConfigParser.parse(_ovpn, username: 'u123', password: 'p456');
    expect(p['type'], 'openvpn');
    expect(p['server'], 'de-001.example.net');
    expect(p['port'], 443);
    expect(p['proto'], 'udp');
    expect(p['cipher'], 'AES-256-GCM');
    expect(p['auth'], 'SHA512');
    expect(p['key-direction'], '1');
    expect((p['ca'] as String), contains('BEGIN CERTIFICATE'));
    expect((p['tls-auth'] as String), contains('Static key V1'));
    expect(p['username'], 'u123');
    expect(p['password'], 'p456');
  });

  test('openvpn without credentials is refused with a clear message', () {
    expect(
      () => VpnConfigParser.parse(_ovpn),
      throwsA(
        isA<VpnConfigException>().having(
          (e) => e.message,
          'message',
          contains('username and password'),
        ),
      ),
    );
  });

  test('typed credentials are used even without an auth-user-pass line', () {
    final noLine = _ovpn.replaceFirst('auth-user-pass\n', '');
    final withCreds = VpnConfigParser.parse(
      noLine,
      username: 'u',
      password: 'p',
    );
    expect(withCreds['username'], 'u');
    expect(withCreds['password'], 'p');
    final without = VpnConfigParser.parse(noLine);
    expect(without.containsKey('username'), isFalse);
  });

  test('openvpn pointing at separate files is refused', () {
    final split = _ovpn.replaceAll(RegExp(r'<ca>[\s\S]*?</ca>'), 'ca ca.crt');
    expect(
      () => VpnConfigParser.parse(split, username: 'a', password: 'b'),
      throwsA(isA<VpnConfigException>()),
    );
  });

  test('comp-lzo, tcp and keepalive are read', () {
    final p = VpnConfigParser.parse(
      '${_ovpn.replaceFirst('proto udp', 'proto tcp-client')}\ncomp-lzo\nkeepalive 10 60\n',
      username: 'a',
      password: 'b',
    );
    expect(p['proto'], 'tcp-client');
    expect(p['comp-lzo'], 'yes');
    expect(p['ping'], 10);
    expect(p['ping-restart'], 60);
  });

  test('unknown text is rejected', () {
    expect(
      () => VpnConfigParser.parse('hello world'),
      throwsA(isA<VpnConfigException>()),
    );
  });
}
