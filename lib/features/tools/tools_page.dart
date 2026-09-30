import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/brand.dart';
import '../home/home_menu.dart';

/// Advanced layout: every tool in one tidy grid (same targets as the simple
/// layout's menu, so both layouts stay in sync).
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static const _items = <(MenuTarget, IconData, String, String)>[
    (MenuTarget.add, Icons.add_circle_rounded, 'menu.add', 'tools.add'),
    (
      MenuTarget.sites,
      Icons.travel_explore_rounded,
      'menu.sites',
      'tools.sites',
    ),
    (MenuTarget.chain, Icons.link_rounded, 'menu.chain', 'tools.chain'),
    (MenuTarget.windscribe, Icons.air_rounded, 'menu.windscribe', 'tools.ws'),
    (
      MenuTarget.routing,
      Icons.alt_route_rounded,
      'menu.routing',
      'tools.routing',
    ),
    (
      MenuTarget.updates,
      Icons.system_update_rounded,
      'menu.updates',
      'tools.updates',
    ),
    (MenuTarget.logs, Icons.receipt_long_rounded, 'menu.logs', 'tools.logs'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('nav.tools'))),
      body: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
          return GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 1 ? 4.2 : 2.6,
            children: [
              for (final (t, icon, title, sub) in _items)
                InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => openMenuPage(context, t),
                  child: Container(
                    decoration: Brand.glass(radius: 22),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Brand.on.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: Brand.on),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.t(title),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                s.t(sub),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Brand.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
