/// Reads the files Windscribe's Config Generator (and most providers) hand out
/// and turns them into mihomo proxies: OpenVPN `.ovpn` and WireGuard
/// wg-quick `.conf`. IKEv2 has no counterpart in the core.
class VpnConfigException implements Exception {
  final String message;

  const VpnConfigException(this.message);

  @override
  String toString() => message;
}

class VpnConfigParser {
  const VpnConfigParser._();

  static bool looksLikeWireGuard(String text) => RegExp(
    r'^\s*\[Interface\]',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(text);

  static bool looksLikeOpenVpn(String text) =>
      RegExp(r'^\s*(remote|client)\b', multiLine: true).hasMatch(text) &&
      !looksLikeWireGuard(text);

  /// [name] defaults to the server address. [username] and [password] are the
  /// OpenVPN credentials (Windscribe: "Get Credentials").
  static Map<String, Object?> parse(
    String text, {
    String? name,
    String? username,
    String? password,
  }) {
    if (looksLikeWireGuard(text)) return parseWireGuard(text, name: name);
    if (looksLikeOpenVpn(text)) {
      return parseOpenVpn(
        text,
        name: name,
        username: username,
        password: password,
      );
    }
    throw const VpnConfigException(
      'Not an OpenVPN (.ovpn) or WireGuard (.conf) config',
    );
  }

  // ---------------------------------------------------------------- WireGuard

  static Map<String, Object?> parseWireGuard(String text, {String? name}) {
    final sections = <String, Map<String, String>>{};
    Map<String, String>? current;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      final header = RegExp(r'^\[(\w+)\]$').firstMatch(line);
      if (header != null) {
        current = sections.putIfAbsent(
          header.group(1)!.toLowerCase(),
          () => <String, String>{},
        );
        continue;
      }
      final eq = line.indexOf('=');
      if (current == null || eq == -1) continue;
      current[line.substring(0, eq).trim().toLowerCase()] = line
          .substring(eq + 1)
          .trim();
    }
    final iface = sections['interface'];
    final peer = sections['peer'];
    if (iface == null || peer == null) {
      throw const VpnConfigException(
        'WireGuard config needs [Interface] and [Peer]',
      );
    }
    final privateKey = iface['privatekey'];
    final publicKey = peer['publickey'];
    final endpoint = peer['endpoint'];
    if (privateKey == null || publicKey == null || endpoint == null) {
      throw const VpnConfigException(
        'WireGuard config is missing PrivateKey, PublicKey or Endpoint',
      );
    }
    final (host, port) = _hostPort(endpoint);

    String? v4;
    String? v6;
    for (final address in (iface['address'] ?? '').split(',')) {
      final ip = address.trim().split('/').first;
      if (ip.isEmpty) continue;
      if (ip.contains(':')) {
        v6 ??= ip;
      } else {
        v4 ??= ip;
      }
    }
    final dns = [
      for (final d in (iface['dns'] ?? '').split(','))
        if (d.trim().isNotEmpty) d.trim(),
    ];
    final mtu = int.tryParse(iface['mtu'] ?? '');
    final keepalive = int.tryParse(peer['persistentkeepalive'] ?? '');
    final allowed = [
      for (final a in (peer['allowedips'] ?? '0.0.0.0/0, ::/0').split(','))
        if (a.trim().isNotEmpty) a.trim(),
    ];
    return {
      'name': name ?? 'WireGuard $host',
      'type': 'wireguard',
      'server': host,
      'port': port,
      'ip': ?v4,
      'ipv6': ?v6,
      'private-key': privateKey,
      'public-key': publicKey,
      if (peer['presharedkey'] != null) 'pre-shared-key': peer['presharedkey'],
      'allowed-ips': allowed,
      if (keepalive != null && keepalive > 0) 'persistent-keepalive': keepalive,
      'mtu': ?mtu,
      'udp': true,
      'remote-dns-resolve': true,
      'dns': dns.isEmpty ? ['1.1.1.1', '8.8.8.8'] : dns,
    };
  }

  static (String, int) _hostPort(String endpoint) {
    final v6 = RegExp(r'^\[(.+)\]:(\d+)$').firstMatch(endpoint);
    if (v6 != null) return (v6.group(1)!, int.parse(v6.group(2)!));
    final i = endpoint.lastIndexOf(':');
    if (i == -1) throw const VpnConfigException('Endpoint needs host:port');
    final port = int.tryParse(endpoint.substring(i + 1));
    if (port == null) {
      throw const VpnConfigException('Endpoint port is not a number');
    }
    return (endpoint.substring(0, i), port);
  }

  // ------------------------------------------------------------------ OpenVPN

