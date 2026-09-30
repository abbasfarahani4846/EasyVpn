import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/env.dart';
import '../../l10n/strings.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';

/// Share one node as a standard share link + QR code (copy / system share).
Future<void> showShareNode(
  BuildContext context,
  WidgetRef ref,
  String nodeId,
) async {
  final env = ref.read(envProvider);
  final raw = await env.repo.rawNode(nodeId);
  if (raw == null || !context.mounted) return;
  String link;
  try {
    link = (await env.core.export('uri', [raw])).trim();
  } catch (e) {
    if (context.mounted) showSnack(context, '$e', error: true);
    return;
  }
  if (!context.mounted) return;
  final name = (raw['name'] as String?) ?? '';
  await showModalBottomSheet(
    context: context,
    backgroundColor: Brand.night2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.radius)),
    ),
    builder: (ctx) => Theme(
      data: Brand.theme(Theme.of(ctx)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(12),
                child: link.length > 2500
                    ? SizedBox(
                        width: 220,
                        child: Text(ctx.s.t('share.too_long')),
                      )
                    : QrImageView(data: link, size: 220),
              ),
              const SizedBox(height: 12),
              Text(
                link,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Brand.textDim),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(ctx.s.t('common.copy')),
                      onPressed: () => copyText(ctx, link),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.share_rounded),
                      label: Text(ctx.s.t('share.share')),
                      onPressed: () => Share.share(link),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
