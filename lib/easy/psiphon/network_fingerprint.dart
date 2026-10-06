import 'dart:io';

import 'package:crypto/crypto.dart';
import 'dart:convert';

/// A stable id for "which internet connection am I on", so what worked on one
/// network is remembered separately from another. Virtual adapters (including
/// the app's own tunnel) are ignored so connecting does not change the id.
class NetworkFingerprint {
  const NetworkFingerprint._();

  static final _virtual = RegExp(
    r'meta|clash|easyvpn|sing|tun|wintun|tap|vethernet|vmware|virtualbox|'
    r'hyper-v|loopback|tailscale|zerotier|wireguard|openvpn|psiphon|wsl',
    caseSensitive: false,
  );

  static String of(Map<String, List<String>> interfaces) {
    final parts = <String>[];
    interfaces.forEach((name, addresses) {
      if (_virtual.hasMatch(name)) return;
      for (final address in addresses) {
        final octets = address.split('.');
        if (octets.length != 4) continue;
        parts.add('$name|${octets.take(3).join('.')}');
      }
    });
    parts.sort();
    if (parts.isEmpty) return 'offline';
    return sha1
        .convert(utf8.encode(parts.join(';')))
        .toString()
        .substring(0, 16);
  }

  static Future<String> current() async {
    try {
      final list = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      return of({
        for (final i in list) i.name: [for (final a in i.addresses) a.address],
      });
    } catch (_) {
      return 'unknown';
    }
  }
}
