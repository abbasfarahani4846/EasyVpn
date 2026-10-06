import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/easy/update/easy_installer.dart';
import 'package:fl_clash/easy/update/easy_updater.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> _releases({String sha = 'abcdef1'}) => [
  {
    'tag_name': 'nightly',
    'name': 'Nightly (main @ $sha)',
    'draft': false,
    'body': 'Automatic build.\n<!-- easy-build:$sha -->',
    'assets': [
      {
        'name': 'EasyEasyVpn-windows-x64.zip',
        'browser_download_url': 'https://example.com/win.zip',
        'size': 100,
      },
      {
        'name': 'EasyEasyVpn-linux-x64.tar.gz',
        'browser_download_url': 'https://example.com/linux.tgz',
        'size': 90,
      },
      {
        'name': 'EasyVpn-0.8.99-android-arm64-v8a.apk',
        'browser_download_url': 'https://example.com/arm64.apk',
        'size': 80,
      },
      {
        'name': 'EasyVpn-0.8.99-android-x86_64.apk',
        'browser_download_url': 'https://example.com/x64.apk',
        'size': 85,
      },
    ],
  },
];

void main() {
  test('a release built from another commit is offered with its asset', () {
    final info = EasyUpdater.parse(
      _releases(),
      currentSha: '1234567',
      platform: UpdatePlatform.windows,
    );
    expect(info, isNotNull);
    expect(info!.sha, 'abcdef1');
    expect(info.assetName, 'EasyEasyVpn-windows-x64.zip');
    expect(info.assetUrl, 'https://example.com/win.zip');
    expect(info.assetSize, 100);
    expect(info.notes, 'Automatic build.');
  });

  test('the same commit, a dev build and malformed data offer nothing', () {
    for (final current in ['abcdef1', 'abcdef1234567']) {
      expect(
        EasyUpdater.parse(
          _releases(),
          currentSha: current,
          platform: UpdatePlatform.windows,
        ),
        isNull,
      );
    }
    expect(
      EasyUpdater.parse(
        _releases(),
        currentSha: 'dev',
        platform: UpdatePlatform.windows,
      ),
      isNull,
    );
    for (final data in [
      null,
      'x',
      <Object?>[],
      {'message': 'Not Found'},
    ]) {
      expect(
        EasyUpdater.parse(
          data,
          currentSha: '1234567',
          platform: UpdatePlatform.windows,
        ),
        isNull,
      );
    }
  });

  test('drafts and releases without the build marker are skipped', () {
    final data = [
      {'draft': true, 'body': 'easy-build:abcdef1', 'assets': []},
      {'tag_name': 'v1', 'body': 'no marker', 'assets': []},
      ..._releases(sha: 'fedcba9'),
    ];
    final info = EasyUpdater.parse(
      data,
      currentSha: '1234567',
      platform: UpdatePlatform.linux,
    );
    expect(info!.sha, 'fedcba9');
    expect(info.assetName, 'EasyEasyVpn-linux-x64.tar.gz');
  });

  test('android picks the apk of its own abi and others get none', () {
    String? pick(String abi) => EasyUpdater.parse(
      _releases(),
      currentSha: '1234567',
      platform: UpdatePlatform.android,
      abi: abi,
    )?.assetName;
    expect(pick('arm64-v8a'), 'EasyVpn-0.8.99-android-arm64-v8a.apk');
    expect(pick('x86_64'), 'EasyVpn-0.8.99-android-x86_64.apk');
    expect(pick('armeabi-v7a'), isNull);
    expect(
      EasyUpdater.parse(
        _releases(),
        currentSha: '1234567',
        platform: UpdatePlatform.other,
      ),
      isNull,
    );
  });

  group('download', () {
    late Directory dir;
    late HttpServer server;
    late Dio dio;
    final payload = List<int>.generate(50000, (i) => i % 251);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('easy_update_test');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.add(payload);
        await request.response.close();
      });
      dio = Dio();
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    EasyUpdateInfo info(int size) => EasyUpdateInfo(
      tag: 'nightly',
      name: 'n',
      sha: 'abcdef1',
      notes: '',
      assetName: 'a.zip',
      assetUrl: 'http://127.0.0.1:${server.port}/a.zip',
      assetSize: size,
    );

    test('saves the file and reports progress up to 1', () async {
      final progress = <double>[];
      final file = await EasyUpdater.download(
        info(payload.length),
        dir,
        onProgress: progress.add,
        dio: dio,
      );
      expect(await file.readAsBytes(), payload);
      expect(progress.last, 1.0);
    });

    test('a file of the wrong size is rejected and removed', () async {
      await expectLater(
        EasyUpdater.download(
          info(payload.length + 1),
          dir,
          onProgress: (_) {},
          dio: dio,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(File('${dir.path}/a.zip').existsSync(), isFalse);
    });
  });

  group('installer', () {
    test('the windows script waits for the app and relaunches it', () {
      const script = EasyInstaller.windowsScript;
      expect(script, contains('Wait-Process -Id \$AppPid'));
      expect(script, contains('robocopy \$Source \$Dest /E'));
      expect(
        script.indexOf('Wait-Process'),
        lessThan(script.indexOf('robocopy')),
      );
      expect(script.trim().split('\n').last, 'Start-Process -FilePath \$Exe');
    });

    test('the linux script waits for the app before copying', () {
      const script = EasyInstaller.linuxScript;
      expect(script.indexOf('kill -0'), lessThan(script.indexOf('cp -rf')));
      expect(script, contains('nohup "\$EXE"'));
    });

    test('contentRoot finds the app files at the root or in one folder', () {
      final root = Directory.systemTemp.createTempSync('easy_root');
      addTearDown(() => root.deleteSync(recursive: true));
      final sep = Platform.pathSeparator;
      final nested = Directory('${root.path}${sep}pkg')..createSync();
      expect(EasyInstaller.contentRoot(root, 'EasyVpn.exe').path, nested.path);
      File('${root.path}${sep}EasyVpn.exe').writeAsStringSync('x');
      expect(EasyInstaller.contentRoot(root, 'EasyVpn.exe').path, root.path);
    });
  });
}
