import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/core_bridge.dart';
import '../models/models.dart';
import 'env.dart';
import 'settings_provider.dart';

class RulesState {
  const RulesState({
    this.statuses = const [],
    this.syncing = false,
    this.lastError,
    this.lastEvents = const [],
  });
  final List<RuleSetStatus> statuses;
  final bool syncing;
  final String? lastError;
  final List<Map<String, dynamic>> lastEvents;

  RulesState copyWith({
    List<RuleSetStatus>? statuses,
    bool? syncing,
    String? lastError,
    List<Map<String, dynamic>>? lastEvents,
  }) => RulesState(
    statuses: statuses ?? this.statuses,
    syncing: syncing ?? this.syncing,
    lastError: lastError,
    lastEvents: lastEvents ?? this.lastEvents,
  );
}

/// Rule-set cache status + sync (the Go core downloads; the app only orchestrates).
class RulesNotifier extends Notifier<RulesState> {
  Timer? _timer;

  @override
  RulesState build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(_init);
    return const RulesState();
  }

  CoreBridge get _core => ref.read(envProvider).core;

  Future<void> _init() async {
    if (!_core.isAvailable) return;
    await applyCountry();
    _timer = Timer.periodic(const Duration(hours: 6), (_) {
      if (ref.read(settingsProvider).routing.autoUpdateRules) sync();
    });
    if (ref.read(settingsProvider).routing.autoUpdateRules) {
      unawaited(sync());
    }
  }

  /// Pushes the selected country to the core (loads its pack) and refreshes status.
  Future<void> applyCountry() async {
    try {
      await _core.setCountry(ref.read(settingsProvider).routing.country);
      state = state.copyWith(statuses: await _core.ruleSetStatus());
    } catch (e) {
      state = state.copyWith(lastError: '$e');
    }
  }

  Future<void> refreshStatus() async {
    try {
      state = state.copyWith(statuses: await _core.ruleSetStatus());
    } catch (_) {}
  }

  Future<void> sync({List<String> tags = const []}) async {
    if (state.syncing || !_core.isAvailable) return;
    state = state.copyWith(syncing: true);
    try {
      await _core.setCountry(ref.read(settingsProvider).routing.country);
      final events = await _core.syncRuleSets(tags: tags);
      final statuses = await _core.ruleSetStatus();
      final failed = events
          .where((e) => e['status'] == 'failed' || e['status'] == 'baseline')
          .length;
      state = RulesState(
        statuses: statuses,
        lastEvents: events,
        lastError: failed == events.length && events.isNotEmpty
            ? 'all downloads failed'
            : null,
      );
    } on CoreException catch (e) {
      state = state.copyWith(syncing: false, lastError: e.message);
    }
  }
}

final rulesProvider = NotifierProvider<RulesNotifier, RulesState>(
  RulesNotifier.new,
);
