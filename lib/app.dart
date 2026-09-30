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
import 'theme/brand.dart';
import 'core/update/update_service.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/home/simple_home.dart';
import 'features/logs/logs_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/proxies/proxies_page.dart';
import 'features/routing/routing_page.dart';
import 'features/settings/settings_page.dart';
import 'features/subscription/subscription_page.dart';
import 'features/tools/tools_page.dart';
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
        // One consistent "liquid glass" look on every page and platform;
        // AppTheme still supplies the user's font scale / radius / density.
        theme: Brand.glassTheme(AppTheme.build(a, Brightness.dark)),
        darkTheme: Brand.glassTheme(AppTheme.build(a, Brightness.dark)),
        themeMode: ThemeMode.dark,
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
            child: GlassBackground(child: child ?? const SizedBox.shrink()),
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
    openVpnCredentialPrompt = _askOpenVpnCredentials;
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

  Future<({String user, String pass})?> _askOpenVpnCredentials(
    String nodeName,
  ) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return null;
    final s = ctx.s;
    final u = TextEditingController();
    final p = TextEditingController();
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(s.t('ovpn.creds.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nodeName, style: Theme.of(c).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              s.t('ovpn.creds.hint'),
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: u,
              autofocus: true,
              decoration: InputDecoration(labelText: s.t('ovpn.creds.user')),
            ),
            TextField(
              controller: p,
              obscureText: true,
              decoration: InputDecoration(labelText: s.t('ovpn.creds.pass')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(s.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(s.t('common.ok')),
          ),
        ],
      ),
    );
    if (ok != true || u.text.trim().isEmpty) return null;
    return (user: u.text.trim(), pass: p.text);
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
    ref.watch(updateProvider); // starts the periodic update check
    final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
    final simple = ref.watch(
      settingsProvider.select((s) => s.uiMode != 'advanced'),
    );
    if (!onboarded) return const OnboardingPage();
    return simple ? const SimpleHome() : const AppShell();
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  // Page index == navProvider value (Dest.*); order of the sidebar/bottom
  // bar is defined separately below.
  static const _pages = <Widget>[
    DashboardPage(),
    ProxiesPage(),
    SubscriptionPage(),
    RoutingPage(),
    SettingsPage(),
    ToolsPage(),
  ];

  static const _desktop = <(int, IconData, IconData, String)>[
    (Dest.dashboard, Icons.home_outlined, Icons.home_rounded, 'nav.dashboard'),
    (Dest.proxies, Icons.dns_outlined, Icons.dns_rounded, 'nav.proxies'),
    (
      Dest.profiles,
      Icons.cloud_outlined,
      Icons.cloud_rounded,
      'nav.subscriptions',
    ),
    (
      Dest.routing,
      Icons.alt_route_outlined,
      Icons.alt_route_rounded,
      'nav.routing',
    ),
    (Dest.tools, Icons.handyman_outlined, Icons.handyman_rounded, 'nav.tools'),
    (
      Dest.settings,
      Icons.settings_outlined,
      Icons.settings_rounded,
      'nav.settings',
    ),
  ];

  // Mobile keeps five tabs; Routing lives under Tools there.
  static const _mobile = <(int, IconData, IconData, String)>[
    (Dest.dashboard, Icons.home_outlined, Icons.home_rounded, 'nav.dashboard'),
    (Dest.proxies, Icons.dns_outlined, Icons.dns_rounded, 'nav.proxies'),
    (
      Dest.profiles,
      Icons.cloud_outlined,
      Icons.cloud_rounded,
      'nav.subscriptions',
    ),
    (Dest.tools, Icons.handyman_outlined, Icons.handyman_rounded, 'nav.tools'),
    (
      Dest.settings,
      Icons.settings_outlined,
      Icons.settings_rounded,
      'nav.settings',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(navProvider);
    final s = context.s;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        final body = IndexedStack(index: index, children: _pages);
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(items: _desktop, index: index),
                Expanded(child: body),
              ],
            ),
          );
        }
        final items = _mobile;
        final sel = items.indexWhere((e) => e.$1 == index);
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            height: 66,
            selectedIndex: sel < 0 ? 0 : sel,
            onDestinationSelected: (i) =>
                ref.read(navProvider.notifier).go(items[i].$1),
            destinations: [
              for (final (_, icon, selIcon, key) in items)
                NavigationDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selIcon),
                  label: s.t(key),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Desktop sidebar: brand, sections, and a live connection card with a
/// one-click connect/cancel/disconnect button (Hiddify / Karing style).
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.items, required this.index});
  final List<(int, IconData, IconData, String)> items;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final core = ref.watch(coreControllerProvider);
    final c = Brand.forStatus(core.status);
    return Container(
      width: 232,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: Brand.glass(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: Brand.orbGradient(
                    core.isConnected
                        ? CoreStatus.connected
                        : CoreStatus.disconnected,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.shield_rounded, size: 19),
              ),
              const SizedBox(width: 10),
              const Text(
                'EasyVPN',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final (dest, icon, selIcon, key) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: dest == index
                    ? Brand.on.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => ref.read(navProvider.notifier).go(dest),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          dest == index ? selIcon : icon,
                          size: 21,
                          color: dest == index ? Brand.on : Brand.textDim,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          s.t(key),
                          style: TextStyle(
                            fontWeight: dest == index
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: dest == index ? Brand.text : Brand.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  core.isConnected
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  color: c,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    core.isConnected
                        ? s.t('home.protected')
                        : (core.status == CoreStatus.connecting
                              ? s.t('home.connecting')
                              : s.t('home.unprotected')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: c.withValues(alpha: 0.25),
                    foregroundColor: Brand.text,
                  ),
                  iconSize: 20,
                  onPressed: core.status == CoreStatus.unavailable
                      ? null
                      : () =>
                            ref.read(coreControllerProvider.notifier).toggle(),
                  icon: const Icon(Icons.power_settings_new_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.radio_button_checked, size: 18),
            label: Text(s.t('home.simple')),
            onPressed: () => ref
                .read(settingsProvider.notifier)
                .update((x) => x.copyWith(uiMode: 'simple')),
          ),
        ],
      ),
    );
  }
}
