import 'dart:convert';

import 'psiphon_constants.dart';

/// One way of asking Psiphon to connect, and how long to wait for it.
///
/// Which one works depends on the network, so the manager walks them all: the
/// fronted path survives address blocklists, the direct one is fastest where
/// nothing is blocked, and the in-proxy one borrows other users' devices when
/// every server address and CDN front is unreachable.
class PsiphonRung {
  final String name;
  final String labelEn;
  final String labelFa;
  final int budgetSeconds;
  final void Function(Map<String, Object?> config) apply;

  const PsiphonRung({
    required this.name,
    required this.labelEn,
    required this.labelFa,
    required this.budgetSeconds,
    required this.apply,
  });
}

class PsiphonLadder {
  const PsiphonLadder._();

  static const fronted = [
    'FRONTED-MEEK-OSSH',
    'FRONTED-MEEK-HTTP-OSSH',
    'FRONTED-MEEK-QUIC-OSSH',
  ];

  static void _noTactics(Map<String, Object?> c) {
    c['DisableTactics'] = true;
    c['InproxyEnabled'] = false;
    c['InproxyAllowClient'] = false;
  }

  static final List<PsiphonRung> rungs = List.unmodifiable([
    PsiphonRung(
      name: 'A',
      labelEn: 'Domain fronting (CDN)',
      labelFa: 'دامین‌فرانتینگ (CDN)',
      budgetSeconds: 100,
      apply: (c) {
        c['InitialLimitTunnelProtocols'] = fronted;
        c['InitialLimitTunnelProtocolsCandidateCount'] = 30;
        c['LimitTunnelProtocols'] = fronted;
        c['ConnectionWorkerPoolSize'] = 12;
        c['NetworkLatencyMultiplier'] = 2.0;
        _noTactics(c);
      },
    ),
    PsiphonRung(
      name: 'D',
      labelEn: 'All protocols (direct)',
      labelFa: 'همه‌ی پروتکل‌ها (مستقیم)',
      budgetSeconds: 60,
      apply: (c) {
        c['ConnectionWorkerPoolSize'] = 16;
        _noTactics(c);
      },
    ),
    PsiphonRung(
      name: 'C',
      labelEn: 'Relay through other users',
      labelFa: 'رله از طریق کاربران دیگر',
      budgetSeconds: 90,
      apply: (c) {
        c['InproxyEnabled'] = true;
        c['InproxyAllowClient'] = true;
        c['InproxySkipAwaitFullyConnected'] = true;
        c['ConnectionWorkerPoolSize'] = 16;
        c['NetworkLatencyMultiplier'] = 3.0;
      },
    ),
  ]);

  /// Fast first, patient later: a server that answers connects within
  /// seconds, so a slow first try usually means that method does not work on
  /// this network. Later passes wait longer for the hard networks.
  static int budgetFor(PsiphonRung rung, int pass) {
    if (pass <= 0) return 8;
    if (pass == 1) return 15;
    return rung.name == 'A' ? 40 : 25;
  }

  /// Protocols that can cross a SOCKS5 upstream (TCP only).
  static const chainable = [
    'FRONTED-MEEK-OSSH',
    'FRONTED-MEEK-HTTP-OSSH',
    'TLS-OSSH',
    'UNFRONTED-MEEK-HTTPS-OSSH',
    'UNFRONTED-MEEK-OSSH',
    'SHADOWSOCKS-OSSH',
    'OSSH',
    'SSH',
  ];

  /// In-proxy needs raw UDP, which a SOCKS5 upstream cannot carry.
  static List<PsiphonRung> orderFor({String? winner, bool chained = false}) {
    final all = order(winner: winner);
    return chained
        ? [
            for (final r in all)
              if (r.name != 'C') r,
          ]
        : all;
  }

  static PsiphonRung? byName(String? name) {
    for (final r in rungs) {
      if (r.name == name) return r;
    }
    return null;
  }

  /// The remembered winner goes first (this network connected there last
  /// time); the rest keep their natural order behind it.
  static List<PsiphonRung> order({String? winner}) {
    final first = byName(winner);
    if (first == null) return rungs;
    return [first, ...rungs.where((r) => r.name != first.name)];
  }

  static String _b64(String url) => base64.encode(utf8.encode(url));

  static List<Map<String, Object?>> _drops(List<PsiphonDrop> drops) => [
    for (final d in drops)
      {
        'URL': _b64(d.url),
        'SkipVerify': d.skipVerify,
        'OnlyAfterAttempts': d.onlyAfterAttempts,
      },
  ];

  static Map<String, Object?> buildConfig({
    required PsiphonRung rung,
    required String dataDir,
    required int socksPort,
    String deviceRegion = 'IR',
    String? egressRegion,
    String? upstreamProxyUrl,
  }) {
    final sep = dataDir.endsWith('/') || dataDir.endsWith('\\') ? '' : '/';
    final config = <String, Object?>{
      'PropagationChannelId': psiphonPropagationChannelId,
      'SponsorId': psiphonSponsorId,
      'ClientVersion': '1',
      'EgressRegion': '',
      'TunnelProtocol': '',
      'EstablishTunnelTimeoutSeconds': 0,
      'DataRootDirectory': dataDir,
      'LocalSocksProxyPort': socksPort,
      'RemoteServerListURLs': _drops(psiphonRemoteServerListDrops),
      'DisableRemoteServerListFetcher': false,
      'FetchRemoteServerListRetryPeriodMilliseconds': 30000,
      'RemoteServerListDownloadFilename': '$dataDir${sep}remote_server_list',
      'ObfuscatedServerListRootURLs': _drops(psiphonObfuscatedServerListDrops),
      'ObfuscatedServerListDownloadDirectory': '$dataDir${sep}osl',
      'RemoteServerListSignaturePublicKey': psiphonRemoteServerListSignatureKey,
      'ServerEntrySignaturePublicKey': psiphonServerEntrySignatureKey,
      'ExchangeObfuscationKey': psiphonExchangeObfuscationKey,
      'EmitBytesTransferred': true,
      'EmitDiagnosticNotices': true,
      'DeviceRegion': deviceRegion,
      'ConnectionWorkerPoolSize': 12,
      'DNSResolverPreferredAlternateServers': psiphonAlternateDns,
      'DNSResolverPreferAlternateServerProbability': 1.0,
      'DNSResolverAttemptsPerPreferredServer': 2,
    };
    rung.apply(config);
    if (upstreamProxyUrl != null) {
      config['UpstreamProxyURL'] = upstreamProxyUrl;
      config['LimitTunnelProtocols'] = chainable;
      config.remove('InitialLimitTunnelProtocols');
      config.remove('InitialLimitTunnelProtocolsCandidateCount');
      config['InproxyEnabled'] = false;
      config['InproxyAllowClient'] = false;
    }
    if (egressRegion != null) {
      config['EgressRegion'] = egressRegion;
      // The country is a hard filter, so a hard protocol limit on top of it
      // can leave no candidates at all (CA has no fronted server). Keep the
      // limit only as a preference, except through an upstream proxy where
      // only TCP protocols can work anyway.
      if (upstreamProxyUrl == null) config.remove('LimitTunnelProtocols');
    }
    return config;
  }
}
