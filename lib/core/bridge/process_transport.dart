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
  ProcessTransport._(this._proc, this._socket);

  final Process _proc;
  final Socket _socket;
  final _events = StreamController<List<CoreEvent>>.broadcast();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  int _next = 1;

  static Future<ProcessTransport> open({
    required String executable,
    required String cacheDir,
  }) async {
    if (!File(executable).existsSync()) {
      throw CoreUnavailable('core binary not found: $executable');
    }
    final proc = await Process.start(executable, ['-cache', cacheDir]);
    proc.stderr.drain<void>(); // sing-box logs come through the event stream
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
    final t = ProcessTransport._(proc, socket);
    t._listen();
    return t;
  }

  void _listen() {
    _socket
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
          onDone: () {
            for (final c in _pending.values) {
              c.completeError(CoreUnavailable('core process exited'));
            }
            _pending.clear();
            if (!_events.isClosed) {
              _events.add([
                const CoreEvent('crash', {'reason': 'core process exited'}),
              ]);
            }
          },
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
