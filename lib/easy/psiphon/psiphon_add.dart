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
import 'psiphon_nodes.dart';

/// One tap in Add profile: creates the Psiphon profile (Auto plus a server
/// per country), selects it and connects. The Psiphon core itself starts in
/// the background as part of connecting.
class EasyPsiphonAddItem extends ConsumerStatefulWidget {
  const EasyPsiphonAddItem({super.key});

  @override
  ConsumerState<EasyPsiphonAddItem> createState() => _EasyPsiphonAddItemState();
}

class _EasyPsiphonAddItemState extends ConsumerState<EasyPsiphonAddItem> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    try {
      await PsiphonManager.instance.setRegion(null);
      ref
          .read(patchClashConfigProvider.notifier)
          .update((s) => s.copyWith(findProcessMode: FindProcessMode.always));
      await SingleConfigService.addParsed(
        ref,
        ShareLinkParseResult(PsiphonNodes.build(), const []),
        label: PsiphonNodes.profileLabel,
        select: true,
        replace: true,
        urlTest: false,
      );
      globalState.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      ref.read(currentPageLabelProvider.notifier).toProfiles();
      dialogs.showNotifier(
        fa
            ? 'Psiphon اضافه شد و در حال اتصال است…'
            : 'Psiphon added, connecting…',
        level: MessageLevel.success,
      );
      unawaited(ref.read(setupActionProvider.notifier).setRunning(true));
    } catch (e) {
      dialogs.showNotifier(compactError(e), level: MessageLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return ListItem(
      leading: _busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.travel_explore),
      title: const Text('Psiphon'),
      subtitle: Text(
        fa
            ? 'افزودن و اتصال فوری؛ سرورها در بخش پروکسی‌ها'
            : 'Add and connect right away; servers appear in Proxies',
      ),
      onTap: _busy ? null : () => unawaited(_add()),
    );
  }
}
