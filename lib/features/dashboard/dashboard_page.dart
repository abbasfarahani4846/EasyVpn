import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String _formatTotalBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnStatus = ref.watch(vpnControllerProvider);
    final stats = ref.watch(trafficStatsProvider);
    final activeNode = ref.watch(activeNodeProvider);
    final settings = ref.watch(settingsProvider);
    final duration = ref.watch(connectionDurationProvider);
    final ipInfo = ref.watch(ipInfoProvider);
    final theme = Theme.of(context);

    final isConnected = vpnStatus == VPNStatus.connected;
    final isConnecting = vpnStatus == VPNStatus.connecting;

    final statusColor = isConnected
        ? const Color(0xFF10B981) // Emerald Green
        : (isConnecting ? const Color(0xFFF59E0B) : const Color(0xFF64748B));

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar: Region and Quick Mode
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'EasyVPN',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isConnected
                                ? 'Connected (${_formatDuration(duration)})'
                                : (isConnecting ? 'Connecting...' : 'Disconnected'),
                            style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.shade800),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.language, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          settings.country,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          settings.routingMode == 'bypass_local_lan' ? 'Bypass' : 'Global',
                          style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              // Hero Connection Card
              Center(
                child: GestureDetector(
                  onTap: () => ref.read(vpnControllerProvider.notifier).toggle(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.cardTheme.color,
                      border: Border.all(
                        color: statusColor.withOpacity(isConnected ? 0.8 : 0.25),
                        width: isConnected ? 3 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(isConnected ? 0.25 : 0.05),
                          blurRadius: isConnected ? 40 : 15,
                          spreadRadius: isConnected ? 8 : 0,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isConnecting)
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.orange),
                          )
                        else
                          Icon(
                            Icons.power_settings_new_rounded,
                            size: 64,
                            color: statusColor,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          isConnected ? 'TAP TO STOP' : (isConnecting ? 'CONNECTING' : 'TAP TO CONNECT'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 36),

              // Network Telemetry (Minimal Dual Stat Grid)
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.blue),
                                ),
                                const SizedBox(width: 8),
                                const Text('DOWNLOAD', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _formatSpeed(stats.downloadSpeed),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total: ${_formatTotalBytes(stats.totalDownload)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.purple),
                                ),
                                const SizedBox(width: 8),
                                const Text('UPLOAD', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _formatSpeed(stats.uploadSpeed),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total: ${_formatTotalBytes(stats.totalUpload)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Active Node Card with Quick Selector
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showQuickNodeSwitcher(context, ref),
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
                          child: Icon(Icons.dns_rounded, color: theme.colorScheme.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeNode?.name ?? 'Select a Proxy Node',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                activeNode != null
                                    ? '${activeNode.type.toUpperCase()} • ${activeNode.server}:${activeNode.port}'
                                    : 'Tap to pick from your imported configs',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (activeNode != null && activeNode.latencyMs > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: activeNode.latencyMs < 200
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${activeNode.latencyMs}ms',
                              style: TextStyle(
                                color: activeNode.latencyMs < 200 ? Colors.green : Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Location & IP Protection Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isConnected ? Colors.green : Colors.grey).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isConnected ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                          color: isConnected ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isConnected ? 'Tunnel Gateway: ${ipInfo.country}' : 'Direct Connection',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isConnected
                                  ? 'IP: ${ipInfo.ip} • Anti-DNS Leak Active'
                                  : 'Traffic unencrypted. Tap connect to protect.',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickNodeSwitcher(BuildContext context, WidgetRef ref) {
    final nodes = ref.read(nodesProvider);
    final activeId = ref.read(activeNodeIdProvider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Select Outbound Node', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              const SizedBox(height: 12),
              if (nodes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No proxies imported yet.', style: TextStyle(color: Colors.grey))),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: nodes.length,
                    itemBuilder: (c, i) {
                      final n = nodes[i];
                      final isSelected = n.id == activeId;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          child: Text(n.type.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${n.server}:${n.port}'),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                        onTap: () {
                          ref.read(activeNodeIdProvider.notifier).state = n.id;
                          ref.read(storageServiceProvider).setActiveNodeId(n.id);
                          if (ref.read(vpnControllerProvider) == VPNStatus.connected) {
                            ref.read(vpnControllerProvider.notifier).connect();
                          }
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
