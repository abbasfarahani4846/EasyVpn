import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/settings_provider.dart';
import '../../l10n/strings.dart';
import '../../theme/brand.dart';
import '../chain/chain_page.dart';
import '../logs/logs_page.dart';
import '../proxies/proxies_page.dart';
import '../routing/routing_page.dart';
import '../settings/settings_page.dart';
import '../settings/updates_page.dart';
import '../subscription/subscription_page.dart';
import '../windscribe/windscribe_page.dart';

enum MenuTarget {
  servers,
  proxies,
  routing,
  chain,
  windscribe,
  updates,
  settings,
  logs,
}

Widget _pageFor(MenuTarget t) => switch (t) {
  MenuTarget.servers => const SubscriptionPage(),
  MenuTarget.proxies => const ProxiesPage(),
  MenuTarget.routing => const RoutingPage(),
  MenuTarget.chain => const ChainPage(),
  MenuTarget.windscribe => const WindscribePage(),
  MenuTarget.updates => const UpdatesPage(),
  MenuTarget.settings => const SettingsPage(),
  MenuTarget.logs => const LogsPage(),
};

/// Opens an advanced page on top of the simple home.
void openMenuPage(BuildContext context, MenuTarget t) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _pageFor(t)));
}

/// The "everything else" sheet: all advanced features, one tap away.
Future<void> showHomeMenu(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Brand.night2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.radius)),
    ),
    builder: (ctx) => const _MenuSheet(),
  );
}

class _MenuSheet extends ConsumerWidget {
  const _MenuSheet();

  static const _items = <(MenuTarget, IconData, String)>[
    (MenuTarget.servers, Icons.cloud_download_rounded, 'menu.servers'),
    (MenuTarget.proxies, Icons.dns_rounded, 'menu.proxies'),
    (MenuTarget.chain, Icons.link_rounded, 'menu.chain'),
    (MenuTarget.windscribe, Icons.air_rounded, 'menu.windscribe'),
    (MenuTarget.routing, Icons.alt_route_rounded, 'menu.routing'),
    (MenuTarget.updates, Icons.system_update_rounded, 'menu.updates'),
    (MenuTarget.settings, Icons.tune_rounded, 'menu.settings'),
    (MenuTarget.logs, Icons.receipt_long_rounded, 'menu.logs'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return Theme(
      data: Brand.theme(Theme.of(context)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.9,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final (t, icon, key) in _items)
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        Navigator.pop(context);
                        openMenuPage(context, t);
                      },
                      child: Container(
                        decoration: Brand.glass(radius: 18),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 26, color: Brand.on),
                            const SizedBox(height: 8),
                            Text(
                              s.t(key),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_rounded),
                title: Text(s.t('home.advanced')),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(settingsProvider.notifier)
                      .update((x) => x.copyWith(uiMode: 'advanced'));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
