import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../windscribe/doh_resolver.dart';
import 'country_bypass_config.dart';
import 'country_catalog.dart';
import 'country_rules_server.dart';

/// Keeps the country rule lists on disk so connecting never waits for the
/// internet. Networks that tamper with DNS (GitHub resolving to a private
/// address) are handled by downloading through DNS-over-HTTPS.
class CountryRulesCache {
  const CountryRulesCache._();

  /// Tests point the cache at a temporary folder.
  static Directory? testDirectory;

  static Future<Directory> directory() async {
    final override = testDirectory;
    if (override != null) {
      await override.create(recursive: true);
      return override;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}easy_country');
    await dir.create(recursive: true);
    return dir;
  }

  static String fileName(CountrySource country, {required bool domain}) =>
      '${country.code}-${domain ? 'domain' : 'ip'}.mrs';

  static const maxAge = Duration(hours: 24);

  static Future<File> file(String name) async =>
      File('${(await directory()).path}${Platform.pathSeparator}$name');

  static Future<bool> has(String name) async {
    final f = await file(name);
    return await f.exists() && await f.length() > 64;
  }

  static Future<bool> isStale(String name) async {
    final f = await file(name);
    if (!await f.exists()) return true;
    return DateTime.now().difference(await f.lastModified()) > maxAge;
  }

  /// `easy_bin/country/<name>` beside the app (or any parent folder), for a
  /// first run on a network where nothing can be downloaded.
  static File? seed(String name) {
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final candidate = File(
        '${dir.path}${Platform.pathSeparator}easy_bin'
        '${Platform.pathSeparator}country${Platform.pathSeparator}$name',
      );
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static Future<bool> installSeed(String name) async {
    final seeded = seed(name);
    if (seeded == null) return false;
    await seeded.copy((await file(name)).path);
    return true;
  }

  /// Downloads [url] into the cache as [name]. Tries the normal way first,
  /// then straight to an address found over HTTPS. Returns false on failure
  /// and never leaves a half-written file.
  static Future<bool> download(
    String name,
    List<String> urls, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    for (final url in urls) {
      for (final viaDoh in [false, true]) {
        final bytes = await _get(
          Uri.parse(url),
          viaDoh: viaDoh,
          timeout: timeout,
        );
        if (bytes != null && bytes.length > 64) {
          final target = await file(name);
          final temp = File('${target.path}.part');
          await temp.writeAsBytes(bytes, flush: true);
          await temp.rename(target.path);
          return true;
        }
      }
    }
    return false;
  }

  /// Provider name -> (cache file, where to download it).
  static List<({String provider, String file, List<String> urls})> sources(
    CountrySelection selection,
  ) {
    final country = CountryCatalog.byCode(selection.code);
    if (country == null) return const [];
    List<String> urlsOf(RuleFile f) => [
      f.url(mirror: selection.mirror),
      f.url(mirror: !selection.mirror),
    ];
    return [
      if (selection.domain && country.domain != null)
        (
          provider: country.domainProvider,
          file: fileName(country, domain: true),
          urls: urlsOf(country.domain!),
        ),
      if (selection.ip)
        (
          provider: country.ipProvider,
          file: fileName(country, domain: false),
          urls: urlsOf(country.ip),
        ),
    ];
  }

  /// The local URL for every list that is available right now. With [wait]
  /// false (connecting) nothing here ever blocks on the internet: a missing
  /// list is installed from the seed or fetched in the background, and the
  /// rule simply starts to apply on the next connect. With [wait] true (the
  /// user just picked a country) missing lists are fetched first.
  static Future<Map<String, String>> prepare(
    CountrySelection selection, {
    bool wait = false,
    bool force = false,
  }) async {
    final server = CountryRulesServer.instance;
    if (!await server.ensureStarted()) return const {};
    final urls = <String, String>{};
    final pending = <Future<void>>[];
    for (final s in sources(selection)) {
      if (!await has(s.file)) await installSeed(s.file);
      if (force || await isStale(s.file)) {
        final job = download(
          s.file,
          s.urls,
          timeout: wait
              ? const Duration(seconds: 12)
              : const Duration(seconds: 8),
        ).then((_) {});
        if (wait) {
          pending.add(job);
        } else {
          unawaited(job);
        }
      }
    }
    if (pending.isNotEmpty) await Future.wait(pending);
    for (final s in sources(selection)) {
      if (await has(s.file)) urls[s.provider] = server.urlFor(s.file);
    }
    return urls;
  }

  static Future<List<int>?> debugGet(Uri uri, {required bool viaDoh}) =>
      _get(uri, viaDoh: viaDoh, timeout: const Duration(seconds: 10));

  static Future<List<int>?> _get(
    Uri uri, {
    required bool viaDoh,
    required Duration timeout,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      if (viaDoh) {
        final ip = await DohResolver.resolve(uri.host, timeout: timeout);
        if (ip == null) return null;
        // Connect to the real address and run TLS against the original name.
        client.connectionFactory = (u, proxyHost, proxyPort) async {
          final task = await Socket.startConnect(ip, u.port);
          final secure = task.socket.then(
            (s) => SecureSocket.secure(s, host: u.host),
          );
          return ConnectionTask.fromSocket<Socket>(secure, task.cancel);
        };
      }
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
