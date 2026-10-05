import 'dart:async';
import 'dart:io';

import 'package:yaml/yaml.dart';

typedef EndpointProbe =
    Future<bool> Function(
      String host,
      int port, {
      required bool tls,
      String? sni,
    });

class EndpointRepair {
  final String name;
  final String server;
  final int from;
  final int to;

  const EndpointRepair(this.name, this.server, this.from, this.to);
}

class EndpointFailure {
  final String name;
  final String server;
  final List<int> tried;

  const EndpointFailure(this.name, this.server, this.tried);

  @override
  String toString() => '$name: $server not reachable on ${tried.join(', ')}';
}

class EndpointHealReport {
  final String yaml;
  final List<EndpointRepair> repaired;
  final List<EndpointFailure> failed;

  const EndpointHealReport(this.yaml, this.repaired, this.failed);

  bool get changed => repaired.isNotEmpty;
}

/// Probes every TCP-based server of a profile; one that does not answer on
/// its own port is moved to the first fallback port that does, and one that
/// answers on none is reported instead of silently left dead.
class EndpointHealer {
  const EndpointHealer._();

  static const fallbackPorts = [1001];

  static const _tcpTypes = {
    'vless',
    'vmess',
    'trojan',
    'ss',
    'ssr',
    'anytls',
    'http',
    'socks5',
    'snell',
  };

  static Future<bool> tcpProbe(
    String host,
    int port, {
    required bool tls,
    String? sni,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!await _connects(host, port, timeout)) return false;
    if (!tls) return true;
    // A bare handshake is what the system resolver cannot stall; the SNI
    // variant only runs for a server that refused it, because Dart looks the
    // name up and a broken DNS would hold every probe for the full timeout.
    if (await _handshake(host, port, null, timeout)) return true;
    return sni != null &&
        sni.isNotEmpty &&
        await _handshake(host, port, sni, timeout);
  }

  static Future<bool> _connects(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _handshake(
    String host,
    int port,
    String? sni,
    Duration timeout,
  ) async {
    final Socket raw;
    try {
      raw = await Socket.connect(host, port, timeout: timeout);
    } catch (_) {
      return false;
    }
    try {
      final secure = await SecureSocket.secure(
        raw,
        host: sni,
        onBadCertificate: (_) => true,
      ).timeout(timeout);
      secure.destroy();
      return true;
    } catch (_) {
      return false;
    } finally {
      raw.destroy();
    }
  }

  static Future<EndpointHealReport> heal(
    String yaml, {
    EndpointProbe probe = tcpProbe,
    List<int> fallbacks = fallbackPorts,
    int concurrency = 6,
  }) async {
    final YamlNode root;
    try {
      root = loadYamlNode(yaml);
    } catch (_) {
      return EndpointHealReport(yaml, const [], const []);
    }
    final proxies = root is YamlMap ? root.nodes['proxies'] : null;
    if (proxies is! YamlList) {
      return EndpointHealReport(yaml, const [], const []);
    }

    final targets = <_Target>[];
    for (final node in proxies.nodes) {
      final target = node is YamlMap ? _Target.of(node) : null;
      if (target != null) targets.add(target);
    }

    final answers = <String, Future<int?>>{};
    final pool = _Pool(concurrency);
    Future<int?> resolve(_Target t) => answers.putIfAbsent(
      t.key,
      () => pool.run(() async {
        for (final port in [t.port, ...fallbacks.where((p) => p != t.port)]) {
          if (await probe(t.server, port, tls: t.tls, sni: t.sni)) return port;
        }
        return null;
      }),
    );

    final results = await Future.wait([for (final t in targets) resolve(t)]);
    final repaired = <EndpointRepair>[];
    final failed = <EndpointFailure>[];
    final edits = <_Edit>[];
    for (var i = 0; i < targets.length; i++) {
      final t = targets[i];
      final answer = results[i];
      if (answer == null) {
        failed.add(
          EndpointFailure(t.name, t.server, [
            t.port,
            ...fallbacks.where((p) => p != t.port),
          ]),
        );
      } else if (answer != t.port) {
        repaired.add(EndpointRepair(t.name, t.server, t.port, answer));
        edits.add(_Edit(t.portStart, t.portEnd, '$answer'));
      }
    }
    if (edits.isEmpty) return EndpointHealReport(yaml, repaired, failed);

    final patched = StringBuffer();
    var cursor = 0;
    edits.sort((a, b) => a.start.compareTo(b.start));
    for (final edit in edits) {
      patched
        ..write(yaml.substring(cursor, edit.start))
        ..write(edit.text);
      cursor = edit.end;
    }
    patched.write(yaml.substring(cursor));
    return EndpointHealReport(patched.toString(), repaired, failed);
  }
}

class _Edit {
  final int start;
  final int end;
  final String text;

  const _Edit(this.start, this.end, this.text);
}

class _Target {
  final String name;
  final String server;
  final int port;
  final bool tls;
  final String? sni;
  final int portStart;
  final int portEnd;

  const _Target(
    this.name,
    this.server,
    this.port,
    this.tls,
    this.sni,
    this.portStart,
    this.portEnd,
  );

  String get key => '$server:$port:$tls:$sni';

  static _Target? of(YamlMap map) {
    final type = '${map['type']}'.toLowerCase();
    final server = map['server'];
    final portNode = map.nodes['port'];
    if (!EndpointHealer._tcpTypes.contains(type) ||
        server is! String ||
        server.isEmpty ||
        portNode is! YamlScalar ||
        portNode.value is! int ||
        map['dialer-proxy'] != null) {
      return null;
    }
    final tls = map['tls'] == true || type == 'trojan' || type == 'anytls';
    final sni = (map['servername'] ?? map['sni'])?.toString();
    return _Target(
      '${map['name']}',
      server,
      portNode.value as int,
      tls,
      sni,
      portNode.span.start.offset,
      portNode.span.end.offset,
    );
  }
}

class _Pool {
  final int size;
  int _active = 0;
  final _waiting = <Completer<void>>[];

  _Pool(this.size);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= size) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}
