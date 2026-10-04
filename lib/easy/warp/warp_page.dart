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
import 'warp_registration.dart';

class WarpView extends ConsumerStatefulWidget {
  const WarpView({super.key});

  @override
  ConsumerState<WarpView> createState() => _WarpViewState();
}

class _WarpViewState extends ConsumerState<WarpView> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    try {
      final proxy = await WarpRegistration.register(name: 'WARP');
      final result = await SingleConfigService.addParsed(
        ref,
        ShareLinkParseResult([proxy], const []),
        label: 'WARP',
        select: true,
      );
      if (!mounted) return;
      dialogs.showNotifier(
        result.added > 0
            ? (fa
                  ? 'پروفایل WARP ساخته شد؛ فقط دکمه‌ی اتصال را بزنید'
                  : 'WARP profile created; just press connect')
            : (fa ? 'WARP از قبل وجود دارد' : 'WARP already exists'),
        level: MessageLevel.success,
      );
      globalState.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      ref.read(currentPageLabelProvider.notifier).toProfiles();
    } catch (e) {
      dialogs.showNotifier(compactError(e), level: MessageLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return CommonScaffold(
      title: 'Cloudflare WARP',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
        children: [
          Text(
            fa
                ? 'یک حساب رایگان و ناشناس WARP ساخته و در یک پروفایل جدا '
                      'به نام «WARP» ذخیره و انتخاب می‌شود. بعد از آن فقط '
                      'دکمه‌ی اتصال را بزنید. ساخت حساب به دسترسی به سرور '
                      'Cloudflare نیاز دارد؛ اگر باز نمی‌شود، با یک فیلترشکن '
                      'امتحان کنید.'
                : 'Creates a free anonymous WARP account and saves it in its '
                      'own "WARP" profile, selected for you. Then just press '
                      'connect. Creating the account needs access to '
                      'Cloudflare; if it is blocked, try with a VPN on.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_add()),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(fa ? 'افزودن WARP' : 'Add WARP'),
            ),
          ),
        ],
      ),
    );
  }
}
