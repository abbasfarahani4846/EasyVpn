import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ffi/easy_core_ffi.dart';
import '../../core/providers/app_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  final List<Color> _accentColors = const [
    Color(0xFF3B82F6), // Minimal Blue
    Color(0xFF8B5CF6), // Royal Violet
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber Gold
    Color(0xFFEF4444), // Crimson
    Color(0xFF06B6D4), // Cyan
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final isCoreLoaded = EasyCoreFFI.instance.isLoaded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Section: Network & Engine
          const Text('TUN & NETWORK ENGINE', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('TUN Virtual Adapter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Routes entire OS traffic (Wintun / VpnService / NetworkExtension)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: settings.tunEnabled,
                  onChanged: (_) => ref.read(settingsProvider.notifier).toggleTun(),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Auto-Connect on Launch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Starts tunnel immediately when EasyVPN is opened', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: settings.autoConnect,
                  onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(autoConnect: val)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section: Appearance
          const Text('APPEARANCE & THEME', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('AMOLED Pure Black', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('True black dark background optimized for OLED displays', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: settings.isDarkMode,
                    onChanged: (_) => ref.read(settingsProvider.notifier).toggleDarkMode(),
                  ),
                  const SizedBox(height: 14),
                  const Text('Accent Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: _accentColors.map((col) {
                      final isSelected = settings.accentColorValue == col.value;
                      return GestureDetector(
                        onTap: () => ref.read(settingsProvider.notifier).setAccentColor(col.value),
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Section: Core Diagnostics & Info
          const Text('CORE & DIAGNOSTICS', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isCoreLoaded ? Colors.green : Colors.orange).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.memory, color: isCoreLoaded ? Colors.green : Colors.orange, size: 20),
                  ),
                  title: const Text('Native Core Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    isCoreLoaded ? 'Go Core (libeasycore) Active' : 'Dart Mock Emulator Mode',
                    style: TextStyle(color: isCoreLoaded ? Colors.green : Colors.orange, fontSize: 12),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_outlined, color: Colors.blue, size: 20),
                  ),
                  title: const Text('Supported Protocols', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('VLESS (Reality/Vision), VMess, Trojan, Shadowsocks, WireGuard, Hysteria 2, TUIC v5, OpenVPN', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.info_outline, color: Colors.purple, size: 20),
                  ),
                  title: const Text('EasyVPN Client', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Version 1.0.0 (Go Core + Flutter UI)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
