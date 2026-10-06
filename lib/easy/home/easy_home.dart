import 'dart:async';

import 'package:fl_clash/easy/update/easy_update_banner.dart';
import 'package:fl_clash/easy/update/easy_update_provider.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps the dashboard grid. Its only job is to give the dashboard a minimal
/// layout built from EasyVpn's own widgets plus the easy ones, once; after
/// that the layout belongs to the user (the dashboard's edit mode moves,
/// removes and adds widgets as usual).
class EasyDashboardTop extends ConsumerStatefulWidget {
  final Widget child;

  const EasyDashboardTop({super.key, required this.child});

  @override
  ConsumerState<EasyDashboardTop> createState() => _EasyDashboardTopState();
}

class _EasyDashboardTopState extends ConsumerState<EasyDashboardTop> {
  static const _flag = 'easy.dashboard.layout.v1';

  /// Connect first, then the IP card, the two switches that matter, outbound
  /// mode and the chain route. Everything else stays one tap away in "add".
  static const minimalLayout = [
    DashboardWidget.easyConnect,
    DashboardWidget.networkDetection,
    DashboardWidget.tunButton,
    DashboardWidget.systemProxyButton,
    DashboardWidget.outboundMode,
    DashboardWidget.easyRoute,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_apply());
      ref.read(easyUpdateProvider.notifier).start();
    });
  }

  Future<void> _apply() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_flag) ?? false) return;
      ref
          .read(appSettingProvider.notifier)
          .update((s) => s.copyWith(dashboardWidgets: minimalLayout));
      await prefs.setBool(_flag, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) =>
      Column(children: [const EasyUpdateBanner(), widget.child]);
}
