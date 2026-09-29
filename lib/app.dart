import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/models.dart';
import 'core/providers/core_provider.dart';
import 'core/providers/nav_provider.dart';
import 'core/providers/profiles_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/logs/logs_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/proxies/proxies_page.dart';
import 'features/routing/routing_page.dart';
import 'features/settings/settings_page.dart';
import 'features/subscription/subscription_page.dart';
import 'l10n/strings.dart';
import 'platform/desktop_shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class EasyVpnApp extends ConsumerWidget {
  const EasyVpnApp({
    super.key,
    required this.startMinimized,
    this.desktopShell,
  });
  final bool startMinimized;

  /// Overrides desktop window/tray integration (tests pass false).
  final bool? desktopShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(settingsProvider.select((s) => s.appearance));
    Locale? locale = switch (a.locale) {
      'en' => const Locale('en'),
      'fa' => const Locale('fa'),
      _ => null,
    };

    return AppTheme.withDynamic(a.dynamicColor, (light, dark) {
      Widget app = MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'EasyVPN',
        theme: AppTheme.build(a, Brightness.light, dynamicScheme: light),
        darkTheme: AppTheme.build(a, Brightness.dark, dynamicScheme: dark),
        themeMode: AppTheme.mode(a.themeMode),
        locale: locale,
        supportedLocales: S.supported,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeResolutionCallback: (l, supported) => supported.firstWhere(
          (s) => s.languageCode == l?.languageCode,
          orElse: () => const Locale('en'),
        ),
        builder: (context, child) {
          // Text-scale customization applies on top of the OS setting.
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(
                mq.textScaler.scale(1) * a.fontScale,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        routes: {'/logs': (_) => const LogsPage()},
        home: const _Root(),
      );
      if (desktopShell ?? isDesktopPlatform) {
        app = DesktopShell(startMinimized: startMinimized, child: app);
      }
      return app;
    });
  }
}

/// Decides between onboarding and the main shell; wires background services.
class _Root extends ConsumerStatefulWidget {
  const _Root();
  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _initLinks();
    // Optional auto-connect on launch.
    Future.microtask(() {
      final s = ref.read(settingsProvider);
      if (s.autoConnect && s.onboarded)
        ref.read(coreControllerProvider.notifier).connect();
    });
  }

  Future<void> _initLinks() async {
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) _handle(initial);
      _links = links.uriLinkStream.listen(_handle);
    } catch (_) {
      // deep links unsupported on this platform build
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  /// Handles easyvpn://import?url=…, sing-box://import-remote-profile?url=…,
  /// clash://install-config?url=…, hiddify://import/URL and raw share links.
  void _handle(Uri uri) {
    String? payload;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'easyvpn' ||
        scheme == 'sing-box' ||
        scheme == 'clash' ||
        scheme == 'clashmeta' ||
        scheme == 'stash') {
      payload = uri.queryParameters['url'];
    } else if (scheme == 'hiddify') {
      final raw = uri.toString();
      final i = raw.indexOf('/import/');
      payload = i >= 0
          ? Uri.decodeFull(raw.substring(i + 8))
          : uri.queryParameters['url'];
    } else if (const {
      'vless',
      'vmess',
      'trojan',
      'ss',
      'hysteria2',
      'hy2',
      'tuic',
      'wireguard',
      'anytls',
    }.contains(scheme)) {
      payload = uri.toString();
    }
    if (payload == null || payload.isEmpty) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !mounted) return;
    ref.read(navProvider.notifier).go(Dest.profiles);
    showAddSheet(ctx, ref, prefillUrl: payload);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(subscriptionSchedulerProvider);
    final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
    return onboarded ? const AppShell() : const OnboardingPage();
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _pages = <Widget>[
    DashboardPage(),
    ProxiesPage(),
    SubscriptionPage(),
    RoutingPage(),
    SettingsPage(),
  ];
  static const _icons = [
    Icons.home_outlined,
    Icons.dns_outlined,
    Icons.cloud_outlined,
    Icons.alt_route,
    Icons.settings_outlined,
  ];
  static const _selIcons = [
    Icons.home,
    Icons.dns,
    Icons.cloud,
    Icons.alt_route,
    Icons.settings,
  ];
  static const _keys = [
    'nav.dashboard',
    'nav.proxies',
    'nav.subscriptions',
    'nav.routing',
    'nav.settings',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(navProvider);
    final style = ref.watch(
      settingsProvider.select((s) => s.appearance.navStyle),
    );
    final s = context.s;
    final core = ref.watch(coreControllerProvider);

    return LayoutBuilder(
      builder: (context, c) {
        final rail = style == 'rail' || (style == 'auto' && c.maxWidth >= 800);
        final body = IndexedStack(index: index, children: _pages);
        final connectedDot = core.status == CoreStatus.connected;

        if (rail) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: ref.read(navProvider.notifier).go,
                  labelType: c.maxWidth >= 1000
                      ? NavigationRailLabelType.all
                      : NavigationRailLabelType.selected,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Icon(
                      Icons.shield_moon,
                      color: connectedDot
                          ? const Color(0xFF22C55E)
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  destinations: [
                    for (var i = 0; i < 5; i++)
                      NavigationRailDestination(
                        icon: Icon(_icons[i]),
                        selectedIcon: Icon(_selIcons[i]),
                        label: Text(s.t(_keys[i])),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: ref.read(navProvider.notifier).go,
            destinations: [
              for (var i = 0; i < 5; i++)
                NavigationDestination(
                  icon: Icon(_icons[i]),
                  selectedIcon: Icon(_selIcons[i]),
                  label: s.t(_keys[i]),
                ),
            ],
          ),
        );
      },
    );
  }
}
