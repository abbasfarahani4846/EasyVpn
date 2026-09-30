import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/core_bridge.dart';
import '../models/models.dart';
import '../util/platform_service.dart';
import 'env.dart';
import 'settings_provider.dart';

/// Result of the last failed connect, used by the UI to offer fixes.
class ConnectFailure {
  const ConnectFailure(this.message, {this.capability});
  final String message;
  final String? capability;
}

/// Authoritative connection state mirrored from core `state` events.
/// The UI is optimistic (shows `connecting` immediately) but the core decides.
class CoreController extends Notifier<CoreState> {
  StreamSubscription<List<CoreEvent>>? _sub;
  int _revision = 0;
  ConnectFailure? lastFailure;

  @override
  CoreState build() {
    final env = ref.read(envProvider);
    ref.onDispose(() => _sub?.cancel());
    if (!env.core.isAvailable) {
      return CoreState(
        status: CoreStatus.unavailable,
        detail: env.core.unavailableReason,
      );
    }
    _sub = env.core.events.listen(_onEvents);
    if (PlatformService.isAndroid) {
      PlatformService.setHandlers(
        onRevoked: () {
          if (state.isConnected || state.status == CoreStatus.connecting)
            disconnect();
        },
        onToggle: toggle,
        onFastest: connectFastest,
      );
      listenSelf((prev, next) {
        if (prev?.status == next.status) return;
        _pushWidget(next.isConnected);
      });
    }
    return const CoreState();
  }

  void _onEvents(List<CoreEvent> batch) {
    for (final e in batch) {
      if (e.type == 'state') {
        final m = (e.payload as Map).cast<String, dynamic>();
        state = CoreState(
          status: parseStatus(m['state'] as String?),
          mode: ConnMode.parse(m['mode'] as String?),
          detail: (m['detail'] as String?) ?? '',
        );
      } else if (e.type == 'crash') {
        state = CoreState(status: CoreStatus.error, detail: 'core crashed');
      } else if (e.type == 'restarted') {
        // A fresh core is running (OS proxy restored). Reconnect is one tap
        // away; pull the previous run's crash report into the logs.
        state = const CoreState(
          status: CoreStatus.error,
          detail: 'err.core_restarted',
        );
        _pullCrashReport();
      }
    }
  }

  Future<void> _pullCrashReport() async {
    try {
      final r = await ref.read(envProvider).core.raw('LastCrash');
      final text = (r['text'] as String?) ?? '';
      if (text.isNotEmpty) {
        ref
            .read(logProvider.notifier)
            .add('error', 'core crash report:\n$text');
      }
    } catch (_) {}
  }

