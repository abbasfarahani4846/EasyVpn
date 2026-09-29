import 'dart:io';

import 'package:flutter/services.dart';

/// Installed application (Android per-app tunneling).
class InstalledApp {
  const InstalledApp(this.package, this.label);
  final String package;
  final String label;
}

/// Thin wrapper over the `easyvpn/platform` MethodChannel implemented by the
/// Android host (VpnService, SIM country, installed apps). Every call degrades
/// gracefully when the channel is missing (desktop, tests).
class PlatformService {
  static const _ch = MethodChannel('easyvpn/platform');

  static bool get isAndroid => Platform.isAndroid;
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<T?> _try<T>(String m, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(m, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// SIM/network ISO country (Android), else null.
  static Future<String?> simCountry() => _try<String>('simCountry');
  static Future<String?> networkCountry() => _try<String>('networkCountry');

  /// Asks for VPN permission (Android). Returns true when granted or not needed.
  static Future<bool> prepareVpn() async {
    if (!isAndroid) return true;
    return (await _try<bool>('prepareVpn')) ?? false;
  }

  /// Returns launchable apps (Android) for the per-app tunneling picker.
  static Future<List<InstalledApp>> installedApps() async {
    final r = await _try<List<dynamic>>('installedApps');
    if (r == null) return const [];
    return r
        .cast<Map>()
        .map((m) => InstalledApp(m['package'] as String, m['label'] as String))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Registers/unregisters start-at-boot (Android) or login item (desktop).
  static Future<void> setAutoStart(bool enabled) async {
    if (isAndroid) {
      await _try<void>('setAutoStart', {'enabled': enabled});
    } else if (isDesktop) {
      await _desktopAutoStart(enabled);
    }
  }

  static Future<void> _desktopAutoStart(bool enabled) async {
    final exe = Platform.resolvedExecutable;
    try {
      if (Platform.isWindows) {
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        if (enabled) {
          await Process.run('reg', [
            'add',
            key,
            '/v',
            'EasyVPN',
            '/t',
            'REG_SZ',
            '/d',
            '"$exe" --minimized',
            '/f',
          ]);
        } else {
          await Process.run('reg', ['delete', key, '/v', 'EasyVPN', '/f']);
        }
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home == null) return;
        final f = File('$home/.config/autostart/easyvpn.desktop');
        if (enabled) {
          await f.create(recursive: true);
          await f.writeAsString(
            '[Desktop Entry]\nType=Application\nName=EasyVPN\nExec="$exe" --minimized\nX-GNOME-Autostart-enabled=true\n',
          );
        } else if (f.existsSync()) {
          await f.delete();
        }
      } else if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home == null) return;
        final f = File('$home/Library/LaunchAgents/app.easyvpn.plist');
        if (enabled) {
          await f.create(recursive: true);
          await f.writeAsString(
            '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0"><dict><key>Label</key><string>app.easyvpn</string><key>ProgramArguments</key><array><string>$exe</string><string>--minimized</string></array><key>RunAtLoad</key><true/></dict></plist>\n',
          );
        } else if (f.existsSync()) {
          await f.delete();
        }
      }
    } catch (_) {
      // best effort; the toggle simply has no effect if the OS refuses
    }
  }

  /// Local time-zone id when the host can provide it.
  static Future<String?> timezoneId() => _try<String>('timezone');
}
