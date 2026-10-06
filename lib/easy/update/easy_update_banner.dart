import 'dart:async';

import 'package:easy_vpn/easy/update/easy_update_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Sits above the dashboard cards and shows only while a newer build exists.
class EasyUpdateBanner extends ConsumerWidget {
  const EasyUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(easyUpdateProvider);
    final info = update.info;
    if (info == null || update.phase == EasyUpdatePhase.none) {
      return const SizedBox.shrink();
    }
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final busy =
        update.phase == EasyUpdatePhase.downloading ||
        update.phase == EasyUpdatePhase.installing;
    final failed = update.phase == EasyUpdatePhase.failed;
    final foreground = failed
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;
    final percent = (update.progress * 100).round();
    final title = switch (update.phase) {
      EasyUpdatePhase.downloading =>
        fa ? 'در حال دانلود… $percent٪' : 'Downloading… $percent%',
      EasyUpdatePhase.installing => fa ? 'در حال نصب…' : 'Installing…',
      EasyUpdatePhase.failed => fa ? 'آپدیت انجام نشد' : 'Update failed',
      _ => fa ? 'نسخه جدید آماده است' : 'A new version is available',
    };
    final size = (info.assetSize / 1048576).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          color: failed ? scheme.errorContainer : scheme.primaryContainer,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed ? Icons.error_outline : Icons.system_update_alt,
                  color: foreground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.titleMedium?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              failed ? '${update.error}' : '${info.name} · $size MB',
              style: theme.bodyMedium?.copyWith(color: foreground),
            ),
            if (info.notes.isNotEmpty && !busy && !failed) ...[
              const SizedBox(height: 4),
              Text(
                info.notes,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.bodySmall?.copyWith(color: foreground),
              ),
            ],
            const SizedBox(height: 12),
            if (busy)
              LinearProgressIndicator(
                value: update.phase == EasyUpdatePhase.installing
                    ? null
                    : update.progress,
              )
            else
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: () => unawaited(
                    ref.read(easyUpdateProvider.notifier).downloadAndInstall(),
                  ),
                  child: Text(
                    failed
                        ? (fa ? 'تلاش دوباره' : 'Try again')
                        : (fa ? 'دانلود و نصب' : 'Download & install'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
