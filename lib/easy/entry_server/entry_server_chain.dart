/// Routes every other proxy through one chosen "entry" proxy by setting
/// mihomo's `dialer-proxy`, so the first hop covers both the connection to
/// each server and its delay test.
class EntryServerChain {
  const EntryServerChain._();

  static const dialerKey = 'dialer-proxy';

  /// Local SOCKS port whose traffic is pinned to the entry server; Psiphon
  /// uses it as its upstream so it too reaches the internet through the entry.
  static const listenerPort = 20840;
  static const listenerName = 'easy-entry';

  static Map<String, dynamic> apply(
    Map<String, dynamic> rawConfig,
    Map<String, Object?>? entry,
  ) {
    if (entry == null || entry['name'] == null) return rawConfig;
    final config = Map<String, dynamic>.from(rawConfig);
    final proxies = <Map<String, dynamic>>[
      for (final item in (config['proxies'] as List? ?? const []))
        if (item is Map) Map<String, dynamic>.from(item),
    ];

    var entryName = '${entry['name']}';
    final entryProxy = Map<String, dynamic>.from(entry)..remove(dialerKey);
    final existing = proxies.indexWhere((p) => p['name'] == entryName);
    if (existing == -1) {
      proxies.add(entryProxy);
    } else if (_sameServer(proxies[existing], entry)) {
      proxies[existing] = entryProxy;
    } else {
      entryName = '$entryName [entry]';
      entryProxy['name'] = entryName;
      proxies.add(entryProxy);
    }

    for (final proxy in proxies) {
      if (proxy['name'] == entryName) continue;
      // A local proxy (Psiphon's SOCKS port) listens on this machine only;
      // dialling it through a remote entry server would reach that server's
      // own loopback instead.
      if (isLocal(proxy)) continue;
      proxy.putIfAbsent(dialerKey, () => entryName);
    }
    config['proxies'] = proxies;
    config['listeners'] = [
      for (final l in (config['listeners'] as List? ?? const []))
        if (l is Map && l['name'] != listenerName) l,
      {
        'name': listenerName,
        'type': 'socks',
        'listen': '127.0.0.1',
        'port': listenerPort,
        'proxy': entryName,
      },
    ];

    final providers = config['proxy-providers'];
    if (providers is Map) {
      config['proxy-providers'] = {
        for (final e in providers.entries)
          e.key: e.value is Map
              ? _overrideProvider(e.value as Map, entryName)
              : e.value,
      };
    }
    return config;
  }

  static Map<String, dynamic> _overrideProvider(Map provider, String entry) {
    final copy = Map<String, dynamic>.from(provider);
    final override = Map<String, dynamic>.from(
      (copy['override'] as Map?) ?? const {},
    );
    override.putIfAbsent(dialerKey, () => entry);
    copy['override'] = override;
    return copy;
  }

  static bool isLocal(Map proxy) {
    final server = '${proxy['server']}'.toLowerCase();
    return server == 'localhost' ||
        server == '::1' ||
        server.startsWith('127.');
  }

  static bool _sameServer(Map a, Map b) =>
      a['server'] == b['server'] && '${a['port']}' == '${b['port']}';
}
