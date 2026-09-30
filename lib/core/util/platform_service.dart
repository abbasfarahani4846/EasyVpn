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

  /// Creates the VPN interface (Android) and returns its TUN file descriptor
  /// for the Go core, or null when the system refused.
  static Future<int?> establishVpn({
    required int mtu,
    required bool ipv6,
    List<String> include = const [],
    List<String> exclude = const [],
  }) => _try<int>('establishVpn', {
    'mtu': mtu,
    'ipv6': ipv6,
    'include': include,
    'exclude': exclude,
  });

  static Future<void> stopVpn() => _try<bool>('stopVpn');

  /// Native -> Dart notifications (system revoked the VPN / tile or notification tapped).
  static void setHandlers({
    required void Function() onRevoked,
    required void Function() onToggle,
    void Function()? onFastest,
  }) {
    void run(String? m) {
      if (m == 'vpnRevoked') onRevoked();
      if (m == 'toggle') onToggle();
      if (m == 'fastest') onFastest?.call();
    }

    _ch.setMethodCallHandler((call) async {
      run(call.method);
      return null;
    });
    // Replays a widget/shortcut tap that cold-started the app.
    _try<String>('ready').then(run);
  }

  /// Updates the Android home-screen widget label.
  static Future<void> setWidgetInfo({
    required bool connected,
    required String node,
  }) async {
    if (!isAndroid) return;
    await _try<bool>('setWidgetInfo', {'connected': connected, 'node': node});
  }

  /// Opens the system installer for a verified update APK.
  static Future<void> installApk(String path) async {
    await _ch.invokeMethod('installApk', {'path': path});
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

  /// True when the process may create a TUN device (admin/root). Always true on mobile.
  static Future<bool> isElevated() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('fltmc', const []);
        return r.exitCode == 0;
      }
      if (Platform.isLinux || Platform.isMacOS) {
        final r = await Process.run('id', const ['-u']);
        return (r.stdout as String).trim() == '0';
      }
    } catch (_) {}
    return true;
  }

  /// Relaunches the app with administrator rights (Windows UAC / Linux pkexec).
  /// Returns false when the platform has no supported mechanism.
  static Future<bool> relaunchElevated() async {
    final exe = Platform.resolvedExecutable;
    try {
      if (Platform.isWindows) {
        await Process.start('powershell', [
          '-NoProfile',
          '-Command',
          "Start-Process -FilePath '$exe' -Verb RunAs",
        ], mode: ProcessStartMode.detached);
        exit(0);
      }
      if (Platform.isLinux) {
        final display = Platform.environment['DISPLAY'] ?? ':0';
        final xauth = Platform.environment['XAUTHORITY'] ?? '';
        await Process.start('pkexec', [
          'env',
          'DISPLAY=$display',
          'XAUTHORITY=$xauth',
          exe,
        ], mode: ProcessStartMode.detached);
        exit(0);
      }
    } catch (_) {}
    return false;
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
