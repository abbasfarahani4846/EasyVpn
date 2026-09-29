/// Human readable bytes: 1.5 MB.
String fmtBytes(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${u[i]}';
}

/// Speed: 1.5 MB/s
String fmtSpeed(num bps) => '${fmtBytes(bps)}/s';

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${h > 0 ? '${two(h)}:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Country flag emoji from an ISO alpha-2 code ("IR" -> 🇮🇷).
String flagEmoji(String cc) {
  if (cc.length != 2) return '🌐';
  final a = cc.toUpperCase().codeUnits;
  if (a.any((c) => c < 65 || c > 90)) return '🌐';
  return String.fromCharCodes(a.map((c) => 0x1F1E6 + c - 65));
}

/// Short protocol label for badges.
String protocolLabel(String p) => switch (p) {
  'vless' => 'VLESS',
  'vmess' => 'VMess',
  'trojan' => 'Trojan',
  'shadowsocks' => 'SS',
  'hysteria2' => 'Hy2',
  'tuic' => 'TUIC',
  'wireguard' => 'WG',
  'openvpn' => 'OVPN',
  'anytls' => 'AnyTLS',
  'ssh' => 'SSH',
  'socks' => 'SOCKS',
  'http' => 'HTTP',
  _ => p.toUpperCase(),
};
