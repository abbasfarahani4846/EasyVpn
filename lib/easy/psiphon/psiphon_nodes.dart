/// The "servers" a Psiphon profile lists in Proxies: one automatic entry plus
/// one per egress country. They all reach the same local SOCKS port; choosing
/// one tells the Psiphon core which country to come out in.
class PsiphonNodes {
  const PsiphonNodes._();

  static const profileLabel = 'Psiphon';
  static const socksPort = 20830;
  static const autoName = 'Psiphon Auto';

  /// Countries Psiphon's server list currently has entries in.
  static const regions = [
    'AT', 'AU', 'BE', 'BR', 'CA', 'CH', 'CZ', 'DE', 'DK', 'ES', 'FI', 'FR', //
    'GB', 'ID', 'IE', 'IN', 'IT', 'JP', 'LT', 'NL', 'NO', 'PL', 'RO', 'RS',
    'SE', 'SG', 'US',
  ];

  /// Regions where Psiphon has domain-fronted servers.
  static const frontedRegions = ['US', 'GB', 'DE', 'NL', 'FR', 'CA'];

  static String flag(String region) => String.fromCharCodes(
    region.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
  );

  static String nameFor(String region) => '${flag(region)} $region Psiphon';

  static Map<String, Object?> _node(String name) => {
    'name': name,
    'type': 'socks5',
    'server': '127.0.0.1',
    'port': socksPort,
    'udp': false,
  };

  static List<Map<String, Object?>> build() => [
    _node(autoName),
    for (final region in regions) _node(nameFor(region)),
  ];

  /// `null` for Auto; throws nothing for names that are not Psiphon nodes.
  static ({bool isPsiphon, String? region}) parse(String proxyName) {
    if (proxyName == autoName) return (isPsiphon: true, region: null);
    for (final region in regions) {
      if (proxyName == nameFor(region)) {
        return (isPsiphon: true, region: region);
      }
    }
    return (isPsiphon: false, region: null);
  }
}
