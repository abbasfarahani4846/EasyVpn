import 'dart:async';
import 'dart:io';

import 'package:easy_vpn/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'build_info.dart';
import 'easy_installer.dart';
import 'easy_updater.dart';

enum EasyUpdatePhase { none, available, downloading, installing, failed }

class EasyUpdateState {
  final EasyUpdatePhase phase;
  final EasyUpdateInfo? info;
  final double progress;
  final String? error;

  const EasyUpdateState({
    this.phase = EasyUpdatePhase.none,
    this.info,
    this.progress = 0,
    this.error,
  });

  EasyUpdateState copyWith({
    EasyUpdatePhase? phase,
    double? progress,
    String? error,
  }) => EasyUpdateState(
    phase: phase ?? this.phase,
    info: info,
    progress: progress ?? this.progress,
    error: error,
  );
}

final easyUpdateProvider =
    NotifierProvider<EasyUpdateNotifier, EasyUpdateState>(
      EasyUpdateNotifier.new,
    );

class EasyUpdateNotifier extends Notifier<EasyUpdateState> {
  Timer? _timer;

  @override
  EasyUpdateState build() {
    ref.onDispose(() => _timer?.cancel());
    return const EasyUpdateState();
  }

  /// Checks now and again every few hours while the app stays open.
  void start() {
    if (easyBuildSha == 'dev' || _timer != null) return;
    unawaited(check());
    _timer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(check()),
    );
  }

  Future<void> check() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return;
    final phase = state.phase;
    if (phase == EasyUpdatePhase.downloading ||
        phase == EasyUpdatePhase.installing) {
      return;
    }
    final info = await EasyUpdater.check();
    if (info == null) return;
    state = EasyUpdateState(phase: EasyUpdatePhase.available, info: info);
  }

  Future<void> downloadAndInstall() async {
    final info = state.info;
    if (info == null || state.phase == EasyUpdatePhase.downloading) return;
    state = state.copyWith(phase: EasyUpdatePhase.downloading, progress: 0);
    try {
      final base = await getTemporaryDirectory();
      final file = await EasyUpdater.download(
        info,
        Directory('${base.path}${Platform.pathSeparator}easy_update'),
        onProgress: (p) => state = state.copyWith(progress: p),
      );
      state = state.copyWith(phase: EasyUpdatePhase.installing, progress: 1);
      await EasyInstaller.install(file, platform: EasyUpdater.platform.name);
      if (EasyUpdater.platform == UpdatePlatform.android) {
        state = state.copyWith(phase: EasyUpdatePhase.available);
      } else {
        await ref.read(systemActionProvider.notifier).handleExit();
      }
    } catch (e) {
      state = state.copyWith(phase: EasyUpdatePhase.failed, error: '$e');
    }
  }
}
