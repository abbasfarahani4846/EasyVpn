import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'psiphon_ladder.dart';

enum PsiphonStage { idle, starting, dialling, connected, failed }

class PsiphonStatus {
  final PsiphonStage stage;
  final String? rung;
  final int rungIndex;
  final int rungCount;
  final String? protocol;
  final String? error;

  const PsiphonStatus({
    this.stage = PsiphonStage.idle,
    this.rung,
    this.rungIndex = 0,
    this.rungCount = 0,
    this.protocol,
    this.error,
  });
}

class PsiphonBinary {
  const PsiphonBinary._();

  static const fileName = 'psiphon-tunnel-core-i686.exe';

  /// `EASY_PSIPHON_EXE`, then `easy_bin/psiphon/` beside the app or in any
  /// parent folder (so a development build finds the project's copy).
  static File? resolve() {
    final override = Platform.environment['EASY_PSIPHON_EXE'];
    if (override != null && File(override).existsSync()) return File(override);
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final candidate = File(
        '${dir.path}${Platform.pathSeparator}easy_bin'
        '${Platform.pathSeparator}psiphon${Platform.pathSeparator}$fileName',
      );
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }
}

/// Runs the Psiphon core as a child process and walks the ladder of rungs
/// until one carries a tunnel, remembering which one did.
class PsiphonManager {
  PsiphonManager._();

  static final PsiphonManager instance = PsiphonManager._();

  static const socksPort = 20830;
  static const _winnerKey = 'easy.psiphon.winner';

  final ValueNotifier<PsiphonStatus> status = ValueNotifier(
    const PsiphonStatus(),
  );

  Process? _process;
  int _session = 0;
  bool _stopRequested = false;

  bool get isRunning =>
      status.value.stage != PsiphonStage.idle &&
      status.value.stage != PsiphonStage.failed;

  Future<void> start() async {
    if (isRunning) return;
    final exe = PsiphonBinary.resolve();
    if (exe == null) {
      status.value = const PsiphonStatus(
        stage: PsiphonStage.failed,
        error: 'binary-missing',
      );
      return;
    }
    final session = ++_session;
    _stopRequested = false;
    status.value = const PsiphonStatus(stage: PsiphonStage.starting);
    final dataDir = await _dataDir();
    final prefs = await SharedPreferences.getInstance();
    final order = PsiphonLadder.order(winner: prefs.getString(_winnerKey));

    unawaited(_loop(session, exe, dataDir, order, prefs));
  }

  Future<void> stop() async {
    _stopRequested = true;
    _session++;
    await _kill();
    status.value = const PsiphonStatus();
  }

  Future<String> _dataDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}easy_psiphon');
    await Directory('${dir.path}${Platform.pathSeparator}osl').create(
      recursive: true,
    );
    return dir.path.replaceAll('\\', '/');
  }

  Future<void> _loop(
    int session,
    File exe,
    String dataDir,
    List<PsiphonRung> order,
    SharedPreferences prefs,
  ) async {
    while (session == _session && !_stopRequested) {
      for (var i = 0; i < order.length; i++) {
        if (session != _session) return;
        final rung = order[i];
        final connected = await _runRung(
          session,
          exe,
          dataDir,
          rung,
          i,
          order.length,
        );
        if (session != _session) return;
        if (connected) {
          await prefs.setString(_winnerKey, rung.name);
          // The tunnel ended (process exited): start over from the winner.
          order = PsiphonLadder.order(winner: rung.name);
          status.value = const PsiphonStatus(stage: PsiphonStage.starting);
          break;
        }
      }
    }
  }

  /// Returns true once a tunnel was up and has since ended.
  Future<bool> _runRung(
    int session,
    File exe,
    String dataDir,
    PsiphonRung rung,
    int index,
    int count,
  ) async {
    await _kill();
    final config = PsiphonLadder.buildConfig(
      rung: rung,
      dataDir: dataDir,
      socksPort: socksPort,
    );
    final configFile = File('$dataDir/psiphon-${rung.name}.config');
    await configFile.writeAsString(jsonEncode(config));

    status.value = PsiphonStatus(
      stage: PsiphonStage.dialling,
      rung: rung.name,
      rungIndex: index,
      rungCount: count,
    );
    final Process process;
    try {
      process = await Process.start(exe.path, ['-config', configFile.path]);
    } catch (e) {
      status.value = PsiphonStatus(
        stage: PsiphonStage.failed,
        error: e.toString(),
      );
      return false;
    }
    _process = process;
    final done = Completer<bool>();
    var connected = false;
    String? protocol;

    final sub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          Map<String, dynamic>? notice;
          try {
            notice = jsonDecode(line) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          final type = notice['noticeType'];
          final data = (notice['data'] as Map?) ?? const {};
          if (type == 'ConnectingServer') {
            protocol = '${data['protocol']}';
          }
          if (type == 'Tunnels' && (data['count'] ?? 0) >= 1 && !connected) {
            connected = true;
            status.value = PsiphonStatus(
              stage: PsiphonStage.connected,
              rung: rung.name,
              rungIndex: index,
              rungCount: count,
              protocol: protocol,
            );
          }
          if (type == 'Tunnels' && data['count'] == 0 && connected) {
            // Lost the tunnel; let the loop restart from this rung.
            if (!done.isCompleted) done.complete(true);
          }
        });
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((_) {
        if (!done.isCompleted) done.complete(connected);
      }),
    );

    final timer = Timer(Duration(seconds: rung.budgetSeconds), () {
      if (!connected && !done.isCompleted) done.complete(false);
    });
    final result = await done.future;
    timer.cancel();
    await sub.cancel();
    if (!result || session != _session) await _kill();
    return result;
  }

  Future<void> _kill() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }
}
