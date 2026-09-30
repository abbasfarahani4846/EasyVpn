import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models/models.dart';
import '../core/providers/core_provider.dart';
import '../core/providers/env.dart';
import '../core/providers/settings_provider.dart';
import '../l10n/strings.dart';

bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Desktop window geometry per layout. Sizes are bounded so the UI keeps a
/// fixed, predictable arrangement instead of stretching across the screen.
class WindowProfile {
  const WindowProfile(this.size, this.min, this.max);
  final Size size;
  final Size min;
  final Size max;

  static const simple = WindowProfile(
    Size(400, 740),
    Size(360, 620),
    Size(520, 900),
  );
  static const mini = WindowProfile(
    Size(320, 440),
    Size(320, 440),
    Size(320, 440),
  );
  static const advanced = WindowProfile(
    Size(1060, 720),
    Size(820, 600),
    Size(1440, 960),
  );

  static WindowProfile of(AppSettings s) =>
      s.uiMode == 'advanced' ? advanced : (s.miniWindow ? mini : simple);
}

Future<void> applyWindowProfile(WindowProfile p) async {
  // Order matters: relax bounds first so the new size is accepted.
  await windowManager.setMinimumSize(const Size(200, 200));
  await windowManager.setMaximumSize(const Size(8000, 8000));
  await windowManager.setSize(p.size);
  await windowManager.setMinimumSize(p.min);
  await windowManager.setMaximumSize(p.max);
  // Note: no setResizable(false): on Linux/GTK it snaps the window to its
  // default size. min == max already makes the mini window fixed.
  await windowManager.setSize(p.size);
}

/// Call once before `runApp` on desktop.
Future<void> initDesktopWindow({
  required bool startMinimized,
  WindowProfile profile = WindowProfile.simple,
}) async {
  await windowManager.ensureInitialized();
  final opts = WindowOptions(
    size: profile.size,
    minimumSize: profile.min,
    maximumSize: profile.max,
    center: true,
    title: 'EasyVPN',
    titleBarStyle: TitleBarStyle.normal,
    backgroundColor: const Color(0xFF070B16),
  );
  await windowManager.waitUntilReadyToShow(opts, () async {
    if (!startMinimized) {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  await windowManager.setPreventClose(true);
}

/// Window + system-tray behavior for desktop: close-to-tray, minimize start,
/// tray menu (show / connect / quick node switch / quit). The core restores the
/// OS proxy on exit, so quitting here always goes through `disconnect`.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({
    super.key,
    required this.child,
    required this.startMinimized,
  });
  final Widget child;
  final bool startMinimized;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell>
    with TrayListener, WindowListener {
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _setupTray();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _setupTray() async {
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
      );
      await trayManager.setToolTip('EasyVPN');
      await _rebuildMenu();
    } catch (_) {
      // Tray is optional (e.g. Linux without AppIndicator): the window still works.
    }
  }

  Future<void> _rebuildMenu() async {
    final s = S(ui.PlatformDispatcher.instance.locale);
    final connected = ref.read(coreControllerProvider).isConnected;
    final env = ref.read(envProvider);
    final top = await env.repo.topNodeIds(limit: 10);
    final items = <MenuItem>[
      MenuItem(key: 'show', label: s.t('tray.show')),
      MenuItem(
        key: 'toggle',
        label: connected ? s.t('tray.disconnect') : s.t('tray.connect'),
      ),
      MenuItem(key: 'fastest', label: '⚡ ${s.t('home.fastest')}'),
      MenuItem.separator(),
    ];
    for (final id in top) {
      final row = await env.repo.nodeRow(id);
      if (row != null)
        items.add(
          MenuItem(
            key: 'node:$id',
            label: '${row.name}  ${row.latency > 0 ? '${row.latency} ms' : ''}',
          ),
        );
    }
    if (top.isNotEmpty) items.add(MenuItem.separator());
    items.add(MenuItem(key: 'quit', label: s.t('tray.quit')));
    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() async {
    await _rebuildMenu();
    await trayManager.popUpContextMenu();
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    final key = item.key ?? '';
    final ctl = ref.read(coreControllerProvider.notifier);
    if (key == 'show') {
      await _show();
    } else if (key == 'toggle') {
      await ctl.toggle();
    } else if (key == 'fastest') {
      await ctl.connectFastest();
    } else if (key == 'quit') {
      await _quit();
    } else if (key.startsWith('node:')) {
      await ctl.selectNode(key.substring(5));
    }
  }

  Future<void> _quit() async {
    _quitting = true;
    try {
      await ref.read(envProvider).core.shutdown();
    } catch (_) {}
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onWindowClose() async {
    if (_quitting) return;
    final toTray = ref.read(settingsProvider).closeToTray;
    if (toTray) {
      await windowManager.hide();
    } else {
      await _quit();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the tray menu label in sync with the connection state.
    ref.listen<CoreState>(coreControllerProvider, (_, _) => _rebuildMenu());
    // Resize the window when the layout changes (simple / mini / advanced).
    ref.listen<WindowProfile>(
      settingsProvider.select(WindowProfile.of),
      (_, p) => applyWindowProfile(p).catchError((_) {}),
    );
    return widget.child;
  }
}
