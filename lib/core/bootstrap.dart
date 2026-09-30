import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/core_bridge.dart';
import 'bridge/core_locator.dart';
import 'database/app_database.dart';
import 'database/node_repository.dart';
import 'models/models.dart';
import 'providers/env.dart';
import 'security/secret_store.dart';

/// Portable mode (desktop): a file named `portable` next to the executable makes
/// every setting, the database and the core cache live in `data/` beside it, so the
/// folder can be moved or run from a USB stick. Otherwise the per-user directory.
Future<String> _resolveDataDir() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      if (await File(p.join(exeDir, 'portable')).exists()) {
        return p.join(exeDir, 'data');
      }
    } catch (_) {}
  }
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, 'easyvpn');
}

/// Performs all async startup work before `runApp`.
Future<AppEnv> bootstrap() async {
  final dataDir = await _resolveDataDir();
  await Directory(dataDir).create(recursive: true);

  final transport = await openCoreTransport(cacheDir: p.join(dataDir, 'core'));
  final core = CoreBridge(transport);
  final secrets = await SecretStore.open(dataDir);
  final db = await AppDatabase.open(p.join(dataDir, 'easyvpn.db'));

  // First run: desktop starts with the OS proxy (no admin rights), Android with the VPN tunnel.
  var settings = AppSettings(
    mode: Platform.isAndroid
        ? ConnMode.tun
        : (Platform.isWindows || Platform.isLinux || Platform.isMacOS
              ? ConnMode.systemProxy
              : ConnMode.proxyOnly),
  );
  final raw = await db.kvGet('settings');
  if (raw != null) {
    try {
      settings = AppSettings.decode(raw);
    } catch (_) {
      // corrupt settings: fall back to defaults instead of failing to start
    }
  }

  var pass = await db.kvGet('local_pass');
  if (pass == null) {
    final r = Random.secure();
    pass = List.generate(
      16,
      (_) => 'abcdefghijkmnopqrstuvwxyz23456789'[r.nextInt(33)],
    ).join();
    await db.kvSet('local_pass', pass);
  }

  return AppEnv(
    core: core,
    db: db,
    repo: NodeRepository(db, core, secrets.keyB64),
    dataDir: dataDir,
    initialSettings: settings,
    keystoreBacked: secrets.usesKeystore,
    localPass: pass,
  );
}
