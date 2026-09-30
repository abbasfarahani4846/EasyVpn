import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Holds the 32-byte at-rest key used to seal node secrets in the database.
/// Preferred location is the OS keystore (Keychain/Keystore/DPAPI/libsecret);
/// if that is unavailable (e.g. Linux without libsecret) a 0600 key file inside
/// the app-private directory is used and the fallback is reported.
class SecretStore {
  SecretStore._(this.keyB64, this.usesKeystore);
  final String keyB64;
  final bool usesKeystore;

  static const _name = 'easyvpn.db.key.v1';

  static Future<SecretStore> open(String appDir) async {
    const storage = FlutterSecureStorage();
    try {
      var k = await storage.read(key: _name);
      if (k == null) {
        k = _generate();
        await storage.write(key: _name, value: k);
        // Read back: some Linux setups accept writes but cannot read them.
        if (await storage.read(key: _name) != k)
          throw StateError('keystore round-trip failed');
      }
      return SecretStore._(k, true);
    } catch (_) {
      final f = File(p.join(appDir, '.dbkey'));
      if (f.existsSync())
        return SecretStore._(f.readAsStringSync().trim(), false);
      final k = _generate();
      f.createSync(recursive: true);
      f.writeAsStringSync(k);
      if (!Platform.isWindows) {
        try {
          Process.runSync('chmod', ['600', f.path]);
        } catch (_) {}
      }
      return SecretStore._(k, false);
    }
  }

  /// For tests.
  factory SecretStore.fixed(String keyB64) => SecretStore._(keyB64, false);

  static String _generate() {
    final r = Random.secure();
    return base64.encode(List<int>.generate(32, (_) => r.nextInt(256)));
  }
}
