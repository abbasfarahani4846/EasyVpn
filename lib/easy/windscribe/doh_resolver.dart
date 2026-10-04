import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Finds a server's real address over DNS-over-HTTPS. Some networks answer
/// ordinary DNS with a private address (for example 10.10.34.x) instead of the
/// real one; HTTPS to a resolver is not touched by that, so VPN servers stay
/// reachable.
class DohResolver {
  const DohResolver._();

  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  static bool isIp(String host) => _ipv4.hasMatch(host) || host.contains(':');

  /// True for private, loopback, link-local, CGNAT and benchmarking ranges: an
  /// answer in one of them means the DNS was tampered with.
  static bool isBogon(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((e) => e == null)) return true;
    final a = p[0]!;
    final b = p[1]!;
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 198 && (b == 18 || b == 19)) ||
        a >= 224;
  }

  /// First usable A record in a DoH JSON answer, else null.
  static String? parseAnswer(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      for (final record in (json['Answer'] as List? ?? const [])) {
        if (record is Map && record['type'] == 1) {
          final data = '${record['data']}';
          if (_ipv4.hasMatch(data) && !isBogon(data)) return data;
        }
      }
    } catch (_) {}
    return null;
  }

  static List<Uri> _endpoints(String host) {
    final h = Uri.encodeQueryComponent(host);
    return [
      Uri.parse('https://8.8.8.8/resolve?name=$h&type=A'),
      Uri.parse('https://8.8.4.4/resolve?name=$h&type=A'),
      Uri.parse('https://1.1.1.1/dns-query?name=$h&type=A'),
      Uri.parse('https://1.0.0.1/dns-query?name=$h&type=A'),
      Uri.parse('https://9.9.9.9:5053/dns-query?name=$h&type=A'),
    ];
  }

  static Future<String?> _ask(Uri uri, Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set('accept', 'application/dns-json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return parseAnswer(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The real IPv4 address of [host] (a name that is already an IP is
  /// returned as is), asking several resolvers at once; null when none of
  /// them gave a trustworthy answer.
  static Future<String?> resolve(
    String host, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (isIp(host)) return host;
    final done = Completer<String?>();
    var pending = 0;
    final endpoints = _endpoints(host);
    pending = endpoints.length;
    for (final uri in endpoints) {
      unawaited(
        _ask(uri, timeout).then((ip) {
          pending--;
          if (done.isCompleted) return;
          if (ip != null) {
            done.complete(ip);
          } else if (pending == 0) {
            done.complete(null);
          }
        }),
      );
    }
    return done.future;
  }
}
