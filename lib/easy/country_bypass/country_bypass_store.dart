import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'country_bypass_config.dart';

class CountryBypassStore {
  const CountryBypassStore._();

  static const _prefsKey = 'easy.country_bypass';

  static Future<CountrySelection?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      return CountrySelection.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(CountrySelection selection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(selection.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Future<Map<String, dynamic>> applyStored(
    Map<String, dynamic> rawConfig,
  ) async => CountryBypassConfig.apply(rawConfig, await load());
}
