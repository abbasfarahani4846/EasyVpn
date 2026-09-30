import 'dart:async';
import 'dart:convert';

import '../models/models.dart';
import 'core_transport.dart';
import 'unavailable_transport.dart';

export 'core_transport.dart';

/// Typed facade over [CoreTransport]. The single entry point the rest of the
/// app uses to talk to the Go core.
class CoreBridge {
  CoreBridge(this._t);
  final CoreTransport _t;

  Stream<List<CoreEvent>> get events => _t.events;
  bool get isAvailable => _t.isAvailable;
  String get unavailableReason => switch (_t) {
    UnavailableTransport u => u.reason,
    _ => '',
  };

  Future<Map<String, dynamic>> raw(
    String method, [
    Map<String, dynamic>? args,
  ]) => _t.call(method, args);

  Future<Map<String, dynamic>> info() => _t.call('Info');
  Future<Map<String, dynamic>> exitInfo({String url = ''}) =>
      _t.call('ExitInfo', {'url': url});

  Future<void> start({
    required Map<String, dynamic> node,
    List<Map<String, dynamic>> candidates = const [],
    required AppSettings settings,
    String? authUser,
    String? authPass,
    Map<String, dynamic>? tun,
    List<Map<String, dynamic>> chain = const [],
  }) async {
    await _t.call('Start', {
      'node': node,
      'candidates': candidates,
      if (chain.isNotEmpty) 'chain': chain,
      'mode': settings.mode.wire,
      'local_port': settings.localPort,
      'allow_lan': settings.allowLan,
      'test_url': settings.testUrl,
      'auth': ?(authUser == null
          ? null
          : {'user': authUser, 'pass': authPass ?? ''}),
      'tun':
          tun ??
          {
            'mtu': settings.tunMtu,
            'strict_route': settings.tunStrictRoute,
            'ipv6': settings.tunIpv6,
            'include_packages': ?(settings.perAppMode == 'include'
                ? settings.perAppPackages
                : null),
            'exclude_packages': ?(settings.perAppMode == 'exclude'
                ? settings.perAppPackages
                : null),
          },
      'tricks': {
        'fragment': settings.routing.tlsFragment,
        'record_fragment': false,
      },
    });
  }

  Future<void> stop() => _t.call('Stop');

  /// Decodes a QR code from an image (file path or raw bytes).
  Future<String> decodeQr({String path = '', List<int>? bytes}) async {
    final r = await _t.call('DecodeQR', {
      'path': path,
      if (bytes != null) 'data': base64Encode(bytes),
    });
    return (r['text'] as String?) ?? '';
  }

