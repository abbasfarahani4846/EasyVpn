import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies the data folder of the builds made before the rename into the new
/// one the first time the app starts. The old folder is left untouched.
class LegacyData {
  const LegacyData._();

  static List<Directory> defaultSources() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData == null) return const [];
      return [Directory(p.join(appData, 'com.follow', 'clash'))];
    }
    if (Platform.isLinux) {
      final share =
          env['XDG_DATA_HOME'] ??
          (env['HOME'] == null
              ? null
              : p.join(env['HOME']!, '.local', 'share'));
      if (share == null) return const [];
      return [Directory(p.join(share, 'com.follow.clash'))];
    }
    return const [];
  }

  static bool _inUse(Directory dir) =>
      File(p.join(dir.path, 'database.sqlite')).existsSync() ||
      File(p.join(dir.path, 'config.yaml')).existsSync();

  static bool _skip(String name) =>
      name.endsWith('.lock') || name.endsWith('.part');

  static Future<bool> migrate(
    Directory target, {
    List<Directory>? sources,
  }) async {
    try {
      if (_inUse(target)) return false;
      for (final source in sources ?? defaultSources()) {
        if (!source.existsSync() || !_inUse(source)) continue;
        await _copy(source, target);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (_skip(name)) continue;
      final destination = p.join(to.path, name);
      if (entity is Directory) {
        await _copy(entity, Directory(destination));
      } else if (entity is File) {
        await entity.copy(destination);
      }
    }
  }
}