  /// Connects using the active node from settings (or [nodeId]).
  Future<void> connect({String? nodeId}) async {
    if (state.status == CoreStatus.unavailable ||
        state.isBusy ||
        state.isConnected)
      return;
    final env = ref.read(envProvider);
    final settings = ref.read(settingsProvider);
    final id = nodeId ?? settings.activeNodeId;
    if (id == null) {
      lastFailure = const ConnectFailure('no_node');
      state = const CoreState(status: CoreStatus.error, detail: 'no_node');
      return;
    }
    final rev = ++_revision;
    state = state.copyWith(
      status: CoreStatus.connecting,
      mode: settings.mode,
      detail: '',
    );
    try {
      var node = await env.repo.rawNode(id);
      if (node == null) throw CoreException('node not found');
      node = await _ensureOpenVpnCredentials(id, node);
      // Chain: hops before the active node; an exit node (e.g. WARP) turns
      // the active node into the last hop.
      final chain = <Map<String, dynamic>>[];
      for (final hid in settings.chainNodeIds) {
        if (hid == id) continue;
        final h = await env.repo.rawNode(hid);
        if (h != null) chain.add(h);
      }
      if (settings.exitNodeId.isNotEmpty && settings.exitNodeId != id) {
        final exit = await env.repo.rawNode(settings.exitNodeId);
        if (exit != null) {
          chain.add(node);
          node = exit;
        }
      }
      final candIds = await env.repo.topNodeIds(
        profileId: settings.activeProfileId,
        exclude: id,
      );
      // Candidates (hot switch / auto group) only make sense without a chain.
      final cands = chain.isEmpty
          ? await env.repo.rawNodes(candIds)
          : const <Map<String, dynamic>>[];
      await env.core.setRouting(settings.routing);
      if (PlatformService.isDesktop &&
          settings.mode.usesTun &&
          !await PlatformService.isElevated()) {
        throw CoreException('needs_admin');
      }
      Map<String, dynamic>? tun;
      if (PlatformService.isAndroid && settings.mode.usesTun) {
        // The Android host creates the TUN device and hands its fd to the core.
        if (!await PlatformService.prepareVpn())
          throw CoreException('vpn_permission_denied');
        // Mobile links carry ~1500-byte packets; larger values only hurt.
        final mtu = settings.tunMtu > 1500 || settings.tunMtu < 576
            ? 1500
            : settings.tunMtu;
        Future<int?> establish() => PlatformService.establishVpn(
          mtu: mtu,
          ipv6: settings.tunIpv6,
          include: settings.perAppMode == 'include'
              ? settings.perAppPackages
              : const [],
          exclude: settings.perAppMode == 'exclude'
              ? settings.perAppPackages
              : const [],
        );
        var fd = await establish();
        if (fd == null) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          fd = await establish();
        }
        if (fd == null) throw CoreException('vpn_establish_failed');
        tun = {'fd': fd, 'mtu': mtu, 'ipv6': settings.tunIpv6};
      }
      final useAuth =
          settings.localAuth &&
          settings.mode == ConnMode.proxyOnly &&
          env.localPass.isNotEmpty;
      await env.core.start(
        node: node,
        candidates: cands,
        settings: settings,
        authUser: useAuth ? 'easyvpn' : null,
        authPass: useAuth ? env.localPass : null,
        tun: tun,
        chain: chain,
      );
      lastFailure = null;
    } on CoreException catch (e) {
      if (rev != _revision) return;
      lastFailure = ConnectFailure(e.message, capability: e.capability);
      state = CoreState(
        status: CoreStatus.error,
        mode: settings.mode,
        detail: e.message,
      );
    } catch (e) {
      if (rev != _revision) return;
      lastFailure = ConnectFailure('$e');
      state = CoreState(
        status: CoreStatus.error,
        mode: settings.mode,
        detail: '$e',
      );
    }
  }

  Future<void> disconnect() async {
    if (state.status == CoreStatus.unavailable) return;
    _revision++;
    state = state.copyWith(status: CoreStatus.disconnecting);
    try {
      await ref.read(envProvider).core.stop();
    } catch (_) {
      state = state.copyWith(status: CoreStatus.disconnected);
    }
    if (PlatformService.isAndroid) await PlatformService.stopVpn();
  }

  Future<void> toggle() =>
      state.isConnected || state.status == CoreStatus.connecting
      ? disconnect()
      : connect();

  /// OpenVPN profiles with `auth-user-pass` need a username/password that the
  /// .ovpn file does not contain (e.g. Windscribe's Config Generator
  /// credentials). Ask once and store them with the node (encrypted at rest).
  Future<Map<String, dynamic>> _ensureOpenVpnCredentials(
    String id,
    Map<String, dynamic> node,
  ) async {
    final o = (node['openvpn'] as Map?)?.cast<String, dynamic>();
    if (node['type'] != 'openvpn' ||
        o == null ||
        o['auth_user_pass'] != true ||
        ((o['username'] as String?) ?? '').isNotEmpty) {
      return node;
    }
    final ask = openVpnCredentialPrompt;
    final creds = ask == null
        ? null
        : await ask((node['name'] as String?) ?? '');
    if (creds == null) throw CoreException('openvpn_needs_credentials');
    final updated = {
      ...node,
      'openvpn': {...o, 'username': creds.user, 'password': creds.pass},
    };
    final env = ref.read(envProvider);
    final row = await env.repo.nodeRow(id);
    if (row != null) {
      await env.repo.importNodes(row.profileId, [updated], replace: false);
    }
    return updated;
  }

  Future<void> _pushWidget(bool connected) async {
    final env = ref.read(envProvider);
    final id = ref.read(settingsProvider).activeNodeId;
    final row = id == null ? null : await env.repo.nodeRow(id);
    await PlatformService.setWidgetInfo(
      connected: connected,
      node: row?.name ?? '',
    );
  }

  /// Connects to the lowest-latency node of the active profile (shortcut,
  /// widget, tray "Fastest").
  Future<void> connectFastest() async {
    final env = ref.read(envProvider);
    final s = ref.read(settingsProvider);
    final ids = await env.repo.topNodeIds(
      profileId: s.activeProfileId,
      limit: 1,
    );
    if (ids.isEmpty) return connect();
    if (state.isConnected) return selectNode(ids.first);
    ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(activeNodeId: ids.first));
    await connect(nodeId: ids.first);
  }

  /// Selects a node; hot-switches while connected (no teardown when possible).
  Future<void> selectNode(String id) async {
    final env = ref.read(envProvider);
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(activeNodeId: id));
    if (!state.isConnected) return;
    final raw = await env.repo.rawNode(id);
    if (raw == null) return;
    try {
      await env.core.switchNode(raw);
    } on CoreException catch (e) {
      lastFailure = ConnectFailure(e.message, capability: e.capability);
      state = state.copyWith(detail: e.message);
    }
  }

  /// Changes the connection mode; restarts the session if it is running.
  Future<void> setMode(ConnMode m) async {
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(mode: m));
    if (state.isConnected) {
      await disconnect();
      await connect();
    }
  }
}

final coreControllerProvider = NotifierProvider<CoreController, CoreState>(
  CoreController.new,
);

/// Latest traffic snapshot + 60-sample history for the chart (4 Hz events are
/// down-sampled to 1 Hz for history).
class TrafficState {
  const TrafficState(this.current, this.history);
  final TrafficStats current;
  final List<TrafficStats> history;
}

