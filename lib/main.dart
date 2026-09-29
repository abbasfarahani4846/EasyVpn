import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'core/ffi/easy_core_ffi.dart';
import 'core/providers/app_providers.dart';
import 'core/storage/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/proxies/proxies_page.dart';
import 'features/routing/routing_page.dart';
import 'features/settings/settings_page.dart';
import 'features/subscription/subscription_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistence
  final storageService = await StorageService.init();

  // Initialize Go Core FFI
  try {
    final appDir = await getApplicationSupportDirectory();
    EasyCoreFFI.instance.initialize(appDir.path);
  } catch (_) {
    EasyCoreFFI.instance.initialize('./cache');
  }

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: const EasyVpnApp(),
    ),
  );
}

class EasyVpnApp extends ConsumerWidget {
  const EasyVpnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accentColor = Color(settings.accentColorValue);

    return MaterialApp(
      title: 'EasyVPN',
      debugShowCheckedModeBanner: false,
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.lightTheme(accentColor),
      darkTheme: AppTheme.darkTheme(accentColor),
      home: const ResponsiveMainScreen(),
    );
  }
}

class ResponsiveMainScreen extends ConsumerStatefulWidget {
  const ResponsiveMainScreen({super.key});

  @override
  ConsumerState<ResponsiveMainScreen> createState() => _ResponsiveMainScreenState();
}

class _ResponsiveMainScreenState extends ConsumerState<ResponsiveMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    DashboardPage(),
    ProxiesPage(),
    SubscriptionPage(),
    RoutingPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final vpnStatus = ref.watch(vpnControllerProvider);
    final isConnected = vpnStatus == VPNStatus.connected;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;

        if (isDesktop) {
          // Desktop & Tablet Navigation Rail Layout
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
                  extended: constraints.maxWidth >= 1024,
                  minExtendedWidth: 200,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.shield_outlined, color: theme.colorScheme.primary, size: 24),
                        ),
                        if (constraints.maxWidth >= 1024) ...[
                          const SizedBox(width: 12),
                          const Text(
                            'EasyVPN',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: IconButton(
                          tooltip: isConnected ? 'Disconnect' : 'Connect',
                          icon: Icon(
                            Icons.power_settings_new,
                            color: isConnected ? Colors.green : Colors.grey,
                          ),
                          onPressed: () => ref.read(vpnControllerProvider.notifier).toggle(),
                        ),
                      ),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Dashboard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.dns_outlined),
                      selectedIcon: Icon(Icons.dns),
                      label: Text('Proxies'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.subscriptions_outlined),
                      selectedIcon: Icon(Icons.subscriptions),
                      label: Text('Subscriptions'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.alt_route_outlined),
                      selectedIcon: Icon(Icons.alt_route),
                      label: Text('Routing'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: IndexedStack(
                        index: _currentIndex,
                        children: _pages,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Mobile Bottom Navigation Bar Layout
        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns),
                label: 'Proxies',
              ),
              NavigationDestination(
                icon: Icon(Icons.subscriptions_outlined),
                selectedIcon: Icon(Icons.subscriptions),
                label: 'Profiles',
              ),
              NavigationDestination(
                icon: Icon(Icons.alt_route_outlined),
                selectedIcon: Icon(Icons.alt_route),
                label: 'Routing',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
