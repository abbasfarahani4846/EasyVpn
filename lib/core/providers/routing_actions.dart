import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/core_bridge.dart';
import '../util/platform_service.dart';
import 'env.dart';
import 'rules_provider.dart';
import 'settings_provider.dart';

/// Country selection & detection workflows shared by onboarding and the routing page.
class RoutingActions extends Notifier<void> {
  @override
  void build() {}

  CoreBridge get _core => ref.read(envProvider).core;

  /// Applies [cc] ("IR", "CN", "RU" or "" for none): loads the country pack
  /// defaults (service overrides, TLS-fragment recommendation) and refreshes
  /// the rule-set cache in the background.
  Future<void> setCountry(String cc, {required bool auto}) async {
    final code = cc.toUpperCase();
    Map<String, dynamic>? pack;
    if (_core.isAvailable) {
      try {
        final r = await _core.setCountry(code);
        pack = (r['pack'] as Map?)?.cast<String, dynamic>();
      } on CoreException {
        // unknown country: keep going with global defaults
      }
    }
    final ov = (pack?['service_overrides'] as Map?)?.cast<String, dynamic>();
    final tricks = (pack?['tls_tricks'] as Map?)?.cast<String, dynamic>();
    ref
        .read(settingsProvider.notifier)
        .setRouting(
          (r) => r.copyWith(
            country: code,
            autoCountry: auto,
            overrideProxy: ((ov?['proxy'] as List?) ?? const []).cast<String>(),
            overrideDirect: ((ov?['direct'] as List?) ?? const [])
                .cast<String>(),
            tlsFragment: (tricks?['fragment'] as bool?) ?? false,
            mode: code.isEmpty && r.mode == 'bypass_local_country'
                ? 'global_proxy'
                : r.mode,
          ),
        );
    await ref.read(rulesProvider.notifier).applyCountry();
    if (code.isNotEmpty && ref.read(settingsProvider).routing.autoUpdateRules) {
      ref.read(rulesProvider.notifier).sync();
    }
  }

  /// Detects the country from SIM/network/locale/timezone. Returns "" if unknown.
  Future<String> detect() async {
    final locale = ui.PlatformDispatcher.instance.locale;
    final off = DateTime.now().timeZoneOffset;
    String? tz = await PlatformService.timezoneId();
    // Iran is the only place on UTC+03:30 (no DST since 2022).
    if (tz == null && off.inMinutes == 210) tz = 'Asia/Tehran';
    if (!_core.isAvailable) return '';
    final r = await _core.detectCountry(
      sim: await PlatformService.simCountry(),
      network: await PlatformService.networkCountry(),
      locale: locale.toLanguageTag().replaceAll('-', '_'),
      timezone: tz,
    );
    return r.country;
  }

  Future<String> detectAndApply() async {
    final cc = await detect();
    if (cc.isNotEmpty) await setCountry(cc, auto: true);
    return cc;
  }
}

final routingActionsProvider = NotifierProvider<RoutingActions, void>(
  RoutingActions.new,
);
