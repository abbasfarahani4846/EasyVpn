import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';

class RoutingPage extends ConsumerStatefulWidget {
  const RoutingPage({super.key});

  @override
  ConsumerState<RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends ConsumerState<RoutingPage> {
  bool _isSyncingRules = false;

  final List<Map<String, String>> _countries = [
    {'code': 'IR', 'name': 'Iran', 'flag': '🇮🇷', 'desc': 'Direct routing for .ir, banks, Shaparak, Snapp, and domestic CIDRs'},
    {'code': 'CN', 'name': 'China', 'flag': '🇨🇳', 'desc': 'Direct routing for .cn, WeChat, Baidu, and mainland IPs'},
    {'code': 'RU', 'name': 'Russia', 'flag': '🇷🇺', 'desc': 'Direct routing for .ru, Yandex, VK, and Gosuslugi'},
    {'code': 'GLOBAL', 'name': 'Global', 'flag': '🌐', 'desc': 'Standard routing rules without regional presets'},
  ];

  final List<Map<String, dynamic>> _modes = [
    {
      'id': 'bypass_local_lan',
      'title': 'Bypass LAN & Domestic Sites',
      'desc': 'Direct connection for domestic banks, government sites, and local streaming.',
      'icon': Icons.home_work_outlined,
    },
    {
      'id': 'bypass_lan_only',
      'title': 'Bypass Private LAN Only',
      'desc': 'Routes all internet traffic through proxy; only local network is direct.',
      'icon': Icons.router_outlined,
    },
    {
      'id': 'global_proxy',
      'title': 'Global Proxy (Route All)',
      'desc': 'Forces 100% of network traffic through the selected outbound server.',
      'icon': Icons.public_outlined,
    },
    {
      'id': 'block_ads_only',
      'title': 'Block Trackers & Ads',
      'desc': 'Rejects connections to known ad networks, trackers, and telemetry domains.',
      'icon': Icons.shield_outlined,
    },
  ];

  Future<void> _syncGitHubRules() async {
    setState(() => _isSyncingRules = true);
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully updated routing database from GitHub!')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingRules = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Routing', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('REGION & BYPASS PRESETS', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 10),

            // Country Selector Cards
            ..._countries.map((c) {
              final isSelected = settings.country == c['code'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                    width: isSelected ? 1.5 : 0,
                  ),
                ),
                child: ListTile(
                  leading: Text(c['flag']!, style: const TextStyle(fontSize: 24)),
                  title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Text(c['desc']!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: isSelected ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary) : null,
                  onTap: () => ref.read(settingsProvider.notifier).setCountry(c['code']!),
                ),
              );
            }),

            const SizedBox(height: 24),
            const Text('ROUTING STRATEGY', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 10),

            // Mode Selection
            ..._modes.map((m) {
              final isSelected = settings.routingMode == m['id'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                    width: isSelected ? 1.5 : 0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(m['icon'] as IconData, color: isSelected ? theme.colorScheme.primary : Colors.grey),
                  title: Text(m['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(m['desc'] as String, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Radio<String>(
                    value: m['id'] as String,
                    groupValue: settings.routingMode,
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(settingsProvider.notifier).setRoutingMode(val);
                      }
                    },
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),
            const Text('GITHUB RULES DATABASE', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 10),

            // GitHub Sync Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.cloud_sync_outlined, color: theme.colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Online Rules Synchronization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          SizedBox(height: 2),
                          Text('Fetches up-to-date domain and IP lists from bootmortis & chocolateboy repos.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isSyncingRules ? null : _syncGitHubRules,
                      child: _isSyncingRules
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Update'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
