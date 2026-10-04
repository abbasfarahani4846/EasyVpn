import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entry_server_chain.dart';

/// Keeps the chosen entry proxy as a full proxy map, so it keeps working when
/// the user switches to a profile that does not contain that server.
class EntryServerStore {
  const EntryServerStore._();

  static const _prefsKey = 'easy.entry_server';

  /// Bumped whenever the entry server changes, so the dashboard card reloads.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<Map<String, Object?>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(Map<String, Object?> proxy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(proxy));
    version.value++;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    version.value++;
  }

  static Future<Map<String, dynamic>> applyStored(
    Map<String, dynamic> rawConfig,
  ) async => EntryServerChain.apply(rawConfig, await load());
}
