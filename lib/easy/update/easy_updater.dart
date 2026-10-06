import 'dart:io';

import 'package:dio/dio.dart';

import 'build_info.dart';

const easyUpdateRepository = 'abbasfarahani4846/EasyVpn';

enum UpdatePlatform { android, windows, linux, other }

class EasyUpdateInfo {
  final String tag;
  final String name;
  final String sha;
  final String notes;
  final String assetName;
  final String assetUrl;
  final int assetSize;

  const EasyUpdateInfo({
    required this.tag,
    required this.name,
    required this.sha,
    required this.notes,
    required this.assetName,
    required this.assetUrl,
    required this.assetSize,
  });
}

/// Looks for a newer build among the repository's releases. A release is the
/// newest build when its notes carry `easy-build:<commit>` and that commit is
/// not the one this app was built from.
class EasyUpdater {
  const EasyUpdater._();

  static final _marker = RegExp(r'easy-build:([0-9a-f]{7,40})');

  static UpdatePlatform get platform {
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    if (Platform.isLinux) return UpdatePlatform.linux;
    return UpdatePlatform.other;
  }

  /// The ABI the Dart VM runs on, which is the one the APK has to match.
  static String get androidAbi {
    final version = Platform.version;
    if (version.contains('android_arm64')) return 'arm64-v8a';
    if (version.contains('android_arm')) return 'armeabi-v7a';
    return 'x86_64';
  }

  static String? assetFor(
    UpdatePlatform platform,
    Iterable<String> names, {
    String abi = 'arm64-v8a',
  }) {
    final wanted = switch (platform) {
      UpdatePlatform.windows => (String n) => n.endsWith('windows-x64.zip'),
      UpdatePlatform.linux => (String n) => n.endsWith('linux-x64.tar.gz'),
      UpdatePlatform.android =>
        (String n) => n.endsWith('.apk') && n.contains('android-$abi'),
      UpdatePlatform.other => (String n) => false,
    };
    for (final name in names) {
      if (wanted(name)) return name;
    }
    return null;
  }

  static EasyUpdateInfo? parse(
    Object? releases, {
    required String currentSha,
    required UpdatePlatform platform,
    String abi = 'arm64-v8a',
  }) {
    if (currentSha == 'dev' || releases is! List) return null;
    for (final release in releases) {
      if (release is! Map || release['draft'] == true) continue;
      final body = '${release['body'] ?? ''}';
      final sha = _marker.firstMatch(body)?.group(1);
      if (sha == null) continue;
      if (sha.startsWith(currentSha) || currentSha.startsWith(sha)) {
        return null;
      }
      final assets = [
        for (final a in release['assets'] as List? ?? const [])
          if (a is Map) a,
      ];
      final name = assetFor(platform, [
        for (final a in assets) '${a['name']}',
      ], abi: abi);
      if (name == null) return null;
      final asset = assets.firstWhere((a) => '${a['name']}' == name);
      return EasyUpdateInfo(
        tag: '${release['tag_name']}',
        name: '${release['name'] ?? release['tag_name']}',
        sha: sha,
        notes: body
            .replaceAll(_marker, '')
            .replaceAll(RegExp(r'<!--\s*-->'), '')
            .trim(),
        assetName: name,
        assetUrl: '${asset['browser_download_url']}',
        assetSize: (asset['size'] as num?)?.toInt() ?? 0,
      );
    }
    return null;
  }

  static Future<EasyUpdateInfo?> check({
    Dio? dio,
    String currentSha = easyBuildSha,
  }) async {
    final client = dio ?? Dio();
    try {
      final response = await client.get<Object?>(
        'https://api.github.com/repos/$easyUpdateRepository/releases',
        queryParameters: {'per_page': 5},
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/vnd.github+json'},
        ),
      );
      if (response.statusCode != 200) return null;
      return parse(
        response.data,
        currentSha: currentSha,
        platform: platform,
        abi: androidAbi,
      );
    } catch (_) {
      return null;
    } finally {
      if (dio == null) client.close();
    }
  }

  static Future<File> download(
    EasyUpdateInfo info,
    Directory directory, {
    required void Function(double progress) onProgress,
    Dio? dio,
  }) async {
    final client = dio ?? Dio();
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${info.assetName}',
    );
    try {
      await client.download(
        info.assetUrl,
        file.path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          final size = total > 0 ? total : info.assetSize;
          if (size > 0) onProgress((received / size).clamp(0.0, 1.0));
        },
      );
    } finally {
      if (dio == null) client.close();
    }
    if (info.assetSize > 0 && await file.length() != info.assetSize) {
      await file.delete();
      throw const FormatException('The downloaded file is incomplete');
    }
    return file;
  }
}
