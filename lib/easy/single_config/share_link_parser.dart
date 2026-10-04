import 'dart:convert';

import 'package:yaml/yaml.dart';

class ShareLinkParseResult {
  final List<Map<String, Object?>> proxies;
  final List<String> errors;

  const ShareLinkParseResult(this.proxies, this.errors);
}

/// Turns pasted text into mihomo proxy maps. Accepts share links (one per
/// line, or a base64 blob of them), a Clash/mihomo YAML with `proxies:`, or a
/// single proxy map/JSON object of any type mihomo understands.
class ShareLinkParser {
  const ShareLinkParser._();

  static ShareLinkParseResult parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const ShareLinkParseResult([], []);

    final structured = _parseStructured(trimmed);
    if (structured != null) return ShareLinkParseResult(structured, const []);

    var content = trimmed;
    if (!content.contains('://')) {
      final decoded = _tryBase64(content);
      if (decoded != null && decoded.contains('://')) content = decoded;
    }

    final proxies = <Map<String, Object?>>[];
    final errors = <String>[];
    for (final raw in content.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      try {
        final proxy = _parseLink(line);
        if (proxy == null) {
          errors.add('Unsupported link: ${_shorten(line)}');
        } else {
          proxies.add(proxy);
        }
      } catch (e) {
        errors.add('${_shorten(line)} -> $e');
      }
    }
    return ShareLinkParseResult(proxies, errors);
  }

  static List<Map<String, Object?>>? _parseStructured(String text) {
    final looksStructured =
        text.startsWith('{') ||
        text.startsWith('[') ||
        text.startsWith('proxies:') ||
        text.startsWith('- ') ||
        RegExp(r'^\s*(name|type)\s*:', multiLine: true).hasMatch(text);
    if (!looksStructured || text.contains('://') && !text.contains(': ')) {
      return null;
    }
    Object? doc;
    try {
      doc = _plain(loadYaml(text));
    } catch (_) {
      return null;
    }
    List? list;
    if (doc is Map && doc['proxies'] is List) {
      list = doc['proxies'] as List;
    } else if (doc is Map && doc['type'] != null) {
      list = [doc];
    } else if (doc is List) {
      list = doc;
    }
    if (list == null) return null;
    final result = <Map<String, Object?>>[];
    for (final item in list) {
      if (item is Map && item['type'] != null && item['server'] != null) {
        result.add(Map<String, Object?>.from(item));
      }
    }
    return result.isEmpty ? null : result;
  }

  static Map<String, Object?>? _parseLink(String line) {
    final schemeEnd = line.indexOf('://');
    if (schemeEnd <= 0) return null;
    final scheme = line.substring(0, schemeEnd).toLowerCase();
    switch (scheme) {
      case 'vless':
        return _parseVlessLike(line, 'vless');
      case 'vmess':
        return _parseVmess(line);
      case 'trojan':
        return _parseTrojan(line);
      case 'ss':
        return _parseShadowsocks(line);
      case 'hysteria2':
      case 'hy2':
        return _parseHysteria2(line);
      case 'tuic':
        return _parseTuic(line);
      case 'anytls':
        return _parseAnytls(line);
      default:
        return null;
    }
  }

  static Map<String, Object?> _parseVlessLike(String line, String type) {
    final uri = Uri.parse(line);
    final query = uri.queryParameters;
    _requireEndpoint(uri);
    final proxy = <String, Object?>{
      'name': _name(uri),
      'type': type,
      'server': uri.host,
      'port': uri.port,
      'uuid': Uri.decodeComponent(uri.userInfo),
      'udp': true,
    };
    _applyTls(proxy, query);
    final flow = query['flow'];
    if (flow != null && flow.isNotEmpty) proxy['flow'] = flow.toLowerCase();
    final encryption = query['encryption'];
    if (encryption != null && encryption.isNotEmpty) {
      proxy['encryption'] = encryption;
    }
    switch (query['packetEncoding']) {
      case 'none':
        break;
      case 'packet':
        proxy['packet-addr'] = true;
      default:
        proxy['xudp'] = true;
    }
    _applyTransport(proxy, query);
    return proxy;
  }

  static Map<String, Object?> _parseTrojan(String line) {
    final uri = Uri.parse(line);
    final query = uri.queryParameters;
    _requireEndpoint(uri);
    final proxy = <String, Object?>{
      'name': _name(uri),
      'type': 'trojan',
      'server': uri.host,
      'port': uri.port,
      'password': Uri.decodeComponent(uri.userInfo),
      'udp': true,
    };
    final security = (query['security'] ?? 'tls').toLowerCase();
    if (security == 'reality') {
      _applyTls(proxy, query);
    } else {
      final sni = query['sni'] ?? query['peer'];
      if (sni != null && sni.isNotEmpty) proxy['sni'] = sni;
      final alpn = query['alpn'];
      if (alpn != null && alpn.isNotEmpty) proxy['alpn'] = alpn.split(',');
      final fp = query['fp'];
      if (fp != null && fp.isNotEmpty) proxy['client-fingerprint'] = fp;
      if (_truthy(query['allowInsecure']) || _truthy(query['insecure'])) {
        proxy['skip-cert-verify'] = true;
      }
    }
    _applyTransport(proxy, query);
    return proxy;
  }

  static Map<String, Object?> _parseVmess(String line) {
    final body = line.substring('vmess://'.length);
    final hashIndex = body.indexOf('#');
    final payload = hashIndex == -1 ? body : body.substring(0, hashIndex);
    final decoded = _tryBase64(payload.split('?').first);
    if (decoded == null || !decoded.trimLeft().startsWith('{')) {
      return _parseVlessLike(line, 'vmess');
    }
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final server = '${json['add'] ?? ''}';
    final port = int.tryParse('${json['port'] ?? ''}');
    if (server.isEmpty || port == null) {
      throw const FormatException('missing server or port');
    }
    final proxy = <String, Object?>{
      'name': '${json['ps'] ?? '$server:$port'}',
      'type': 'vmess',
      'server': server,
      'port': port,
      'uuid': '${json['id'] ?? ''}',
      'alterId': int.tryParse('${json['aid'] ?? 0}') ?? 0,
      'cipher': (json['scy'] == null || '${json['scy']}'.isEmpty)
          ? 'auto'
          : '${json['scy']}',
      'udp': true,
      'xudp': true,
    };
    final tls = '${json['tls'] ?? ''}'.toLowerCase();
    if (tls == 'tls' || tls == '1' || tls == 'true') {
      proxy['tls'] = true;
      final sni = '${json['sni'] ?? ''}';
      if (sni.isNotEmpty) proxy['servername'] = sni;
      final alpn = '${json['alpn'] ?? ''}';
      if (alpn.isNotEmpty) proxy['alpn'] = alpn.split(',');
      final fp = '${json['fp'] ?? ''}';
      if (fp.isNotEmpty) proxy['client-fingerprint'] = fp;
    }
    final query = <String, String>{
      'type': '${json['net'] ?? 'tcp'}',
      'headerType': '${json['type'] ?? ''}',
      'host': '${json['host'] ?? ''}',
      'path': '${json['path'] ?? ''}',
      'serviceName': '${json['path'] ?? ''}',
    };
    _applyTransport(proxy, query);
    return proxy;
  }

  static Map<String, Object?> _parseShadowsocks(String line) {
    var body = line.substring('ss://'.length);
    var name = '';
    final hashIndex = body.indexOf('#');
    if (hashIndex != -1) {
      name = Uri.decodeComponent(body.substring(hashIndex + 1));
      body = body.substring(0, hashIndex);
    }
    var queryString = '';
    final queryIndex = body.indexOf('?');
    if (queryIndex != -1) {
      queryString = body.substring(queryIndex + 1);
      body = body.substring(0, queryIndex);
    }
    body = body.replaceAll(RegExp(r'/+$'), '');

    String credentials;
    String hostPort;
    final at = body.lastIndexOf('@');
    if (at == -1) {
      final decoded = _tryBase64(body);
      if (decoded == null || !decoded.contains('@')) {
        throw const FormatException('invalid ss link');
      }
      final i = decoded.lastIndexOf('@');
      credentials = decoded.substring(0, i);
      hostPort = decoded.substring(i + 1);
    } else {
      credentials = body.substring(0, at);
      hostPort = body.substring(at + 1);
      if (!credentials.contains(':')) {
        credentials = _tryBase64(credentials) ?? credentials;
      } else {
        credentials = Uri.decodeComponent(credentials);
      }
    }
    final colon = credentials.indexOf(':');
    if (colon == -1) throw const FormatException('invalid ss credentials');
    final cipher = credentials.substring(0, colon);
    final password = credentials.substring(colon + 1);
    final hp = Uri.parse('ss://$hostPort');
    if (hp.host.isEmpty || !hp.hasPort) {
      throw const FormatException('missing server or port');
    }
    final proxy = <String, Object?>{
      'name': name.isEmpty ? '${hp.host}:${hp.port}' : name,
      'type': 'ss',
      'server': hp.host,
      'port': hp.port,
      'cipher': cipher,
      'password': password,
      'udp': true,
    };
    if (queryString.isNotEmpty) {
      final plugin = Uri.splitQueryString(queryString)['plugin'];
      if (plugin != null && plugin.isNotEmpty) _applySsPlugin(proxy, plugin);
    }
    return proxy;
  }

  static void _applySsPlugin(Map<String, Object?> proxy, String plugin) {
    final parts = plugin.split(';');
    final opts = <String, String>{};
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq == -1) {
        opts[p] = 'true';
      } else {
        opts[p.substring(0, eq)] = p.substring(eq + 1);
      }
    }
    final pluginName = parts.first;
    if (pluginName.contains('obfs')) {
      proxy['plugin'] = 'obfs';
      proxy['plugin-opts'] = {
        'mode': opts['obfs'] ?? 'http',
        if (opts['obfs-host'] != null) 'host': opts['obfs-host'],
      };
    } else if (pluginName.contains('v2ray-plugin')) {
      proxy['plugin'] = 'v2ray-plugin';
      proxy['plugin-opts'] = {
        'mode': opts['mode'] ?? 'websocket',
        if (opts.containsKey('tls')) 'tls': true,
        if (opts['host'] != null) 'host': opts['host'],
        if (opts['path'] != null) 'path': opts['path'],
      };
    } else if (pluginName.contains('shadow-tls')) {
      proxy['plugin'] = 'shadow-tls';
      proxy['plugin-opts'] = {
        'host': opts['host'] ?? '',
        'password': opts['password'] ?? '',
        'version': int.tryParse(opts['version'] ?? '') ?? 2,
      };
    }
  }

  static Map<String, Object?> _parseHysteria2(String line) {
    final uri = Uri.parse(line.replaceFirst(RegExp('^hy2://'), 'hysteria2://'));
    final query = uri.queryParameters;
    if (uri.host.isEmpty) throw const FormatException('missing server');
    final proxy = <String, Object?>{
      'name': _name(uri),
      'type': 'hysteria2',
      'server': uri.host,
      'port': uri.hasPort ? uri.port : 443,
      'password': Uri.decodeComponent(uri.userInfo),
    };
    final sni = query['sni'];
    if (sni != null && sni.isNotEmpty) proxy['sni'] = sni;
    if (_truthy(query['insecure'])) proxy['skip-cert-verify'] = true;
    final obfs = query['obfs'];
    if (obfs != null && obfs.isNotEmpty) {
      proxy['obfs'] = obfs;
      proxy['obfs-password'] = query['obfs-password'] ?? '';
    }
    final pin = query['pinSHA256'];
    if (pin != null && pin.isNotEmpty) proxy['fingerprint'] = pin;
    final mport = query['mport'];
    if (mport != null && mport.isNotEmpty) proxy['ports'] = mport;
    final alpn = query['alpn'];
    if (alpn != null && alpn.isNotEmpty) proxy['alpn'] = alpn.split(',');
    return proxy;
  }

  static Map<String, Object?> _parseTuic(String line) {
    final uri = Uri.parse(line);
    final query = uri.queryParameters;
    _requireEndpoint(uri);
    final colon = uri.userInfo.indexOf(':');
    final proxy = <String, Object?>{
      'name': _name(uri),
      'type': 'tuic',
      'server': uri.host,
      'port': uri.port,
      'uuid': colon == -1 ? uri.userInfo : uri.userInfo.substring(0, colon),
      'password': colon == -1
          ? ''
          : Uri.decodeComponent(uri.userInfo.substring(colon + 1)),
      'alpn': (query['alpn'] ?? 'h3').split(','),
      'udp-relay-mode': query['udp_relay_mode'] ?? 'native',
      'congestion-controller': query['congestion_control'] ?? 'bbr',
    };
    final sni = query['sni'];
    if (sni != null && sni.isNotEmpty) proxy['sni'] = sni;
    if (_truthy(query['allow_insecure']) || _truthy(query['insecure'])) {
      proxy['skip-cert-verify'] = true;
    }
    return proxy;
  }

  static Map<String, Object?> _parseAnytls(String line) {
    final uri = Uri.parse(line);
    final query = uri.queryParameters;
    _requireEndpoint(uri);
    final proxy = <String, Object?>{
      'name': _name(uri),
      'type': 'anytls',
      'server': uri.host,
      'port': uri.port,
      'password': Uri.decodeComponent(uri.userInfo),
      'udp': true,
    };
    final sni = query['sni'];
    if (sni != null && sni.isNotEmpty) proxy['sni'] = sni;
    if (_truthy(query['insecure'])) proxy['skip-cert-verify'] = true;
    final alpn = query['alpn'];
    if (alpn != null && alpn.isNotEmpty) proxy['alpn'] = alpn.split(',');
    final fp = query['fp'];
    if (fp != null && fp.isNotEmpty) proxy['client-fingerprint'] = fp;
    return proxy;
  }

  static void _applyTls(Map<String, Object?> proxy, Map<String, String> q) {
    final security = (q['security'] ?? '').toLowerCase();
    if (security.endsWith('tls') || security == 'reality') {
      proxy['tls'] = true;
      final fp = q['fp'];
      proxy['client-fingerprint'] = (fp == null || fp.isEmpty) ? 'chrome' : fp;
      final alpn = q['alpn'];
      if (alpn != null && alpn.isNotEmpty) proxy['alpn'] = alpn.split(',');
      final pcs = q['pcs'];
      if (pcs != null && pcs.isNotEmpty) proxy['fingerprint'] = pcs;
      if (_truthy(q['allowInsecure']) || _truthy(q['insecure'])) {
        proxy['skip-cert-verify'] = true;
      }
    }
    final sni = q['sni'];
    if (sni != null && sni.isNotEmpty) proxy['servername'] = sni;
    final pbk = q['pbk'];
    if (pbk != null && pbk.isNotEmpty) {
      proxy['reality-opts'] = {
        'public-key': pbk,
        'short-id': q['sid'] ?? '',
        if (q['support-x25519mlkem768'] != null)
          'support-x25519mlkem768': _truthy(q['support-x25519mlkem768']),
      };
    }
  }

  static void _applyTransport(Map<String, Object?> proxy, Map<String, String> q) {
    var network = (q['type'] ?? '').toLowerCase();
    if (network.isEmpty) network = 'tcp';
    final headerType = (q['headerType'] ?? '').toLowerCase();
    if (network == 'tcp' && headerType == 'http') {
      network = 'http';
    } else if (network == 'http') {
      network = 'h2';
    }
    final host = q['host'] ?? '';
    final path = q['path'] ?? '';
    switch (network) {
      case 'tcp':
        proxy['network'] = 'tcp';
      case 'http':
        proxy['network'] = 'http';
        proxy['http-opts'] = {
          'path': [path.isEmpty ? '/' : path],
          if (host.isNotEmpty) 'headers': {'Host': [host]},
          if ((q['method'] ?? '').isNotEmpty) 'method': q['method'],
        };
      case 'h2':
        proxy['network'] = 'h2';
        proxy['h2-opts'] = {
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': [host],
        };
      case 'ws':
      case 'httpupgrade':
        proxy['network'] = network == 'ws' ? 'ws' : 'httpupgrade';
        final opts = <String, Object?>{
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
        final ed = int.tryParse(q['ed'] ?? '');
        if (ed != null) {
          if (network == 'ws') {
            opts['max-early-data'] = ed;
            opts['early-data-header-name'] = 'Sec-WebSocket-Protocol';
          } else {
            opts['v2ray-http-upgrade-fast-open'] = true;
          }
        }
        if ((q['eh'] ?? '').isNotEmpty) {
          opts['early-data-header-name'] = q['eh'];
        }
        proxy['ws-opts'] = opts;
      case 'grpc':
        proxy['network'] = 'grpc';
        proxy['grpc-opts'] = {'grpc-service-name': q['serviceName'] ?? ''};
      case 'xhttp':
        proxy['network'] = 'xhttp';
        final opts = <String, Object?>{
          if (path.isNotEmpty) 'path': path,
          if (host.isNotEmpty) 'host': host,
          if ((q['mode'] ?? '').isNotEmpty) 'mode': q['mode'],
        };
        final extra = q['extra'];
        if (extra != null && extra.isNotEmpty) {
          try {
            _applyXhttpExtra(jsonDecode(extra) as Map<String, dynamic>, opts);
          } catch (_) {}
        }
        proxy['xhttp-opts'] = opts;
      default:
        proxy['network'] = network;
    }
  }

  static const _xhttpExtraKeys = {
    'xPaddingBytes': 'x-padding-bytes',
    'xPaddingObfsMode': 'x-padding-obfs-mode',
    'xPaddingKey': 'x-padding-key',
    'xPaddingHeader': 'x-padding-header',
    'xPaddingPlacement': 'x-padding-placement',
    'xPaddingMethod': 'x-padding-method',
    'noGRPCHeader': 'no-grpc-header',
    'scMaxEachPostBytes': 'sc-max-each-post-bytes',
    'scMinPostsIntervalMs': 'sc-min-posts-interval-ms',
  };

  static void _applyXhttpExtra(
    Map<String, dynamic> extra,
    Map<String, Object?> opts,
  ) {
    extra.forEach((key, value) {
      final mapped = _xhttpExtraKeys[key];
      if (mapped != null) opts[mapped] = value;
    });
  }

  static void _requireEndpoint(Uri uri) {
    if (uri.host.isEmpty) throw const FormatException('missing server');
    if (!uri.hasPort) throw const FormatException('missing port');
  }

  static String _name(Uri uri) {
    var fragment = uri.fragment;
    try {
      fragment = Uri.decodeComponent(fragment);
    } catch (_) {}
    return fragment.isEmpty ? '${uri.host}:${uri.port}' : fragment;
  }

  static bool _truthy(String? value) {
    final v = value?.toLowerCase();
    return v == '1' || v == 'true';
  }

  static String? _tryBase64(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) return null;
    try {
      final normalized = cleaned.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64.decode(padded));
    } catch (_) {
      return null;
    }
  }

  static String _shorten(String line) =>
      line.length <= 48 ? line : '${line.substring(0, 48)}...';

  static Object? _plain(Object? node) {
    if (node is YamlMap) {
      return {for (final e in node.entries) '${e.key}': _plain(e.value)};
    }
    if (node is YamlList) return [for (final e in node) _plain(e)];
    return node;
  }
}
