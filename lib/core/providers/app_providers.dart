import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/easy_core_ffi.dart';
import '../models/models.dart';
import '../storage/storage_service.dart';

// Storage Provider
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService must be overridden in ProviderScope');
});

// Settings Notifier
class SettingsNotifier extends StateNotifier<AppSettingsModel> {
  final StorageService _storage;

  SettingsNotifier(this._storage) : super(_storage.getSettings());

  Future<void> updateSettings(AppSettingsModel newSettings) async {
    state = newSettings;
    await _storage.saveSettings(newSettings);
    EasyCoreFFI.instance.setCountry(newSettings.country);
    EasyCoreFFI.instance.setRoutingMode(newSettings.routingMode);
  }

  Future<void> setCountry(String code) async {
    await updateSettings(state.copyWith(country: code));
  }

  Future<void> setRoutingMode(String mode) async {
    await updateSettings(state.copyWith(routingMode: mode));
  }

  Future<void> toggleDarkMode() async {
    await updateSettings(state.copyWith(isDarkMode: !state.isDarkMode));
  }

  Future<void> setAccentColor(int colorValue) async {
    await updateSettings(state.copyWith(accentColorValue: colorValue));
  }

  Future<void> toggleTun() async {
    await updateSettings(state.copyWith(tunEnabled: !state.tunEnabled));
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettingsModel>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return SettingsNotifier(storage);
});

// Profiles Notifier
class ProfilesNotifier extends StateNotifier<List<ProfileModel>> {
  final StorageService _storage;

  ProfilesNotifier(this._storage) : super(_storage.getProfiles());

  Future<void> addProfile(ProfileModel profile) async {
    await _storage.addProfile(profile);
    state = _storage.getProfiles();
  }

  Future<void> deleteProfile(String profileId) async {
    await _storage.deleteProfile(profileId);
    state = _storage.getProfiles();
  }
}

final profilesProvider = StateNotifierProvider<ProfilesNotifier, List<ProfileModel>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ProfilesNotifier(storage);
});

// Nodes Notifier
class NodesNotifier extends StateNotifier<List<ProxyNodeModel>> {
  final StorageService _storage;

  NodesNotifier(this._storage) : super(_storage.getNodes());

  Future<void> addNodes(List<ProxyNodeModel> newNodes) async {
    await _storage.addNodes(newNodes);
    state = _storage.getNodes();
  }

  Future<void> updateLatency(String nodeId, int latencyMs) async {
    await _storage.updateNodeLatency(nodeId, latencyMs);
    state = _storage.getNodes();
  }

  Future<void> toggleFavorite(String nodeId) async {
    await _storage.toggleNodeFavorite(nodeId);
    state = _storage.getNodes();
  }

  Future<void> deleteNode(String nodeId) async {
    await _storage.deleteNode(nodeId);
    state = _storage.getNodes();
  }

  Future<void> clearAll() async {
    await _storage.clearAllNodes();
    state = [];
  }
}

final nodesProvider = StateNotifierProvider<NodesNotifier, List<ProxyNodeModel>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return NodesNotifier(storage);
});

// Active Node Provider
final activeNodeIdProvider = StateProvider<String?>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.getActiveNodeId();
});

final activeNodeProvider = Provider<ProxyNodeModel?>((ref) {
  final activeId = ref.watch(activeNodeIdProvider);
  final nodes = ref.watch(nodesProvider);
  if (activeId == null) {
    return nodes.isNotEmpty ? nodes.first : null;
  }
  return nodes.firstWhere((n) => n.id == activeId, orElse: () => nodes.isNotEmpty ? nodes.first : null as dynamic);
});

// VPN State & Duration
enum VPNStatus { disconnected, connecting, connected, error }

class ConnectionTimerNotifier extends StateNotifier<Duration> {
  Timer? _timer;

  ConnectionTimerNotifier() : super(Duration.zero);

  void start() {
    _timer?.cancel();
    state = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state + const Duration(seconds: 1);
    });
  }

  void stop() {
    _timer?.cancel();
    state = Duration.zero;
  }
}

final connectionDurationProvider = StateNotifierProvider<ConnectionTimerNotifier, Duration>((ref) {
  return ConnectionTimerNotifier();
});

