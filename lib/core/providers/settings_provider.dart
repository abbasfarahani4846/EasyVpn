import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'env.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  Timer? _debounce;

  @override
  AppSettings build() {
    ref.onDispose(() => _debounce?.cancel());
    return ref.read(envProvider).initialSettings;
  }

  /// Applies [fn] and persists (debounced) — many sliders/toggles can fire quickly.
  void update(AppSettings Function(AppSettings s) fn) {
    state = fn(state);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _flush);
  }

  Future<void> replace(AppSettings s) async {
    state = s;
    await _flush();
  }

  Future<void> _flush() =>
      ref.read(envProvider).db.kvSet('settings', state.encode());

  void setAppearance(AppearanceSettings Function(AppearanceSettings a) fn) =>
      update((s) => s.copyWith(appearance: fn(s.appearance)));

  void setRouting(RoutingSettings Function(RoutingSettings r) fn) =>
      update((s) => s.copyWith(routing: fn(s.routing)));
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