  /// Probes IP/region-sensitive sites through the running tunnel.
  Future<List<Map<String, dynamic>>> siteCheck() async {
    final r = await _t.call('SiteCheck', {});
    return ((r['results'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// Registers a free WARP device; returns {node, account}.
  Future<Map<String, dynamic>> warpRegister({
    String name = 'WARP',
    String endpoint = '',
    String license = '',
  }) => _t.call('WarpRegister', {
    'name': name,
    'endpoint': endpoint,
    'license': license,
  });

  /// Expands one Windscribe WireGuard config to every location of the account.
  Future<List<Map<String, dynamic>>> windscribeExpand(
    Map<String, dynamic> template, {
    bool pro = false,
  }) async {
    final r = await _t.call('WindscribeExpand', {
      'template': template,
      'pro': pro,
    });
    return ((r['nodes'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateCheck({
    required String channel,
    required String current,
    required Map<String, dynamic> target,
  }) => _t.call('UpdateCheck', {
    'channel': channel,
    'current': current,
    'target': target,
  });

  /// Downloads + verifies an update; returns the local file path.
  Future<String> updateDownload({
    required String url,
    required String name,
    required String sha256,
  }) async =>
      (await _t.call('UpdateDownload', {
            'url': url,
            'name': name,
            'sha256': sha256,
          }))['path']
          as String;
  Future<void> switchNode(Map<String, dynamic> node) =>
      _t.call('SwitchNode', {'node': node});

  Future<TrafficStats> stats() async =>
      TrafficStats.fromJson(await _t.call('GetStats'));

  Future<({List<Map<String, dynamic>> nodes, List<String> warnings})>
  parseContent(String content) async {
    final r = await _t.call('ParseContent', {'content': content});
    return (
      nodes: (r['nodes'] as List)
          .cast<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
      warnings: ((r['warnings'] as List?) ?? const []).cast<String>(),
    );
  }

  Future<Map<String, dynamic>> fetchSubscription(
    String url, {
    String ua = '',
    bool viaProxy = true,
  }) => _t.call('FetchSubscription', {
    'url': url,
    'ua': ua,
    'via_proxy': viaProxy,
  });

  Future<List<Map<String, dynamic>>> ping(
    List<Map<String, dynamic>> nodes, {
    String mode = 'tcp',
    String? url,
    int workers = 50,
  }) async {
    final r = await _t.call('PingBatch', {
      'nodes': nodes,
      'mode': mode,
      'url': url ?? '',
      'workers': workers,
    });
    return (r['results'] as List)
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> cancelPing() => _t.call('CancelPing');

  Future<Map<String, dynamic>> setRouting(RoutingSettings r) =>
      _t.call('SetRouting', r.toCoreModel());
  Future<Map<String, dynamic>> setCountry(String cc) =>
      _t.call('SetCountry', {'country': cc});
  Future<void> setTricks({required bool fragment}) =>
      _t.call('SetTricks', {'fragment': fragment, 'record_fragment': false});

  Future<({String country, String source, double confidence})> detectCountry({
    String? sim,
    String? network,
    String? locale,
    String? timezone,
  }) async {
    final r = await _t.call('DetectCountry', {
      'sim_country': ?sim,
      'network_country': ?network,
      'locale': ?locale,
      'timezone': ?timezone,
    });
    return (
      country: (r['country'] as String?) ?? '',
      source: (r['source'] as String?) ?? 'none',
      confidence: ((r['confidence'] as num?) ?? 0).toDouble(),
    );
  }

  Future<List<Map<String, dynamic>>> syncRuleSets({
    List<String> tags = const [],
  }) async {
    final r = await _t.call('SyncRuleSets', {'tags': tags});
    return ((r['events'] as List?) ?? const [])
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<List<RuleSetStatus>> ruleSetStatus() async {
    final r = await _t.call('RuleSetStatus');
    return ((r['statuses'] as List?) ?? const [])
        .cast<Map>()
        .map((e) => RuleSetStatus.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Map<String, dynamic>> countries() => _t.call('Countries');
  Future<void> addRuleSet(String tag, List<String> urls) =>
      _t.call('AddRuleSet', {'tag': tag, 'urls': urls});
  Future<void> removeRuleSet(String tag) =>
      _t.call('RemoveRuleSet', {'tag': tag});

  /// format: uri | clash | singbox | wgquick
  Future<String> export(String format, List<Map<String, dynamic>> nodes) async {
    final r = await _t.call('Export', {'format': format, 'nodes': nodes});
    return r['payload'] as String;
  }

  Future<String> dumpConfig(Map<String, dynamic> node, ConnMode mode) async =>
      (await _t.call('DumpConfig', {'node': node, 'mode': mode.wire}))['config']
          as String;

  Future<String> backupEncrypt(
    Map<String, dynamic> data,
    String passphrase,
  ) async =>
      (await _t.call('BackupEncrypt', {
            'data': data,
            'passphrase': passphrase,
          }))['blob']
          as String;

  Future<Map<String, dynamic>> backupDecrypt(
    String blob,
    String passphrase,
  ) async =>
      ((await _t.call('BackupDecrypt', {
                'blob': blob,
                'passphrase': passphrase,
              }))['data']
              as Map)
          .cast<String, dynamic>();

  Future<List<String>> seal(String keyB64, List<String> items) async =>
      ((await _t.call('Seal', {'key': keyB64, 'items': items}))['items']
              as List)
          .cast<String>();

  Future<List<String>> open(String keyB64, List<String> items) async =>
      ((await _t.call('Open', {'key': keyB64, 'items': items}))['items']
              as List)
          .cast<String>();

  Future<void> shutdown() async {
    try {
      await _t.call('Shutdown');
    } catch (_) {}
    await _t.dispose();
  }
}
