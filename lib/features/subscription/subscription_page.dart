import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/ffi/easy_core_ffi.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  final TextEditingController _importController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _importController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _processImport(String content, {String? customName}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      String finalContent = trimmed;
      String subName = customName ?? 'Subscription';

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        final uri = Uri.parse(trimmed);
        subName = customName ?? (uri.host.isNotEmpty ? uri.host : 'Subscription');

        final resp = await http.get(uri).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          finalContent = resp.body;
        } else {
          throw Exception('Failed to download subscription: HTTP ${resp.statusCode}');
        }
      }

      final result = EasyCoreFFI.instance.parseSubscription(finalContent);
      final rawNodes = result['nodes'] as List<dynamic>? ?? [];

      if (rawNodes.isEmpty) {
        throw Exception('No valid proxy configurations found');
      }

      final parsedModels = rawNodes.map((n) {
        final m = n as Map<String, dynamic>;
        return ProxyNodeModel.fromMap(m).copyWith(group: subName);
      }).toList();

      await ref.read(nodesProvider.notifier).addNodes(parsedModels);

      // Save Profile
      final profile = ProfileModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: subName,
        url: trimmed.startsWith('http') ? trimmed : 'Manual Import',
        lastUpdated: DateTime.now(),
        nodeCount: parsedModels.length,
        uploadBytes: 15 * 1024 * 1024 * 1024,   // 15 GB simulated
        downloadBytes: 38 * 1024 * 1024 * 1024, // 38 GB simulated
        totalBytes: 100 * 1024 * 1024 * 1024,   // 100 GB simulated
        expireDate: DateTime.now().add(const Duration(days: 28)),
      );
      await ref.read(profilesProvider.notifier).addProfile(profile);

      if (mounted) {
        _importController.clear();
        _nameController.clear();
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${parsedModels.length} nodes into "$subName"!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showImportDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add Subscription or Config', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Profile Name (Optional)',
                  hintText: 'e.g. My Premium Proxy',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _importController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Subscription URL or Direct Links',
                  hintText: 'Paste https://... or vless://, vmess://, hysteria2:// links',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.paste_rounded, size: 18),
                      label: const Text('Clipboard'),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _importController.text = data!.text!;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: _isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Import'),
                      onPressed: _isLoading ? null : () => _processImport(_importController.text, customName: _nameController.text.isNotEmpty ? _nameController.text : null),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQrDialog(String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profile QR Code'),
        content: SizedBox(
          width: 240,
          height: 240,
          child: Center(
            child: QrImageView(
              data: content,
              version: QrVersions.auto,
              size: 220,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _formatGB(int bytes) {
    return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    final allNodes = ref.watch(nodesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Add Subscription',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: _showImportDialog,
          ),
        ],
      ),
      body: profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text('No Subscriptions Added', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  const Text('Add your subscription link to auto-fetch and update nodes.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Subscription'),
                    onPressed: _showImportDialog,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final p = profiles[index];
                final usedBytes = p.uploadBytes + p.downloadBytes;
                final totalBytes = p.totalBytes > 0 ? p.totalBytes : 1;
                final progress = (usedBytes / totalBytes).clamp(0.0, 1.0);

                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${p.nodeCount} Outbound Nodes',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                                  tooltip: 'Show QR',
                                  onPressed: () => _showQrDialog(p.url),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.sync_rounded, size: 20),
                                  tooltip: 'Sync Now',
                                  onPressed: () => _processImport(p.url, customName: p.name),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                                  tooltip: 'Delete',
                                  onPressed: () => ref.read(profilesProvider.notifier).deleteProfile(p.id),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Traffic Usage Bar
                        if (p.totalBytes > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Data: ${_formatGB(usedBytes)} GB / ${_formatGB(p.totalBytes)} GB',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              if (p.expireDate != null)
                                Text(
                                  'Expires: ${p.expireDate!.day}/${p.expireDate!.month}/${p.expireDate!.year}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: theme.colorScheme.surface,
                              color: progress > 0.85 ? Colors.red : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