class VPNController extends StateNotifier<VPNStatus> {
  final Ref _ref;
  Timer? _statsTimer;

  VPNController(this._ref) : super(VPNStatus.disconnected);

  Future<void> connect() async {
    final activeNode = _ref.read(activeNodeProvider);
    if (activeNode == null) return;

    state = VPNStatus.connecting;
    final settings = _ref.read(settingsProvider);

    final res = EasyCoreFFI.instance.startProxy(activeNode.toMap(), settings.tunEnabled);
    if (res == 0) {
      state = VPNStatus.connected;
      _ref.read(connectionDurationProvider.notifier).start();
      _startStatsTimer();
      _ref.read(ipInfoProvider.notifier).updateForProxy(activeNode);
    } else {
      state = VPNStatus.error;
    }
  }

  Future<void> disconnect() async {
    _statsTimer?.cancel();
    _ref.read(connectionDurationProvider.notifier).stop();
    EasyCoreFFI.instance.stopProxy();
    state = VPNStatus.disconnected;
    _ref.read(trafficStatsProvider.notifier).reset();
    _ref.read(ipInfoProvider.notifier).reset();
  }

  Future<void> toggle() async {
    if (state == VPNStatus.connected) {
      await disconnect();
    } else if (state == VPNStatus.disconnected || state == VPNStatus.error) {
      await connect();
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final snapshot = EasyCoreFFI.instance.getStats();
      _ref.read(trafficStatsProvider.notifier).update(snapshot);
    });
  }
}

final vpnControllerProvider = StateNotifierProvider<VPNController, VPNStatus>((ref) {
  return VPNController(ref);
});

// IP Info Notifier
class IPInfoNotifier extends StateNotifier<IPInfo> {
  IPInfoNotifier() : super(IPInfo.disconnected);

  void updateForProxy(ProxyNodeModel node) {
    state = IPInfo(
      ip: node.server,
      country: node.name.contains('DE') ? 'Germany' : (node.name.contains('US') ? 'United States' : 'Secure Tunnel'),
      countryCode: 'VPN',
      city: 'Encrypted Gateway',
      isp: 'EasyVPN Tunnel Core',
    );
  }

  void reset() {
    state = IPInfo.disconnected;
  }
}

final ipInfoProvider = StateNotifierProvider<IPInfoNotifier, IPInfo>((ref) {
  return IPInfoNotifier();
});

// Traffic Stats
class TrafficStats {
  final int uploadSpeed;
  final int downloadSpeed;
  final int totalUpload;
  final int totalDownload;
  final int connections;

  TrafficStats({
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.totalUpload = 0,
    this.totalDownload = 0,
    this.connections = 0,
  });
}

class TrafficStatsNotifier extends StateNotifier<TrafficStats> {
  TrafficStatsNotifier() : super(TrafficStats());

  void update(Map<String, dynamic> snapshot) {
    state = TrafficStats(
      uploadSpeed: snapshot['upload_speed'] ?? 0,
      downloadSpeed: snapshot['download_speed'] ?? 0,
      totalUpload: snapshot['total_upload'] ?? 0,
      totalDownload: snapshot['total_download'] ?? 0,
      connections: snapshot['connections'] ?? 0,
    );
  }

  void reset() {
    state = TrafficStats();
  }
}

final trafficStatsProvider = StateNotifierProvider<TrafficStatsNotifier, TrafficStats>((ref) {
  return TrafficStatsNotifier();
});

// Node Search and Filter
final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedGroupProvider = StateProvider<String>((ref) => 'All');

final filteredNodesProvider = Provider<List<ProxyNodeModel>>((ref) {
  final nodes = ref.watch(nodesProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final group = ref.watch(selectedGroupProvider);

  return nodes.where((node) {
    final matchesQuery = query.isEmpty ||
        node.name.toLowerCase().contains(query) ||
        node.server.toLowerCase().contains(query) ||
        node.type.toLowerCase().contains(query);

    final matchesGroup = group == 'All' ||
        (group == 'Favorites' && node.isFavorite) ||
        node.group == group;

    return matchesQuery && matchesGroup;
  }).toList();
});
