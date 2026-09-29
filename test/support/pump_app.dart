import 'package:easyvpn/app.dart';
import 'package:easyvpn/core/bridge/core_bridge.dart';
import 'package:easyvpn/core/bridge/unavailable_transport.dart';
import 'package:easyvpn/core/database/app_database.dart';
import 'package:easyvpn/core/database/node_repository.dart';
import 'package:easyvpn/core/models/models.dart';
import 'package:easyvpn/core/providers/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

class TestApp {
  TestApp(this.env, this.transport);
  final AppEnv env;
  final FakeTransport? transport;
}

Future<TestApp> pumpApp(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(onboarded: true),
  CoreTransport? transport,
  Size size = const Size(420, 900),
  Future<void> Function(NodeRepository repo)? seed,
}) async {
  // The host platform channel does not exist in tests; answer with null.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('easyvpn/platform'),
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('easyvpn/platform'),
      null,
    ),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final t = transport ?? FakeTransport();
  final core = CoreBridge(t);
  final db = AppDatabase.memory();
  final repo = NodeRepository(db, core, 'key');
  await repo.saveProfile(const Profile(id: 'p1', name: 'Main'));
  if (seed != null) await seed(repo);
  final env = AppEnv(
    core: core,
    db: db,
    repo: repo,
    dataDir: '/tmp',
    initialSettings: settings,
    keystoreBacked: true,
    localPass: 'pw',
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [envProvider.overrideWithValue(env)],
      child: const EasyVpnApp(startMinimized: false, desktopShell: false),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
  return TestApp(env, t is FakeTransport ? t : null);
}

TestApp unavailable() => throw UnimplementedError();

CoreTransport unavailableTransport() => UnavailableTransport('test: no core');