class TrafficNotifier extends Notifier<TrafficState> {
  StreamSubscription<List<CoreEvent>>? _sub;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  TrafficState build() {
    final env = ref.read(envProvider);
    ref.onDispose(() => _sub?.cancel());
    _sub = env.core.events.listen((batch) {
      for (final e in batch) {
        if (e.type != 'stats') continue;
        final cur = TrafficStats.fromJson(
          (e.payload as Map).cast<String, dynamic>(),
        );
        final now = DateTime.now();
        var hist = state.history;
        if (now.difference(_lastSample) >= const Duration(seconds: 1)) {
          _lastSample = now;
          hist = [...hist, cur];
          if (hist.length > 60) hist = hist.sublist(hist.length - 60);
        }
        state = TrafficState(cur, hist);
      }
    });
    // Reset when the session ends.
    ref.listen(coreControllerProvider, (prev, next) {
      if (next.status == CoreStatus.disconnected &&
          prev?.status != CoreStatus.disconnected) {
        state = const TrafficState(TrafficStats(), []);
      }
    });
    return const TrafficState(TrafficStats(), []);
  }
}

final trafficProvider = NotifierProvider<TrafficNotifier, TrafficState>(
  TrafficNotifier.new,
);

/// Ring buffer of the last [max] log lines.
class LogNotifier extends Notifier<List<LogLine>> {
  static const max = 2000;
  final _ring = Queue<LogLine>();
  StreamSubscription<List<CoreEvent>>? _sub;
  Timer? _flush;
  bool _dirty = false;

  @override
  List<LogLine> build() {
    final env = ref.read(envProvider);
    ref.onDispose(() {
      _sub?.cancel();
      _flush?.cancel();
    });
    _sub = env.core.events.listen((batch) {
      for (final e in batch) {
        if (e.type != 'log') continue;
        final m = (e.payload as Map).cast<String, dynamic>();
        _ring.add(
          LogLine(
            DateTime.now(),
            (m['level'] as String?) ?? 'info',
            (m['msg'] as String?) ?? '',
          ),
        );
        if (_ring.length > max) _ring.removeFirst();
        _dirty = true;
      }
    });
    // Publish at most 4x per second so a log storm never rebuilds the UI per line.
    // (see also [add] for app-generated lines)
    _flush = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_dirty) {
        _dirty = false;
        state = List.unmodifiable(_ring);
      }
    });
    return const [];
  }

  void clear() {
    _ring.clear();
    state = const [];
  }
}

extension LogNotifierAdd on LogNotifier {
  /// Appends an app-side line (e.g. a crash report fetched from the core).
  void add(String level, String msg) {
    _ring.add(LogLine(DateTime.now(), level, msg));
    if (_ring.length > LogNotifier.max) _ring.removeFirst();
    _dirty = true;
  }
}

final logProvider = NotifierProvider<LogNotifier, List<LogLine>>(
  LogNotifier.new,
);

/// Asks the user for OpenVPN credentials; installed by the app shell (it owns
/// the navigator). Returns null when cancelled.
Future<({String user, String pass})?> Function(String nodeName)?
openVpnCredentialPrompt;

/// Real exit IP / country through the tunnel (refreshed on connect).
class ExitInfo {
  const ExitInfo({
    this.ip = '',
    this.country = '',
    this.countryCode = '',
    this.city = '',
    this.isp = '',
    this.source = '',
  });
  final String ip;
  final String country;
  final String countryCode;
  final String city;
  final String isp;
  final String source;
}

/// Looks up the address the internet sees, THROUGH the tunnel. Uses the user's
/// custom URL when set (Settings ▸ Connection), else the built-in providers.
/// Retries a few times because a fresh tunnel needs a moment to carry traffic.
class ExitInfoNotifier extends AsyncNotifier<ExitInfo?> {
  @override
  Future<ExitInfo?> build() async {
    final st = ref.watch(coreControllerProvider.select((s) => s.status));
    final url = ref.watch(settingsProvider.select((s) => s.ipCheckUrl));
    if (st != CoreStatus.connected) return null;
    return _lookup(url);
  }

  Future<ExitInfo?> _lookup(String url) async {
    final core = ref.read(envProvider).core;
    Object? lastError;
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration(milliseconds: i == 0 ? 500 : 1500));
      try {
        final j = await core.exitInfo(url: url);
        if ((j['ip'] as String?)?.isNotEmpty ?? false) {
          return ExitInfo(
            ip: j['ip'] as String,
            country: (j['country'] as String?) ?? '',
            countryCode: (j['countryCode'] as String?) ?? '',
            city: (j['city'] as String?) ?? '',
            isp: (j['isp'] as String?) ?? '',
            source: (j['source'] as String?) ?? '',
          );
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? 'no answer';
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _lookup(ref.read(settingsProvider).ipCheckUrl),
    );
  }
}

final exitInfoProvider = AsyncNotifierProvider<ExitInfoNotifier, ExitInfo?>(
  ExitInfoNotifier.new,
);