  static const _blocks = [
    'ca',
    'cert',
    'key',
    'tls-auth',
    'tls-crypt',
    'tls-crypt-v2',
  ];

  static Map<String, Object?> parseOpenVpn(
    String text, {
    String? name,
    String? username,
    String? password,
  }) {
    final blocks = <String, String>{};
    var rest = text;
    for (final tag in _blocks) {
      final m = RegExp(
        '<$tag>\\s*([\\s\\S]*?)\\s*</$tag>',
        caseSensitive: false,
      ).firstMatch(rest);
      if (m != null) {
        blocks[tag] = '${m.group(1)!.trim()}\n';
        rest = rest.replaceRange(m.start, m.end, '');
      }
    }

    String? host;
    int? port;
    String? proto;
    String? dev;
    String? cipher;
    List<String>? dataCiphers;
    String? fallback;
    String? auth;
    String? lzo;
    String? keyDirection;
    var needsCredentials = false;
    int? ping;
    int? pingRestart;
    final externalFiles = <String>[];

    for (final raw in rest.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      final directive = parts.first.toLowerCase();
      final args = parts.skip(1).toList();
      switch (directive) {
        case 'remote':
          if (host == null && args.isNotEmpty) {
            host = args[0];
            if (args.length > 1) port = int.tryParse(args[1]);
            if (args.length > 2) proto ??= args[2];
          }
        case 'proto':
          if (args.isNotEmpty) proto = args[0];
        case 'dev':
          if (args.isNotEmpty) dev = args[0];
        case 'cipher':
          if (args.isNotEmpty) cipher = args[0];
        case 'data-ciphers' || 'ncp-ciphers':
          if (args.isNotEmpty) dataCiphers = args[0].split(':');
        case 'data-ciphers-fallback':
          if (args.isNotEmpty) fallback = args[0];
        case 'auth':
          if (args.isNotEmpty) auth = args[0];
        case 'comp-lzo':
          lzo = args.isEmpty ? 'yes' : args[0];
        case 'key-direction':
          if (args.isNotEmpty) keyDirection = args[0];
        case 'auth-user-pass':
          needsCredentials = true;
        case 'ping':
          ping = int.tryParse(args.firstOrNull ?? '');
        case 'ping-restart':
          pingRestart = int.tryParse(args.firstOrNull ?? '');
        case 'keepalive':
          if (args.length >= 2) {
            ping = int.tryParse(args[0]);
            pingRestart = int.tryParse(args[1]);
          }
        case 'ca' || 'cert' || 'key' || 'tls-crypt' || 'tls-crypt-v2':
          if (!blocks.containsKey(directive)) externalFiles.add(directive);
        case 'tls-auth':
          if (!blocks.containsKey('tls-auth')) externalFiles.add('tls-auth');
          if (args.length > 1) keyDirection ??= args[1];
      }
    }

    if (host == null || port == null) {
      throw const VpnConfigException(
        'OpenVPN config has no "remote host port" line',
      );
    }
    if (externalFiles.isNotEmpty) {
      throw VpnConfigException(
        'This .ovpn points to separate files (${externalFiles.toSet().join(', ')}). '
        'Download the single-file version with the certificates inside.',
      );
    }
    if (!blocks.containsKey('ca')) {
      throw const VpnConfigException('OpenVPN config has no <ca> certificate');
    }
    if (needsCredentials &&
        (username == null ||
            username.isEmpty ||
            password == null ||
            password.isEmpty)) {
      throw const VpnConfigException(
        'This config needs a username and password (Windscribe: "Get Credentials")',
      );
    }
    return {
      'name': name ?? 'OpenVPN $host',
      'type': 'openvpn',
      'server': host,
      'port': port,
      'proto': ?proto,
      'dev': ?dev,
      'cipher': ?cipher,
      'data-ciphers': ?dataCiphers,
      'data-ciphers-fallback': ?fallback,
      'auth': ?auth,
      'comp-lzo': ?lzo,
      'ca': blocks['ca'],
      if (blocks.containsKey('cert')) 'cert': blocks['cert'],
      if (blocks.containsKey('key')) 'key': blocks['key'],
      if (blocks.containsKey('tls-auth')) 'tls-auth': blocks['tls-auth'],
      'key-direction': ?keyDirection,
      if (blocks.containsKey('tls-crypt')) 'tls-crypt': blocks['tls-crypt'],
      if (blocks.containsKey('tls-crypt-v2'))
        'tls-crypt-v2': blocks['tls-crypt-v2'],
      if (needsCredentials) 'username': username,
      if (needsCredentials) 'password': password,
      'ping': ?ping,
      'ping-restart': ?pingRestart,
      'udp': true,
      'remote-dns-resolve': true,
      'dns': ['1.1.1.1', '8.8.8.8'],
    };
  }
}
