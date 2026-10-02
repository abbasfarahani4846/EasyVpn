import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../bridge/core_bridge.dart';
import '../providers/env.dart';
import '../providers/settings_provider.dart';
import '../util/platform_service.dart';

/// Build identity stamped by CI (`--dart-define=BUILD_LABEL=...`).
const buildLabel = String.fromEnvironment('BUILD_LABEL', defaultValue: '1.0.2');
const _buildChannelDefine = String.fromEnvironment('BUILD_CHANNEL');

/// 'stable' for tagged releases, 'nightly' otherwise (CI may override).
String get buildChannel => _buildChannelDefine.isNotEmpty
    ? _buildChannelDefine
    : (buildLabel.startsWith('nightly') || buildLabel == 'dev'
          ? 'nightly'
          : 'stable');

enum UpdatePhase { idle, checking, available, downloading, ready, error }

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.latest = '',
    this.notes = '',
    this.pageUrl = '',
    this.progress = 0,
    this.error = '',
    this.path = '',
    this.asset,
    this.sha256 = '',
  });
  final UpdatePhase phase;
  final String latest;
  final String notes;
  final String pageUrl;
  final double progress; // 0..1
  final String error;
  final String path; // downloaded + verified file
  final Map<String, dynamic>? asset;
  final String sha256;

  bool get hasUpdate =>
      phase == UpdatePhase.available ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.ready;

  UpdateState copyWith({
    UpdatePhase? phase,
    double? progress,
    String? error,
    String? path,
  }) => UpdateState(
    phase: phase ?? this.phase,
    latest: latest,
    notes: notes,
    pageUrl: pageUrl,
    progress: progress ?? this.progress,
    error: error ?? this.error,
    path: path ?? this.path,
    asset: asset,
    sha256: sha256,
  );
}

/// Checks GitHub Releases (through the Go core, verified by SHA-256) and
/// installs updates the way each platform allows.
class UpdateNotifier extends Notifier<UpdateState> {
  Timer? _timer;
  Timer? _initialTimer;
  StreamSubscription? _sub;

  @override
  UpdateState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _initialTimer?.cancel();
      _sub?.cancel();
    });
    final auto = ref.watch(settingsProvider.select((s) => s.autoUpdateCheck));
    _timer?.cancel();
    _initialTimer?.cancel();
    if (auto && !Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialTimer = Timer(const Duration(seconds: 20), () => check(silent: true));
      _timer = Timer.periodic(
        const Duration(hours: 12),
        (_) => check(silent: true),
      );
    }
    return const UpdateState();
  }

  CoreBridge get _core => ref.read(envProvider).core;

  String get channel {
    final c = ref.read(settingsProvider).updateChannel;
    return c.isEmpty ? buildChannel : c;
  }

  Future<Map<String, dynamic>> target() async {
    final t = <String, dynamic>{'platform': _platform(), 'arch': _arch()};
    if (Platform.isWindows || Platform.isLinux) {
      final dir = p.dirname(Platform.resolvedExecutable);
      t['portable'] = await File(p.join(dir, 'portable')).exists();
      if (Platform.isLinux && dir.startsWith('/opt/easyvpn')) {
        t['package'] = 'deb';
      }
    }
    return t;
  }

  Future<void> check({bool silent = false}) async {
    if (state.phase == UpdatePhase.downloading) return;
    state = const UpdateState(phase: UpdatePhase.checking);
    try {
      final r = await _core.updateCheck(
        channel: channel,
        current: buildLabel,
        target: await target(),
      );
      if (r['available'] == true) {
        state = UpdateState(
          phase: UpdatePhase.available,
          latest: r['latest'] as String? ?? '',
          notes: r['notes'] as String? ?? '',
          pageUrl: r['page_url'] as String? ?? '',
          asset: (r['asset'] as Map?)?.cast<String, dynamic>(),
          sha256: r['sha256'] as String? ?? '',
        );
      } else {
        state = UpdateState(latest: r['latest'] as String? ?? '');
      }
    } catch (e) {
      state = silent
          ? const UpdateState()
          : UpdateState(phase: UpdatePhase.error, error: '$e');
    }
  }

  Future<void> download() async {
    final a = state.asset;
    if (a == null) return;
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    _sub?.cancel();
    _sub = _core.events.listen((batch) {
      for (final e in batch) {
        if (e.type != 'updateProgress') continue;
        final m = (e.payload as Map).cast<String, dynamic>();
        final done = (m['done'] as num?)?.toDouble() ?? 0;
        final total = (m['total'] as num?)?.toDouble() ?? 0;
        if (total > 0) state = state.copyWith(progress: done / total);
      }
    });
    try {
      final path = await _core.updateDownload(
        url: a['browser_download_url'] as String,
        name: a['name'] as String,
        sha256: state.sha256,
      );
      state = state.copyWith(phase: UpdatePhase.ready, path: path, progress: 1);
    } catch (e) {
      state = state.copyWith(phase: UpdatePhase.error, error: '$e');
    } finally {
      await _sub?.cancel();
      _sub = null;
    }
  }

  /// Installs the verified file. Desktop archive installs exit the app and let
  /// a small script swap the files and relaunch.
  Future<void> install() async {
    final path = state.path;
    if (path.isEmpty) return;
    if (Platform.isAndroid) {
      await PlatformService.installApk(path);
      return;
    }
    if (Platform.isWindows && path.endsWith('.zip')) {
      await _swapAndRestartWindows(path);
    } else if (Platform.isLinux && path.endsWith('.tar.gz')) {
      await _swapAndRestartLinux(path);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [
        '-R',
        path,
      ], mode: ProcessStartMode.detached);
    }
  }

  Future<void> _swapAndRestartWindows(String zip) async {
    final appDir = p.dirname(Platform.resolvedExecutable);
    final exe = p.basename(Platform.resolvedExecutable);
    final stage = p.join(p.dirname(zip), 'stage');
    final script = File(p.join(p.dirname(zip), 'apply_update.cmd'));
    await script.writeAsString('''@echo off
:wait
tasklist /FI "PID eq $pid" 2>nul | find "$pid" >nul && (timeout /t 1 /nobreak >nul & goto wait)
rmdir /s /q "$stage" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -LiteralPath '$zip' -DestinationPath '$stage'"
robocopy "$stage" "$appDir" /E /XF portable *.db *.db-shm *.db-wal >nul
start "" "$appDir\\$exe"
''');
    await Process.start(
      'cmd',
      ['/c', script.path],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    await _exitForUpdate();
  }

  Future<void> _swapAndRestartLinux(String tgz) async {
    final appDir = p.dirname(Platform.resolvedExecutable);
    final exe = Platform.resolvedExecutable;
    final script = File(p.join(p.dirname(tgz), 'apply_update.sh'));
    await script.writeAsString('''#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 1; done
tar -xzf "$tgz" -C "$appDir" --exclude=./portable --exclude=./data
exec "$exe" >/dev/null 2>&1
''');
    await Process.run('chmod', ['+x', script.path]);
    await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
    await _exitForUpdate();
  }

  Future<void> _exitForUpdate() async {
    try {
      await _core.shutdown(); // restores the OS proxy, stops the tunnel
    } catch (_) {}
    exit(0);
  }

  static String _platform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }

  static String _arch() {
    final v = Platform.version.toLowerCase();
    if (v.contains('x64') || v.contains('x86_64') || v.contains('amd64')) {
      return 'x86_64';
    }
    return 'arm64';
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);
