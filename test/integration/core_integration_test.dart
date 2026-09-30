@TestOn('linux || mac-os || windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easyvpn/core/bridge/core_bridge.dart';
import 'package:easyvpn/core/bridge/ffi_transport.dart';
import 'package:easyvpn/core/bridge/process_transport.dart';
import 'package:easyvpn/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end tests against the REAL Go core (built with `make -C core proc lib-linux`).
/// They are skipped when the binaries are not present.
final _proc = File('bin/easycoreproc-linux-amd64');
final _lib = File('bin/libeasycore.so');

/// Minimal SOCKS5 server (no auth, CONNECT only) used as the upstream "proxy node".
Future<ServerSocket> startSocks5() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((client) async {
    final buf = <int>[];
    var stage = 0;
    Socket? remote;
    late StreamSubscription<List<int>> sub;
    sub = client.listen(
      (data) async {
        if (stage == 2) {
          remote!.add(data);
          return;
        }
        buf.addAll(data);
        if (stage == 0 && buf.length >= 2 && buf.length >= 2 + buf[1]) {
          client.add([5, 0]);
          buf.removeRange(0, 2 + buf[1]);
          stage = 1;
        }
        if (stage == 1 && buf.length >= 4) {
          final atyp = buf[3];
          int need;
          String host;
          int portOff;
          if (atyp == 1) {
            need = 10;
            if (buf.length < need) return;
            host = buf.sublist(4, 8).join('.');
            portOff = 8;
          } else if (atyp == 3) {
            need = 5 + buf[4] + 2;
            if (buf.length < need) return;
            host = utf8.decode(buf.sublist(5, 5 + buf[4]));
            portOff = 5 + buf[4];
          } else {
            client.destroy();
            return;
          }
          final port = (buf[portOff] << 8) | buf[portOff + 1];
          stage = 2;
          sub.pause();
          try {
            remote = await Socket.connect(host, port);
            client.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
            remote!.listen(
              client.add,
              onDone: client.destroy,
              onError: (_) => client.destroy(),
            );
            sub.resume();
            if (buf.length > need) remote!.add(buf.sublist(need));
          } catch (_) {
            client.add([5, 5, 0, 1, 0, 0, 0, 0, 0, 0]);
            client.destroy();
          }
        }
      },
      onDone: () => remote?.destroy(),
      onError: (_) => remote?.destroy(),
    );
  });
  return server;
}

Future<void> runScenario(CoreBridge core) async {
  final info = await core.info();
  expect(info['version'], isNotEmpty);
  expect(
    (info['capabilities'] as List),
    containsAll(['xhttp', 'mlkem', 'tcphttp']),
  );

  // Real-world sample subscription (sanitized): all 17 nodes parse.
  final sample = File('test/fixtures/sub_dart_decoded.txt').readAsStringSync();
  final parsed = await core.parseContent(sample);
  expect(parsed.nodes.length, 17);

  // Export -> re-import keeps the node count (uri list).
  final uri = await core.export('uri', parsed.nodes);
  expect((await core.parseContent(uri)).nodes.length, greaterThanOrEqualTo(15));

  // Backup encrypt/decrypt.
  final blob = await core.backupEncrypt({'hello': 'world'}, 'pw');
  expect((await core.backupDecrypt(blob, 'pw'))['hello'], 'world');
  await expectLater(
    core.backupDecrypt(blob, 'nope'),
    throwsA(isA<CoreException>()),
  );

  // Routing: Iran pack + baseline rule-sets present without network.
  await core.setCountry('ir');
  final statuses = await core.ruleSetStatus();
  expect(statuses.where((s) => s.present).length, greaterThanOrEqualTo(8));

  // Real traffic: app -> core (mixed inbound) -> SOCKS5 upstream -> HTTP echo server.
  final echo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  echo.listen((r) {
    r.response
      ..write('hello-from-echo')
      ..close();
  });
  final socks = await startSocks5();
  final port = 25000 + DateTime.now().millisecond % 500;
  final node = <String, dynamic>{
    'name': 'local-socks',
    'type': 'socks',
    'server': '127.0.0.1',
    'port': socks.port,
  };
  final states = <String>[];
  final sub = core.events.listen((b) {
    for (final e in b) {
      if (e.type == 'state') states.add((e.payload as Map)['state'] as String);
    }
  });
  await core.start(
    node: node,
    settings: AppSettings(
      mode: ConnMode.proxyOnly,
      localPort: port,
      routing: const RoutingSettings(mode: 'global_proxy', bypassLan: false),
    ),
  );
  final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
  final req = await client.getUrl(Uri.parse('http://127.0.0.1:${echo.port}/'));
  final resp = await req.close();
  expect(await resp.transform(utf8.decoder).join(), 'hello-from-echo');
  client.close(force: true);

  await Future<void>.delayed(const Duration(milliseconds: 600));
  final stats = await core.stats();
  expect(stats.totalUp + stats.totalDown, greaterThan(0));

  await core.stop();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  expect(
    states,
    containsAllInOrder([
      'connecting',
      'connected',
      'disconnecting',
      'disconnected',
    ]),
  );
  await sub.cancel();
  await echo.close(force: true);
  await socks.close();
}

void main() {
  final skip = !_proc.existsSync()
      ? 'build the core first: make -C core linux-proc lib-linux'
      : null;

  test(
    'process transport: full scenario against the real core',
    () async {
      final dir = Directory.systemTemp.createTempSync('ezcore');
      final t = await ProcessTransport.open(
        executable: _proc.absolute.path,
        cacheDir: dir.path,
      );
      try {
        await runScenario(CoreBridge(t));
      } finally {
        await t.dispose();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('process transport rejects a wrong token', () async {
    final proc = await Process.start(_proc.absolute.path, [
      '-cache',
      Directory.systemTemp.createTempSync('ezcore').path,
    ]);
    final line = await proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final ready = jsonDecode(line) as Map;
    final s = await Socket.connect(
      InternetAddress.loopbackIPv4,
      ready['port'] as int,
    );
    s.write('{"auth":"wrong"}\n');
    final data = await s
        .fold<List<int>>([], (a, b) => a..addAll(b))
        .timeout(const Duration(seconds: 3));
    expect(data, isEmpty); // closed without serving anything
    await proc.stdin.close();
    await proc.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        proc.kill();
        return -1;
      },
    );
  }, skip: skip);

  test(
    'ffi transport: full scenario against libeasycore.so',
    () async {
      final dir = Directory.systemTemp.createTempSync('ezcore');
      final t = await FfiTransport.open(
        libPath: _lib.absolute.path,
        cacheDir: dir.path,
      );
      try {
        await runScenario(CoreBridge(t));
      } finally {
        await t.dispose();
      }
    },
    skip: (!_lib.existsSync())
        ? 'build the shared library first: make -C core lib-linux'
        : null,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
