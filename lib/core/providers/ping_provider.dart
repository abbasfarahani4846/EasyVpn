import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/core_bridge.dart';
import '../util/platform_service.dart';
import 'env.dart';
import 'node_list_provider.dart';
import 'settings_provider.dart';

class PingState {
  const PingState({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.mode = 'tcp',
    this.error,
  });
  final bool running;
  final int done;
  final int total;
  final String mode;
  final String? error;
  double get progress => total == 0 ? 0 : done / total;
}

/// Batch latency testing. Results stream from the core as `delay` events; the
/// UI applies them in place and they are persisted in throttled batches so
/// testing 5,000 nodes never rebuilds the list per node.
class PingNotifier extends Notifier<PingState> {
  StreamSubscription<List<CoreEvent>>? _sub;
  final _pending = <String, int>{};
  Timer? _flushTimer;
  int _done = 0;

  @override
  PingState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _flushTimer?.cancel();
    });
    _sub = ref.read(envProvider).core.events.listen((batch) {
      for (final e in batch) {
        if (e.type != 'delay' || !state.running) continue;
        for (final r in (e.payload as List).cast<Map>()) {
          final id = r['node_id'] as String;
          _pending[id] = (r['latency_ms'] as int?) ?? -1;
          _done++;
        }
      }
      if (_pending.isNotEmpty) _scheduleFlush();
    });
    return const PingState();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 300), _flush);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    if (_pending.isEmpty) {
      return;
    }
    final snap = Map<String, int>.from(_pending);
    _pending.clear();
    ref.read(nodeListProvider.notifier).applyLatency(snap);
    state = PingState(
      running: state.running,
      done: _done.clamp(0, state.total),
      total: state.total,
      mode: state.mode,
    );
    await ref.read(envProvider).repo.setLatencies(snap);
  }

  /// Pings [ids] (all when null: every node of [profileId]).
  Future<void> run({List<String>? ids, String? profileId, String? mode}) async {
    if (state.running) return;
    final env = ref.read(envProvider);
    final m = mode ?? 'tcp';
    try {
      final all = ids ?? await env.repo.allIds(profileId: profileId);
      if (all.isEmpty) return;
      _done = 0;
      _pending.clear();
      state = PingState(running: true, total: all.length, mode: m);
      if (m == 'tcp') {
        // TCP mode only needs host/port — no secrets are decrypted or sent.
        final nodes = <Map<String, dynamic>>[];
        for (var i = 0; i < all.length; i += 500) {
          final part = all.sublist(
            i,
            i + 500 > all.length ? all.length : i + 500,
          );
          for (final id in part) {
            final r = await env.repo.nodeRow(id);
            if (r != null)
              nodes.add({
                'id': r.id,
                'type': r.protocol,
                'server': r.server,
                'port': r.port,
              });
          }
        }
        final results = await env.core.ping(nodes, mode: 'tcp');
        _applyFinal(results);
      } else {
        final url = ref.read(settingsProvider).testUrl;
        final dns = await PlatformService.systemDns();
        for (var i = 0; i < all.length && state.running; i += 200) {
          final part = all.sublist(
            i,
            i + 200 > all.length ? all.length : i + 200,
          );
          final raws = await env.repo.rawNodes(part);
          final results = await env.core.ping(
            raws,
            mode: 'url',
            url: url,
            systemDns: dns,
          );
          _applyFinal(results);
        }
      }
      await _flush();
      state = PingState(total: state.total, done: state.total, mode: m);
    } on CoreException catch (e) {
      state = PingState(error: e.message, mode: m);
    } catch (e) {
      state = PingState(error: '$e', mode: m);
    }
  }

  void _applyFinal(List<Map<String, dynamic>> results) {
    for (final r in results) {
      _pending[r['node_id'] as String] = (r['latency_ms'] as int?) ?? -1;
    }
    _done = state.total;
  }

  Future<void> cancel() async {
    if (!state.running) return;
    try {
      await ref.read(envProvider).core.cancelPing();
    } catch (_) {}
    await _flush();
    state = PingState(total: state.total, done: state.done, mode: state.mode);
  }
}

final pingProvider = NotifierProvider<PingNotifier, PingState>(
  PingNotifier.new,
);
