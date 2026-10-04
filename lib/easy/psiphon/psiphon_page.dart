import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../single_config/share_link_parser.dart';
import '../single_config/single_config_service.dart';
import 'psiphon_manager.dart';

const psiphonProfileLabel = 'Psiphon';

class PsiphonView extends ConsumerStatefulWidget {
  const PsiphonView({super.key});

  @override
  ConsumerState<PsiphonView> createState() => _PsiphonViewState();
}

class _PsiphonViewState extends ConsumerState<PsiphonView> {
  bool _adding = false;

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    try {
      final result = await SingleConfigService.addParsed(
        ref,
        const ShareLinkParseResult([
          {
            'name': 'Psiphon',
            'type': 'socks5',
            'server': '127.0.0.1',
            'port': 20830,
            'udp': false,
          },
        ], []),
        label: psiphonProfileLabel,
        select: true,
      );
      if (!mounted) return;
      dialogs.showNotifier(
        result.added > 0
            ? (fa
                  ? 'پروفایل Psiphon ساخته شد؛ فقط دکمه‌ی اتصال را بزنید'
                  : 'Psiphon profile created; just press connect')
            : (fa
                  ? 'پروفایل Psiphon انتخاب شد؛ دکمه‌ی اتصال را بزنید'
                  : 'Psiphon profile selected; press connect'),
        level: MessageLevel.success,
      );
      globalState.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      ref.read(currentPageLabelProvider.notifier).toProfiles();
    } catch (e) {
      dialogs.showNotifier(compactError(e), level: MessageLevel.error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  String? _statusText(bool fa, PsiphonStatus s) {
    switch (s.stage) {
      case PsiphonStage.idle:
        return null;
      case PsiphonStage.starting:
      case PsiphonStage.dialling:
        return fa ? 'Psiphon در حال اتصال…' : 'Psiphon is connecting…';
      case PsiphonStage.connected:
        return fa ? 'Psiphon وصل است' : 'Psiphon is connected';
      case PsiphonStage.failed:
        if (s.error == 'binary-missing') {
          return fa
              ? 'فایل Psiphon پیدا نشد (easy_bin/psiphon)'
              : 'Psiphon binary not found (easy_bin/psiphon)';
        }
        return s.error ?? (fa ? 'خطا' : 'Failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return CommonScaffold(
      title: 'Psiphon',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
        children: [
          Text(
            fa
                ? 'یک پروفایل جدا به نام «Psiphon» ساخته و انتخاب می‌شود. '
                      'فقط دکمه‌ی اتصال را بزنید؛ Psiphon خودش روشن می‌شود، '
                      'لیست سرورها را می‌گیرد و بهترین روش اتصال را برای '
                      'اینترنت شما پیدا می‌کند (ممکن است تا حدود یک دقیقه '
                      'طول بکشد).'
                : 'Creates and selects a separate "Psiphon" profile. Just '
                      'press connect; Psiphon starts by itself, fetches its '
                      'server list and finds the method that works on your '
                      'network (this can take up to a minute).',
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<PsiphonStatus>(
            valueListenable: PsiphonManager.instance.status,
            builder: (context, status, _) {
              final text = _statusText(fa, status);
              return text == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(text),
                    );
            },
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _adding ? null : () => unawaited(_add()),
              icon: _adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(fa ? 'افزودن پروفایل Psiphon' : 'Add Psiphon profile'),
            ),
          ),
        ],
      ),
    );
  }
}
