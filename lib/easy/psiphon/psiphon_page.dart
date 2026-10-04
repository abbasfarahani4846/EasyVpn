import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../single_config/share_link_parser.dart';
import '../single_config/single_config_service.dart';
import 'psiphon_ladder.dart';
import 'psiphon_manager.dart';

bool _isFa(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

class EasyPsiphonItem extends StatelessWidget {
  const EasyPsiphonItem({super.key});

  @override
  Widget build(BuildContext context) {
    final fa = _isFa(context);
    return ListItem.open(
      leading: const Icon(Icons.travel_explore),
      title: const Text('Psiphon'),
      subtitle: Text(
        fa
            ? 'اتصال رایگان با تلاش خودکار چند روش (CDN، مستقیم، رله)'
            : 'Free tunnel that tries several methods automatically',
      ),
      widget: const PsiphonView(),
    );
  }
}

class PsiphonView extends ConsumerStatefulWidget {
  const PsiphonView({super.key});

  @override
  ConsumerState<PsiphonView> createState() => _PsiphonViewState();
}

class _PsiphonViewState extends ConsumerState<PsiphonView> {
  final _manager = PsiphonManager.instance;
  bool _adding = false;

  Future<void> _addProxy() async {
    if (_adding) return;
    setState(() => _adding = true);
    final fa = _isFa(context);
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
      );
      dialogs.showNotifier(
        result.added > 0
            ? (fa ? 'نود Psiphon اضافه شد' : 'Psiphon node added')
            : (fa ? 'نود Psiphon از قبل وجود دارد' : 'Psiphon node already exists'),
        level: MessageLevel.success,
      );
    } catch (e) {
      dialogs.showNotifier(compactError(e), level: MessageLevel.error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  String _statusText(bool fa, PsiphonStatus s) {
    switch (s.stage) {
      case PsiphonStage.idle:
        return fa ? 'خاموش' : 'Stopped';
      case PsiphonStage.starting:
        return fa ? 'در حال شروع…' : 'Starting…';
      case PsiphonStage.dialling:
        final rung = PsiphonLadder.byName(s.rung);
        final label = rung == null
            ? ''
            : (fa ? rung.labelFa : rung.labelEn);
        return fa
            ? 'در حال اتصال — روش ${s.rungIndex + 1} از ${s.rungCount}: $label'
            : 'Connecting — method ${s.rungIndex + 1} of ${s.rungCount}: $label';
      case PsiphonStage.connected:
        final rung = PsiphonLadder.byName(s.rung);
        final label = rung == null
            ? ''
            : (fa ? rung.labelFa : rung.labelEn);
        final proto = s.protocol == null ? '' : ' · ${s.protocol}';
        return fa
            ? 'وصل شد — $label$proto (پورت SOCKS ${PsiphonManager.socksPort})'
            : 'Connected — $label$proto (SOCKS port ${PsiphonManager.socksPort})';
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
    final fa = _isFa(context);
    return CommonScaffold(
      title: 'Psiphon',
      body: ValueListenableBuilder<PsiphonStatus>(
        valueListenable: _manager.status,
        builder: (context, status, _) {
          final running = _manager.isRunning;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              context.contentTopPadding,
              16,
              16,
            ),
            children: [
              Text(
                fa
                    ? 'لیست سرورها را خود Psiphon از شبکه‌ی خودش می‌گیرد. چون '
                          'در هر اینترنت یک روش جواب می‌دهد، برنامه همه‌ی روش‌ها '
                          'را به ترتیب امتحان می‌کند و روشی که جواب داد را '
                          'برای دفعه‌ی بعد اول امتحان می‌کند.'
                    : 'Psiphon downloads its own server list. Since a different '
                          'method works on each network, the app tries every '
                          'method in turn and tries the one that worked last '
                          'time first.',
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    status.stage == PsiphonStage.connected
                        ? Icons.check_circle
                        : Icons.travel_explore,
                  ),
                  title: Text(_statusText(fa, status)),
                  trailing: FilledButton(
                    onPressed: () =>
                        running ? _manager.stop() : _manager.start(),
                    child: Text(
                      running
                          ? (fa ? 'توقف' : 'Stop')
                          : (fa ? 'شروع' : 'Start'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                fa
                    ? 'برای استفاده در اپ، یک بار نود Psiphon را به پروفایل '
                          'Default اضافه کنید و هنگام استفاده، Psiphon را '
                          'روشن نگه دارید.'
                    : 'To use it in the app, add the Psiphon node to the '
                          'Default profile once and keep Psiphon running '
                          'while you use it.',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _adding ? null : _addProxy,
                  icon: const Icon(Icons.add),
                  label: Text(fa ? 'افزودن نود Psiphon' : 'Add Psiphon node'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
