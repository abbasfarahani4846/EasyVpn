import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum LinkState { verified, unchanged, mismatch, noAnswer }

/// Decides whether a connection really works by comparing the IP the
/// internet sees through the proxy (the core's own listener) with the IP the
/// system itself gets, and with the IP before connecting.
class ConnectionVerifier {
  const ConnectionVerifier._();

  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static final _ipv6 = RegExp(r'^[0-9a-fA-F:]+$');

  static bool looksLikeIp(String value) {
    final v = value.trim();
    return _ipv4.hasMatch(v) || (v.contains(':') && _ipv6.hasMatch(v));
  }

  static LinkState evaluate({
    required String? coreIp,
    required String? systemIp,
    required String? baselineIp,
    required bool tunOn,
  }) {
    if (coreIp == null) return LinkState.noAnswer;
    if (baselineIp != null && coreIp == baselineIp) return LinkState.unchanged;
    if (!tunOn) return LinkState.verified;
    if (systemIp == null) return LinkState.noAnswer;
    return systemIp == coreIp ? LinkState.verified : LinkState.mismatch;
  }

  static const _services = [
    'https://api.ipify.org',
    'https://icanhazip.com',
    'https://ifconfig.me/ip',
  ];

  /// The public IP as seen from the internet. With [proxy] (`host:port`) the
  /// request goes through that local proxy; without it, straight out through
  /// whatever the system routing does (TUN included).
  static Future<String?> fetchIp({
    String? proxy,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => proxy == null ? 'DIRECT' : 'PROXY $proxy';
    try {
      for (final url in _services) {
        try {
          final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
          final response = await request.close().timeout(timeout);
          final body = await response
              .transform(utf8.decoder)
              .join()
              .timeout(timeout);
          final ip = body.trim();
          if (response.statusCode == 200 && looksLikeIp(ip)) return ip;
        } catch (_) {
          continue;
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
