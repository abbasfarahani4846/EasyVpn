import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'country_rules_cache.dart';

/// Hands the cached rule lists to the core over loopback, so the core's own
/// fetch is instant and never depends on the internet or on DNS.
class CountryRulesServer {
  CountryRulesServer._() : _listenPort = port;

  @visibleForTesting
  CountryRulesServer.forTest(this._listenPort);

  static final CountryRulesServer instance = CountryRulesServer._();

  final int _listenPort;

  /// Fixed so the provider URLs in the generated profile stay the same.
  static const port = 20841;

  HttpServer? _server;

  int get boundPort => _server?.port ?? _listenPort;

  String urlFor(String name) => 'http://127.0.0.1:$boundPort/$name';

  Future<bool> ensureStarted() async {
    if (_server != null) return true;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _listenPort,
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
    try {
      await _serve(request);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serve(HttpRequest request) async {
    // The core's HTTP client reuses idle connections; Dart drops them after
    // two minutes without telling it, and the next fetch then reads EOF.
    request.response.persistentConnection = false;
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
