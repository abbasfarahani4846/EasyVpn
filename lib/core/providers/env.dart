import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/core_bridge.dart';
import '../database/app_database.dart';
import '../database/node_repository.dart';
import '../models/models.dart';

/// Everything created before `runApp` (opened DB, bridge, initial settings).
class AppEnv {
  AppEnv({
    required this.core,
    required this.db,
    required this.repo,
    required this.dataDir,
    required this.initialSettings,
    required this.keystoreBacked,
    this.localPass = '',
  });

  final CoreBridge core;
  final AppDatabase db;
  final NodeRepository repo;
  final String dataDir;
  final AppSettings initialSettings;
  final bool keystoreBacked;
  final String localPass;
}

/// Overridden in `main()` once the async startup finished.
final envProvider = Provider<AppEnv>(
  (ref) => throw UnimplementedError('envProvider must be overridden'),
);
