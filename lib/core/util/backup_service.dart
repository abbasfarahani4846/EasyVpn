import 'dart:convert';

import '../bridge/core_bridge.dart';
import '../database/app_database.dart';
import '../database/node_repository.dart';
import '../models/models.dart';

/// Full backup/restore: settings + profiles + nodes (decrypted only in memory,
/// then sealed with AES-256-GCM/Argon2id by the Go core).
class BackupService {
  BackupService(this.db, this.repo, this.core);
  final AppDatabase db;
  final NodeRepository repo;
  final CoreBridge core;

  static const schema = 1;

  Future<Map<String, dynamic>> _collect(AppSettings settings) async {
    final profiles = await repo.profiles();
    final out = <Map<String, dynamic>>[];
    for (final p in profiles) {
      final ids = await repo.allIds(profileId: p.id);
      final nodes = <Map<String, dynamic>>[];
      for (var i = 0; i < ids.length; i += 500) {
        nodes.addAll(
          await repo.rawNodes(
            ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500),
          ),
        );
      }
      out.add({'profile': p.toMap(), 'nodes': nodes});
    }
    return {
      'schema': schema,
      'created': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'profiles': out,
    };
  }

  /// Returns the encrypted backup as a base64 string.
  Future<String> create(AppSettings settings, String passphrase) async =>
      core.backupEncrypt(await _collect(settings), passphrase);

  /// Plain (unencrypted, secret-free) settings export for support/debug.
  String exportSettings(AppSettings s) => const JsonEncoder.withIndent(
    '  ',
  ).convert({'schema': schema, 'settings': s.toJson()});

  AppSettings importSettings(String json) {
    final j = (jsonDecode(json) as Map).cast<String, dynamic>();
    final s = ((j['settings'] ?? j) as Map).cast<String, dynamic>();
    return AppSettings.fromJson(s);
  }

  /// Restores a backup; existing profiles with the same id are replaced.
  /// Returns the restored settings (the caller applies them).
  Future<({AppSettings settings, int profiles, int nodes})> restore(
    String blob,
    String passphrase,
  ) async {
    final data = await core.backupDecrypt(blob.trim(), passphrase);
    final v = (data['schema'] as int?) ?? 0;
    if (v < 1 || v > schema)
      throw const FormatException('unsupported backup version');
    var nodeCount = 0;
    final profiles = (data['profiles'] as List).cast<Map>();
    for (final entry in profiles) {
      final p = Profile.fromMap(
        (entry['profile'] as Map).cast<String, Object?>(),
      );
      await repo.deleteProfile(p.id);
      await repo.saveProfile(p);
      final nodes = (entry['nodes'] as List)
          .cast<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      await repo.importNodes(p.id, nodes, replace: false);
      nodeCount += nodes.length;
    }
    return (
      settings: AppSettings.fromJson(
        (data['settings'] as Map).cast<String, dynamic>(),
      ),
      profiles: profiles.length,
      nodes: nodeCount,
    );
  }
}
