import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'core_transport.dart';

typedef _InitC = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _Init = void Function(ffi.Pointer<Utf8>);
typedef _CallC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _Call = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _FreeC = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _Free = void Function(ffi.Pointer<Utf8>);
typedef _EventCbC = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _RegC = ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_EventCbC>>);
typedef _Reg = void Function(ffi.Pointer<ffi.NativeFunction<_EventCbC>>);

class _WorkerInit {
  _WorkerInit(this.libPath, this.cacheDir, this.wantEvents, this.toMain);
  final String libPath;
  final String cacheDir;
  final bool wantEvents;
  final SendPort toMain;
}

/// FFI transport: the Go library is loaded inside two long-lived worker
/// isolates so a slow call (ping, rule sync) never blocks state queries and the
/// UI isolate never executes a native call.
///
///  * `control` isolate – quick calls + receives core events
///  * `heavy` isolate   – long-running calls
class FfiTransport implements CoreTransport {
  FfiTransport._(this._control, this._heavy, this._events, this._ports);

  final _Worker _control;
  final _Worker _heavy;
  final StreamController<List<CoreEvent>> _events;
  final List<ReceivePort> _ports;

  static Future<FfiTransport> open({
    required String libPath,
    required String cacheDir,
  }) async {
    // Fail fast on the calling isolate if the library cannot be loaded.
    try {
      ffi.DynamicLibrary.open(libPath);
    } catch (e) {
      throw CoreUnavailable('cannot load $libPath ($e)');
    }
    final events = StreamController<List<CoreEvent>>.broadcast();
    final ports = <ReceivePort>[];
    final control = await _Worker.spawn(libPath, cacheDir, true, events, ports);
    final heavy = await _Worker.spawn(libPath, cacheDir, false, events, ports);
    return FfiTransport._(control, heavy, events, ports);
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
    final w = heavyMethods.contains(method) ? _heavy : _control;
    return w.call(method, args ?? const {});
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    _control.kill();
    _heavy.kill();
    for (final p in _ports) {
      p.close();
    }
  }
}

class _Worker {
  _Worker(this._isolate, this._send, this._pending);
  final Isolate _isolate;
  final SendPort _send;
  final Map<int, Completer<Map<String, dynamic>>> _pending;
  int _next = 1;

  static Future<_Worker> spawn(
    String lib,
    String cache,
    bool wantEvents,
    StreamController<List<CoreEvent>> events,
    List<ReceivePort> ports,
  ) async {
    final fromWorker = ReceivePort();
    ports.add(fromWorker);
    final pending = <int, Completer<Map<String, dynamic>>>{};
    final ready = Completer<SendPort>();
    fromWorker.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is List && msg.isNotEmpty) {
        switch (msg[0]) {
          case 'res':
            final c = pending.remove(msg[1] as int);
            final res = msg[2] as Map;
            if (res['error'] != null && (res['error'] as String).isNotEmpty) {
              c?.completeError(CoreException(res['error'] as String));
            } else {
              c?.complete(
                ((res['result'] as Map?) ?? const {}).cast<String, dynamic>(),
              );
            }
          case 'evt':
            if (!events.isClosed) {
              final batch = (msg[1] as List)
                  .map(
                    (e) =>
                        CoreEvent.fromJson((e as Map).cast<String, dynamic>()),
                  )
                  .toList(growable: false);
              events.add(batch);
            }
          case 'fatal':
            if (!ready.isCompleted)
              ready.completeError(CoreUnavailable(msg[1] as String));
        }
      }
    });
    final iso = await Isolate.spawn(
      _workerMain,
      _WorkerInit(lib, cache, wantEvents, fromWorker.sendPort),
    );
    final send = await ready.future;
    return _Worker(iso, send, pending);
  }

  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> args) {
    final id = _next++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _send.send([
      id,
      jsonEncode({'id': '$id', 'method': method, 'args': args}),
    ]);
    return c.future;
  }

  void kill() => _isolate.kill(priority: Isolate.immediate);
}

void _workerMain(_WorkerInit init) {
  late final ffi.DynamicLibrary lib;
  try {
    lib = ffi.DynamicLibrary.open(init.libPath);
  } catch (e) {
    init.toMain.send(['fatal', '$e']);
    return;
  }
  final initCore = lib.lookupFunction<_InitC, _Init>('InitCore');
  final coreCall = lib.lookupFunction<_CallC, _Call>('CoreCall');
  final freeStr = lib.lookupFunction<_FreeC, _Free>('FreeString');

  final dir = init.cacheDir.toNativeUtf8();
  initCore(dir);
  malloc.free(dir);

  if (init.wantEvents) {
    final register = lib.lookupFunction<_RegC, _Reg>('RegisterEventCallback');
    final cb = ffi.NativeCallable<_EventCbC>.listener((ffi.Pointer<Utf8> p) {
      final s = p.toDartString();
      freeStr(p); // ownership was transferred by the Go side
      try {
        final batch = jsonDecode(s) as List;
        init.toMain.send(['evt', batch]);
      } catch (_) {}
    });
    register(cb.nativeFunction);
  }

  final inbox = ReceivePort();
  init.toMain.send(inbox.sendPort);
  inbox.listen((msg) {
    final list = msg as List;
    final id = list[0] as int;
    final req = (list[1] as String).toNativeUtf8();
    final resPtr = coreCall(req);
    malloc.free(req);
    final raw = resPtr.toDartString();
    freeStr(resPtr);
    Map<String, dynamic> decoded;
    try {
      decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (e) {
      decoded = {'error': 'bad core response: $e'};
    }
    init.toMain.send(['res', id, decoded]);
  });
}
