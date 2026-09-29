import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/bootstrap.dart';
import 'core/providers/env.dart';
import 'platform/desktop_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final startMinimized = args.contains('--minimized');

  FlutterError.onError = (d) {
    FlutterError.presentError(d);
  };

  final env = await bootstrap();
  if (isDesktopPlatform) {
    await initDesktopWindow(
      startMinimized: startMinimized || env.initialSettings.startMinimized,
    );
  }

  runApp(
    ProviderScope(
      overrides: [envProvider.overrideWithValue(env)],
      child: EasyVpnApp(startMinimized: startMinimized),
    ),
  );
}
