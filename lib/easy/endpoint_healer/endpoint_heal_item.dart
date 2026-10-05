import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'endpoint_healer.dart';
import 'profile_heal.dart';

class EasyEndpointHealItem extends ConsumerWidget {
  const EasyEndpointHealItem({super.key});

  Future<void> _run(WidgetRef ref, bool fa) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      dialogs.showNotifier(
        fa ? 'اول یک پروفایل انتخاب کنید' : 'Select a profile first',
        level: MessageLevel.warning,
      );
      return;
    }
    final report = await globalState.loadingRun(
      () async {
        final file = await profile.file;
        final text = await file.readAsString();
        final report = await EndpointHealer.heal(text);
        if (report.changed) {
          final saved = await profile.saveFile(
            Uint8List.fromList(utf8.encode(report.yaml)),
            validate: (path) =>
                ref.read(coreHandlerProvider).validateConfig(path),
          );
          ref
              .read(profilesActionProvider.notifier)
              .setProfileAndAutoApply(saved);
        }
        return report;
      },
      tag: LoadingTag.profiles,
      title: fa ? 'بررسی پورت سرورها' : 'Checking server ports',
    );
    if (report == null) return;
    dialogs.showNotifier(
      report.repaired.isEmpty && report.failed.isEmpty
          ? (fa
                ? 'همه‌ی سرورها روی پورتشان جواب می‌دهند'
                : 'Every server answers on its port')
          : repairMessage(report),
      level: report.failed.isEmpty ? MessageLevel.success : MessageLevel.error,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return ListItem(
      leading: const Icon(Icons.build_circle_outlined),
      title: Text(fa ? 'تعمیر پورت سرورها' : 'Repair server ports'),
      subtitle: Text(
        fa
            ? 'سروری که روی پورتش جواب نمی‌دهد با پورت جایگزین تست و اصلاح می‌شود'
            : 'A server that does not answer on its port is retested on the fallback port and fixed',
      ),
      onTap: () => _run(ref, fa),
    );
  }
}
