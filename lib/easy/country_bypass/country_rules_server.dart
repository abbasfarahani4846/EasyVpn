import 'dart:async';
import 'dart:io';

import 'country_rules_cache.dart';

/// Hands the cached rule lists to the core over loopback, so the core's own
/// fetch is instant and never depends on the internet or on DNS.
class CountryRulesServer {
  CountryRulesServer._();

  static final CountryRulesServer instance = CountryRulesServer._();

  /// Fixed so the provider URLs in the generated profile stay the same.
  static const port = 20841;

  HttpServer? _server;

  String urlFor(String name) => 'http://127.0.0.1:$port/$name';

  Future<bool> ensureStarted() async {
    if (_server != null) return true;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _server = server;
      unawaited(server.forEach(_handle));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final name = request.uri.pathSegments.isEmpty
        ? ''
        : request.uri.pathSegments.last;
    // Only plain list names: never a path that could leave the cache folder.
    if (!RegExp(r'^[a-z0-9_-]+\.mrs$').hasMatch(name)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final file = await CountryRulesCache.file(name);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.binary;
    request.response.contentLength = await file.length();
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
