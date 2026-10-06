import 'dart:io';

import 'package:easy_vpn/common/legacy_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory oldDir;
  late Directory newDir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('legacy_data');
    oldDir = Directory('${root.path}/old')..createSync();
    newDir = Directory('${root.path}/new');
    File('${oldDir.path}/database.sqlite').writeAsStringSync('db');
    Directory('${oldDir.path}/profiles').createSync();
    File('${oldDir.path}/profiles/1.yaml').writeAsStringSync('proxies: []');
    File('${oldDir.path}/FlClash.lock').writeAsStringSync('lock');
    File('${oldDir.path}/list.mrs.part').writeAsStringSync('half');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'copies the old data, skips locks and partial files, keeps the source',
    () async {
      expect(await LegacyData.migrate(newDir, sources: [oldDir]), isTrue);
      expect(File('${newDir.path}/database.sqlite').readAsStringSync(), 'db');
      expect(File('${newDir.path}/profiles/1.yaml').existsSync(), isTrue);
      expect(File('${newDir.path}/FlClash.lock').existsSync(), isFalse);
      expect(File('${newDir.path}/list.mrs.part').existsSync(), isFalse);
      expect(File('${oldDir.path}/database.sqlite').existsSync(), isTrue);
    },
  );

  test('a folder that already holds data is never overwritten', () async {
    newDir.createSync();
    File('${newDir.path}/database.sqlite').writeAsStringSync('new');
    expect(await LegacyData.migrate(newDir, sources: [oldDir]), isFalse);
    expect(File('${newDir.path}/database.sqlite').readAsStringSync(), 'new');
    expect(File('${newDir.path}/profiles/1.yaml').existsSync(), isFalse);
  });

  test('a missing or empty source changes nothing', () async {
    expect(
      await LegacyData.migrate(
        newDir,
        sources: [Directory('${root.path}/none'), Directory(root.path)],
      ),
      isFalse,
    );
    expect(newDir.existsSync(), isFalse);
  });
}
