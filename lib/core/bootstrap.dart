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

/// Performs all async startup work before `runApp`.
Future<AppEnv> bootstrap() async {
  final dir = await getApplicationSupportDirectory();
  final dataDir = p.join(dir.path, 'easyvpn');
  await Directory(dataDir).create(recursive: true);

  final transport = await openCoreTransport(cacheDir: p.join(dataDir, 'core'));
  final core = CoreBridge(transport);
  final secrets = await SecretStore.open(dataDir);
  final db = await AppDatabase.open(p.join(dataDir, 'easyvpn.db'));

  var settings = const AppSettings();
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
