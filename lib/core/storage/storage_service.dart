import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class StorageService {
  static const String _keySettings = 'app_settings';
  static const String _keyProfiles = 'app_profiles';
  static const String _keyNodes = 'app_nodes';
  static const String _keyActiveNodeId = 'active_node_id';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // Settings
  AppSettingsModel getSettings() {
    final raw = _prefs.getString(_keySettings);
    if (raw == null) return AppSettingsModel();
    try {
      return AppSettingsModel.fromMap(jsonDecode(raw));
    } catch (_) {
      return AppSettingsModel();
    }
  }

  Future<void> saveSettings(AppSettingsModel settings) async {
    await _prefs.setString(_keySettings, jsonEncode(settings.toMap()));
  }

  // Active Node
  String? getActiveNodeId() {
    return _prefs.getString(_keyActiveNodeId);
  }

  Future<void> setActiveNodeId(String? id) async {
    if (id == null) {
      await _prefs.remove(_keyActiveNodeId);
    } else {
      await _prefs.setString(_keyActiveNodeId, id);
    }
  }

  // Profiles
  List<ProfileModel> getProfiles() {
    final raw = _prefs.getString(_keyProfiles);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((item) => ProfileModel.fromMap(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<ProfileModel> profiles) async {
    final raw = jsonEncode(profiles.map((p) => p.toMap()).toList());
    await _prefs.setString(_keyProfiles, raw);
  }

  Future<void> addProfile(ProfileModel profile) async {
    final list = getProfiles();
    list.removeWhere((p) => p.id == profile.id);
    list.add(profile);
    await saveProfiles(list);
  }

  Future<void> deleteProfile(String profileId) async {
    final list = getProfiles();
    list.removeWhere((p) => p.id == profileId);
    await saveProfiles(list);
  }

  // Nodes
  List<ProxyNodeModel> getNodes() {
    final raw = _prefs.getString(_keyNodes);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((item) => ProxyNodeModel.fromMap(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNodes(List<ProxyNodeModel> nodes) async {
    final raw = jsonEncode(nodes.map((n) => n.toMap()).toList());
    await _prefs.setString(_keyNodes, raw);
  }

  Future<void> addNodes(List<ProxyNodeModel> newNodes) async {
    final existing = getNodes();
    final map = {for (var n in existing) n.id: n};
    for (var n in newNodes) {
      map[n.id] = n;
    }
    await saveNodes(map.values.toList());
  }

  Future<void> updateNodeLatency(String nodeId, int latencyMs) async {
    final existing = getNodes();
    final idx = existing.indexWhere((n) => n.id == nodeId);
    if (idx != -1) {
      existing[idx] = existing[idx].copyWith(latencyMs: latencyMs);
      await saveNodes(existing);
    }
  }

  Future<void> toggleNodeFavorite(String nodeId) async {
    final existing = getNodes();
    final idx = existing.indexWhere((n) => n.id == nodeId);
    if (idx != -1) {
      existing[idx] = existing[idx].copyWith(isFavorite: !existing[idx].isFavorite);
      await saveNodes(existing);
    }
  }

  Future<void> deleteNode(String nodeId) async {
    final existing = getNodes();
    existing.removeWhere((n) => n.id == nodeId);
    await saveNodes(existing);
  }

  Future<void> clearAllNodes() async {
    await _prefs.remove(_keyNodes);
  }
}
