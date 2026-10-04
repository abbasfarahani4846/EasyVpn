/// Routes every other proxy through one chosen "entry" proxy by setting
/// mihomo's `dialer-proxy`, so the first hop covers both the connection to
/// each server and its delay test.
class EntryServerChain {
  const EntryServerChain._();

  static const dialerKey = 'dialer-proxy';

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
      proxy.putIfAbsent(dialerKey, () => entryName);
    }
    config['proxies'] = proxies;

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

  static bool _sameServer(Map a, Map b) =>
      a['server'] == b['server'] && '${a['port']}' == '${b['port']}';
}
