import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'core_transport.dart';

/// Desktop transport: spawns `easycoreproc`, reads its `{"ready","port","token"}`
/// line, then talks newline-delimited JSON over an authenticated loopback socket.
/// Closing this transport closes the child's stdin, which makes it restore the
/// OS proxy and exit.
class ProcessTransport implements CoreTransport {
  ProcessTransport._(this._exe, this._cacheDir);

  final String _exe;
  final String _cacheDir;
  late Process _proc;
  late Socket _socket;
  final _events = StreamController<List<CoreEvent>>.broadcast();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  int _next = 1;
  bool _disposed = false;

  /// PID of the current core process (tests / diagnostics).
  int get pid => _proc.pid;
  int _restarts = 0;

  /// Last lines the core wrote to stderr (Go panics land here); attached to
  /// the "crash" event so "Copy diagnostics" shows the real cause.
  final _stderrTail = <String>[];

  static Future<ProcessTransport> open({
    required String executable,
    required String cacheDir,
  }) async {
    if (!File(executable).existsSync()) {
      throw CoreUnavailable('core binary not found: $executable');
    }
    final t = ProcessTransport._(executable, cacheDir);
    await t._spawn();
    return t;
  }

  Future<void> _spawn() async {
    final proc = await Process.start(_exe, ['-cache', _cacheDir]);
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((
      l,
    ) {
      _stderrTail.add(l);
      if (_stderrTail.length > 120) _stderrTail.removeAt(0);
    }, onError: (_) {});
    final readyC = Completer<Map<String, dynamic>>();
    // A single listener keeps draining stdout for the process lifetime.
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (readyC.isCompleted) return;
            try {
              readyC.complete(
                (jsonDecode(line) as Map).cast<String, dynamic>(),
              );
            } catch (e) {
              readyC.completeError(CoreUnavailable('bad ready line: $line'));
            }
          },
          onDone: () {
            if (!readyC.isCompleted)
              readyC.completeError(
                CoreUnavailable('core exited before becoming ready'),
              );
          },
        );
    final Map<String, dynamic> ready;
    try {
      ready = await readyC.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      proc.kill();
      throw CoreUnavailable('core did not become ready in time');
    }

    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      ready['port'] as int,
    );
    socket.write('${jsonEncode({'auth': ready['token']})}\n');
    _proc = proc;
    _socket = socket;
    _listen(socket);
  }

  /// The core died: fail pending calls, report the crash with its stderr
  /// tail, then start a fresh core so the user can reconnect without
  /// restarting the app (the new core also restores the OS proxy).
  Future<void> _onExit() async {
    for (final c in _pending.values) {
      c.completeError(CoreUnavailable('core process exited'));
    }
    _pending.clear();
    if (_disposed || _events.isClosed) return;
    var code = -1;
    try {
      code = await _proc.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
    final tail = _stderrTail.join('\n');
    _events.add([
      CoreEvent('log', {
        'level': 'error',
        'msg': 'core process exited (code $code)\n$tail',
      }),
      CoreEvent('crash', {
        'reason': 'core process exited (code $code)',
        'stderr': tail,
      }),
    ]);
    _stderrTail.clear();
    if (_restarts >= 5) return; // crash loop: stop respawning
    _restarts++;
    for (var attempt = 0; attempt < 3 && !_disposed; attempt++) {
      try {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        await _spawn();
        if (!_events.isClosed) {
          _events.add([const CoreEvent('restarted', {})]);
        }
        return;
      } catch (_) {}
    }
  }

  void _listen(Socket socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) async {
            final j = line.length > 64 * 1024
                ? await Isolate.run(() => jsonDecode(line) as Map)
                : jsonDecode(line) as Map;
            if (j.containsKey('event')) {
              final batch = (j['event'] as List)
                  .map(
                    (e) =>
                        CoreEvent.fromJson((e as Map).cast<String, dynamic>()),
                  )
                  .toList(growable: false);
              if (!_events.isClosed) _events.add(batch);
              return;
            }
            final c = _pending.remove(j['id'] as String?);
            if (c == null) return;
            final err = j['error'] as String?;
            if (err != null && err.isNotEmpty) {
              c.completeError(CoreException(err));
            } else {
              c.complete(
                ((j['result'] as Map?) ?? const {}).cast<String, dynamic>(),
              );
            }
          },
          onError: (_) {},
          onDone: _onExit,
        );
  }

  @override
  bool get isAvailable => true;

  @override
  Stream<List<CoreEvent>> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) {
    final id = '${_next++}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _socket.write(
      '${jsonEncode({'id': id, 'method': method, 'args': args ?? const {}})}\n',
    );
    return c.future;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _events.close();
    try {
      await _proc.stdin.close(); // triggers restore + exit inside the core
    } catch (_) {}
    await _socket.close();
    await _proc.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _proc.kill();
        return -1;
      },
    );
  }
}
