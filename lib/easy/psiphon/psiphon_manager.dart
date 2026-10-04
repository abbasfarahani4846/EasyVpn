import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_fingerprint.dart';
import 'psiphon_ladder.dart';
import 'psiphon_nodes.dart';

enum PsiphonStage { idle, starting, dialling, connected, failed }

class PsiphonStatus {
  final PsiphonStage stage;
  final String? rung;
  final String? protocol;
  final String? error;

  /// How many full passes over the methods found nothing yet.
  final int pass;

  /// Why the previous attempt failed: refused | timeout | blocked.
  final String? hint;

  const PsiphonStatus({
    this.stage = PsiphonStage.idle,
    this.rung,
    this.protocol,
    this.error,
    this.pass = 0,
    this.hint,
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

/// Runs the Psiphon core as a child process in the background. It walks the
/// ladder of methods until one carries a tunnel, remembers per network which
/// one did (and refreshes that every time it connects), and starts over when
/// the network changes or the tunnel drops.
class PsiphonManager {
  PsiphonManager._();

  static final PsiphonManager instance = PsiphonManager._();

  static const socksPort = PsiphonNodes.socksPort;
  static const _networksKey = 'easy.psiphon.networks';
  static const _winnerKey = 'easy.psiphon.winner';
  static const _regionKey = 'easy.psiphon.region';

  /// True when [config] holds the node [PsiphonManager] serves, so the app
  /// knows it must run the Psiphon core while that profile is in use.
  static bool isPsiphonNodeIn(Map<String, dynamic> config) {
    for (final item in (config['proxies'] as List? ?? const [])) {
      if (item is Map &&
          item['type'] == 'socks5' &&
          item['server'] == '127.0.0.1' &&
          '${item['port']}' == '$socksPort') {
        return true;
      }
    }
    return false;
  }

  final ValueNotifier<PsiphonStatus> status = ValueNotifier(
    const PsiphonStatus(),
  );

  Process? _process;
  Timer? _networkWatch;
  int _session = 0;
  bool _stopRequested = false;
  bool _networkChanged = false;
  String? _fingerprint;
  String? _upstream;
  String? _lastHint;
  final List<String> _log = [];
  String? _dataDirPath;

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
    _dataDirPath = dataDir;
    await _seed(exe, dataDir);
    unawaited(_loop(session, exe, dataDir));
  }

  /// Starts the core and completes once a tunnel is up, or after [timeout]
  /// (or when stopped / failed), so connecting the profile waits for Psiphon.
  Future<bool> startAndWait({
    Duration timeout = const Duration(seconds: 110),
  }) async {
    if (status.value.stage == PsiphonStage.connected) return true;
    await start();
    final done = Completer<bool>();
    void listener() {
      final stage = status.value.stage;
      if (done.isCompleted) return;
      if (stage == PsiphonStage.connected) done.complete(true);
      if (stage == PsiphonStage.failed || stage == PsiphonStage.idle) {
        done.complete(false);
      }
    }

    status.addListener(listener);
    listener();
    try {
      return await done.future.timeout(timeout, onTimeout: () => false);
    } finally {
      status.removeListener(listener);
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    _session++;
    _networkWatch?.cancel();
    await _kill();
    status.value = const PsiphonStatus();
  }

  /// Dial Psiphon's servers through this SOCKS5 URL (the entry server), or
  /// directly when null. Restarts a running core when it changes.
  Future<void> setUpstream(String? url) async {
    if (_upstream == url) return;
    _upstream = url;
    if (isRunning) {
      await stop();
      await start();
    }
  }

  /// A new egress country (null = automatic). Remembered, and applied right
  /// away when the core is running.
  Future<void> setRegion(String? region) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_regionKey);
    if (current == region) return;
    if (region == null) {
      await prefs.remove(_regionKey);
    } else {
      await prefs.setString(_regionKey, region);
    }
    if (isRunning) {
      await stop();
      await start();
    }
  }

  /// Called when the user picks a proxy in the app's lists.
  static Future<void> noteSelection(String proxyName) async {
    final parsed = PsiphonNodes.parse(proxyName);
    if (!parsed.isPsiphon) return;
    await instance.setRegion(parsed.region);
  }

  Future<String> _dataDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}easy_psiphon');
    await Directory(
      '${dir.path}${Platform.pathSeparator}osl',
    ).create(recursive: true);
    return dir.path.replaceAll('\\', '/');
  }

  /// First run on a network that cannot reach Psiphon's server-list drops
  /// still has servers to dial: copy the list that shipped beside the core
  /// (`seed/`), never over files the core has already written.
  Future<void> _seed(File exe, String dataDir) async {
    final seed = Directory('${exe.parent.path}${Platform.pathSeparator}seed');
    if (!seed.existsSync()) return;
    await for (final entity in seed.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(seed.path.length + 1);
      final target = File('$dataDir/${relative.replaceAll('\\', '/')}');
      if (target.existsSync()) continue;
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    }
  }

  Future<Map<String, dynamic>> _networks(SharedPreferences prefs) async {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(prefs.getString(_networksKey) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  /// Which method to try first on this network: what worked here last time,
  /// else what worked anywhere last, else the natural order.
  Future<List<PsiphonRung>> _orderFor(
    SharedPreferences prefs,
    String fingerprint,
  ) async {
    final networks = await _networks(prefs);
    final here = (networks[fingerprint] as Map?)?['winner'] as String?;
    return PsiphonLadder.orderFor(
      winner: here ?? prefs.getString(_winnerKey),
      chained: _upstream != null,
    );
  }

  Future<void> _remember(
    SharedPreferences prefs,
    String fingerprint,
    String rung,
  ) async {
    final networks = await _networks(prefs);
    networks[fingerprint] = {
      'winner': rung,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    await prefs.setString(_networksKey, jsonEncode(networks));
    await prefs.setString(_winnerKey, rung);
  }

  void _watchNetwork(int session) {
    _networkWatch?.cancel();
    _networkWatch = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (session != _session) return;
      final now = await NetworkFingerprint.current();
      if (_fingerprint != null && now != _fingerprint) {
        _networkChanged = true;
        await _kill();
      }
    });
  }

  Future<void> _loop(int session, File exe, String dataDir) async {
    final prefs = await SharedPreferences.getInstance();
    _watchNetwork(session);
    var pass = 0;
    while (session == _session && !_stopRequested) {
      _fingerprint = await NetworkFingerprint.current();
      _networkChanged = false;
      final order = await _orderFor(prefs, _fingerprint!);
      for (final rung in order) {
        if (session != _session || _networkChanged) break;
        final connected = await _runRung(
          session,
          exe,
          dataDir,
          rung,
          prefs,
          prefs.getString(_regionKey),
          pass,
        );
        if (session != _session) return;
        if (connected || _networkChanged) {
          // The tunnel ended or the network changed: start over, which
          // re-reads what is remembered for the (possibly new) network.
          pass = 0;
          status.value = const PsiphonStatus(stage: PsiphonStage.starting);
          break;
        }
      }
      if (session == _session && !_networkChanged) pass++;
    }
  }

  /// Returns true once a tunnel was up and has since ended.
  Future<bool> _runRung(
    int session,
    File exe,
    String dataDir,
    PsiphonRung rung,
    SharedPreferences prefs,
    String? region,
    int pass,
  ) async {
    await _kill();
    final config = PsiphonLadder.buildConfig(
      rung: rung,
      dataDir: dataDir,
      socksPort: socksPort,
      egressRegion: region,
      upstreamProxyUrl: _upstream,
    );
    final configFile = File('$dataDir/psiphon-${rung.name}.config');
    await configFile.writeAsString(jsonEncode(config));

    status.value = PsiphonStatus(
      stage: PsiphonStage.dialling,
      rung: rung.name,
      pass: pass,
      hint: _lastHint,
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
    final failures = <String, int>{};

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
          _record(rung.name, '$type', notice['data']);
          if (type == 'Info') {
            final message = '${data['message']}'.toLowerCase();
            if (message.contains('failed to connect')) {
              final kind =
                  message.contains('actively refused') ||
                      message.contains('connection refused')
                  ? 'refused'
                  : message.contains('deadline') || message.contains('timeout')
                  ? 'timeout'
                  : 'blocked';
              failures.update(kind, (n) => n + 1, ifAbsent: () => 1);
            }
          }
          if (type == 'ConnectingServer') {
            protocol = '${data['protocol']}';
          }
          if (type == 'Tunnels' && (data['count'] ?? 0) >= 1 && !connected) {
            connected = true;
            status.value = PsiphonStatus(
              stage: PsiphonStage.connected,
              rung: rung.name,
              protocol: protocol,
            );
            // Refresh what is remembered for this network every time it
            // connects, so the next run starts on the method that works now.
            final fingerprint = _fingerprint;
            if (fingerprint != null) {
              unawaited(_remember(prefs, fingerprint, rung.name));
            }
          }
          if (type == 'Tunnels' && data['count'] == 0 && connected) {
            if (!done.isCompleted) done.complete(true);
          }
        });
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((_) {
        if (!done.isCompleted) done.complete(connected);
      }),
    );

    final timer = Timer(
      Duration(seconds: PsiphonLadder.budgetFor(rung, pass)),
      () {
        if (!connected && !done.isCompleted) done.complete(false);
      },
    );
    final result = await done.future;
    if (failures.isNotEmpty) {
      final top = failures.entries.reduce((a, b) => a.value >= b.value ? a : b);
      _lastHint = top.key;
    }
    final dir = _dataDirPath;
    if (dir != null) {
      unawaited(File('$dir/psiphon.log').writeAsString(_log.join('\n')));
    }
    timer.cancel();
    await sub.cancel();
    if (!result || session != _session) await _kill();
    return result;
  }

  /// Keeps the notices that explain a failure and writes them beside the
  /// core's data, so "it did not connect" always has something to read.
  void _record(String rung, String type, Object? data) {
    const interesting = {
      'ConnectingServer',
      'Tunnels',
      'Alert',
      'Warning',
      'Error',
      'AvailableEgressRegions',
      'ListeningSocksProxyPort',
    };
    final isFailure =
        type == 'Info' && '${(data as Map?)?['message']}'.contains('failed');
    if (!interesting.contains(type) && !isFailure) return;
    var text = jsonEncode(data);
    if (text.length > 300) text = '${text.substring(0, 300)}…';
    _log.add('${DateTime.now().toIso8601String()} [$rung] $type $text');
    if (_log.length > 200) _log.removeRange(0, _log.length - 200);
    final dir = _dataDirPath;
    if (dir != null && _log.length % 10 == 0) {
      unawaited(File('$dir/psiphon.log').writeAsString(_log.join('\n')));
    }
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
