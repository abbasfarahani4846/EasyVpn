import 'dart:async';

import 'country_bypass/country_bypass_store.dart';
import 'entry_server/entry_server_chain.dart';
import 'entry_server/entry_server_store.dart';
import 'psiphon/psiphon_manager.dart';

/// Single seam for what the easy features need from the app's connect cycle.
/// The generated profile and the run state each call it once, so a new feature
/// adds no hook to upstream files.
class EasyConfig {
  const EasyConfig._();

  static bool _running = false;

  static Future<Map<String, dynamic>> apply(
    Map<String, dynamic> rawConfig,
  ) async {
    var config = rawConfig;
    config = await EntryServerStore.applyStored(config);
    config = await CountryBypassStore.applyStored(config);
    if (_running && PsiphonManager.isPsiphonNodeIn(config)) {
      final entry = await EntryServerStore.load();
      await PsiphonManager.instance.setUpstream(
        entry == null
            ? null
            : 'socks5://127.0.0.1:${EntryServerChain.listenerPort}',
      );
      // Not awaited: with an entry server the Psiphon core can only connect
      // once this config is applied and the listener below is up.
      unawaited(PsiphonManager.instance.start());
    }
    return config;
  }

  /// Called whenever the app starts or stops proxying.
  static void onRunning(bool running) {
    _running = running;
    if (!running) unawaited(PsiphonManager.instance.stop());
  }
}
