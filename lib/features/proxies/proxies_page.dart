import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ffi/easy_core_ffi.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';

class ProxiesPage extends ConsumerStatefulWidget {
  const ProxiesPage({super.key});

  @override
  ConsumerState<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends ConsumerState<ProxiesPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isTestingPing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pingAllNodes() async {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty || _isTestingPing) return;

    setState(() => _isTestingPing = true);

    try {
      final nodesMap = nodes.map((n) => n.toMap()).toList();
      final results = EasyCoreFFI.instance.testBatchPing(nodesMap);

      for (var res in results) {
        if (res is Map) {
          final id = res['node_id']?.toString() ?? '';
          final latency = res['latency_ms'] is int ? res['latency_ms'] as int : -1;
          if (id.isNotEmpty) {
            await ref.read(nodesProvider.notifier).updateLatency(id, latency);
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingPing = false);
      }
    }
  }

  Color _getLatencyColor(int latency) {
    if (latency <= 0) return Colors.red;
    if (latency < 150) return Colors.green;
    if (latency < 300) return Colors.amber;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final filteredNodes = ref.watch(filteredNodesProvider);
    final activeNodeId = ref.watch(activeNodeIdProvider);
    final currentGroup = ref.watch(selectedGroupProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxies & Nodes', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Ping All Nodes',
            icon: _isTestingPing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bolt),
            onPressed: _isTestingPing ? null : _pingAllNodes,
          ),
          IconButton(
            tooltip: 'Clear All Nodes',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear All Proxies?'),
                  content: const Text('This will delete all imported proxy nodes.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                ref.read(nodesProvider.notifier).clearAll();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, server, or protocol...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                        },
                      )
                    : null,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => ref.read(searchQueryProvider.notifier).state = val,
            ),
          ),

          // Group Filtering Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: ['All', 'Favorites'].map((grp) {
                final isSelected = currentGroup == grp;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(grp),
                    selected: isSelected,
                    onSelected: (_) => ref.read(selectedGroupProvider.notifier).state = grp,
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          // Virtualized List
          Expanded(
            child: filteredNodes.isEmpty
                ? const Center(
                    child: Text(
                      'No proxies found.\nImport via Subscriptions tab.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredNodes.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemBuilder: (context, index) {
                      final node = filteredNodes[index];
                      final isSelected = node.id == activeNodeId;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                            width: isSelected ? 2 : 0,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            ref.read(activeNodeIdProvider.notifier).state = node.id;
                            await ref.read(storageServiceProvider).setActiveNodeId(node.id);
                            if (ref.read(vpnControllerProvider) == VPNStatus.connected) {
                              EasyCoreFFI.instance.switchProxy(node.toMap());
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Protocol Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    node.type.toUpperCase(),
                                    style: TextStyle(
                                      color: theme.colorScheme.onPrimaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Node Name & Server Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        node.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${node.server}:${node.port}',
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // Latency Indicator
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getLatencyColor(node.latencyMs).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    node.latencyMs > 0 ? '${node.latencyMs} ms' : (node.latencyMs == -1 ? 'Timeout' : 'Ping'),
                                    style: TextStyle(
                                      color: _getLatencyColor(node.latencyMs),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                                // Favorite Button
                                IconButton(
                                  icon: Icon(
                                    node.isFavorite ? Icons.star : Icons.star_border,
                                    size: 20,
                                    color: node.isFavorite ? Colors.amber : Colors.grey,
                                  ),
                                  onPressed: () => ref.read(nodesProvider.notifier).toggleFavorite(node.id),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
