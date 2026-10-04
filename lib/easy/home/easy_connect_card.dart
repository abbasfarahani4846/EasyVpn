import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../psiphon/psiphon_manager.dart';
import '../psiphon/psiphon_nodes.dart';
import 'connection_verifier.dart';
import 'selected_server.dart';

enum _Phase { idle, connecting, verified, problem, timedOut }

/// A dashboard widget (movable, removable in the dashboard's edit mode): one
/// big connect button that says "Connected" only after the connection has been
/// checked end to end, with what is happening underneath.
class EasyConnectCard extends ConsumerStatefulWidget {
  const EasyConnectCard({super.key});

  @override
  ConsumerState<EasyConnectCard> createState() => _EasyConnectCardState();
}

class _EasyConnectCardState extends ConsumerState<EasyConnectCard> {
  static const _checkEvery = Duration(seconds: 2);
  static const _recheckEvery = Duration(seconds: 30);

  _Phase _phase = _Phase.idle;
  LinkState? _link;
  String? _baseline;
  String? _coreIp;
  String? _systemIp;
  DateTime _deadline = DateTime.now();
  Timer? _timer;
  bool _checking = false;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _t(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(isStartProvider, (_, running) {
      if (running) {
        _begin();
      } else {
        _reset();
      }
    });
    if (ref.read(isStartProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
    } else {
      unawaited(_fetchBaseline());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isPsiphonProfile =>
      ref.read(currentProfileProvider)?.label == PsiphonNodes.profileLabel;

  Future<void> _fetchBaseline() async {
    final ip = await ConnectionVerifier.fetchIp();
    if (mounted && !ref.read(isStartProvider)) setState(() => _baseline = ip);
  }

  void _begin() {
    _timer?.cancel();
    _deadline = DateTime.now().add(
      Duration(seconds: _isPsiphonProfile ? 30 : 12),
    );
    setState(() {
      _phase = _Phase.connecting;
      _link = null;
      _coreIp = null;
      _systemIp = null;
    });
    _timer = Timer.periodic(_checkEvery, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.idle;
      _link = null;
      _coreIp = null;
      _systemIp = null;
    });
    Timer(const Duration(seconds: 3), () {
      if (mounted && !ref.read(isStartProvider)) unawaited(_fetchBaseline());
    });
  }

  Future<void> _tick() async {
    if (_checking || !ref.read(isStartProvider)) return;
    _checking = true;
    try {
      final port = ref.read(patchClashConfigProvider).mixedPort;
      final tunOn = ref.read(patchClashConfigProvider).tun.enable;
      final results = await Future.wait([
        ConnectionVerifier.fetchIp(proxy: '127.0.0.1:$port'),
        if (tunOn) ConnectionVerifier.fetchIp() else Future.value(null),
      ]);
      if (!mounted || !ref.read(isStartProvider)) return;
      final coreIp = results[0];
      final systemIp = results.length > 1 ? results[1] : null;
      final link = ConnectionVerifier.evaluate(
        coreIp: coreIp,
        systemIp: systemIp,
        baselineIp: _baseline,
        tunOn: tunOn,
      );
      setState(() {
        _coreIp = coreIp;
        _systemIp = systemIp;
        _link = link;
        if (link == LinkState.verified) {
          _phase = _Phase.verified;
        } else if (DateTime.now().isAfter(_deadline)) {
          _phase = link == LinkState.mismatch || link == LinkState.unchanged
              ? _Phase.problem
              : _Phase.timedOut;
        }
      });
      if (link == LinkState.verified) {
        _timer?.cancel();
        _timer = Timer.periodic(_recheckEvery, (_) => unawaited(_tick()));
      }
    } finally {
      _checking = false;
    }
  }

  void _keepWaiting() {
    _deadline = DateTime.now().add(const Duration(seconds: 30));
    setState(() => _phase = _Phase.connecting);
    _timer?.cancel();
    _timer = Timer.periodic(_checkEvery, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  Future<void> _toggle() async {
    if (ref.read(profilesProvider).isEmpty) {
      ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
      return;
    }
    final running = ref.read(isStartProvider);
    if (!running) {
      // The country follows the server actually selected, never a stale one.
      final selected = ref.read(visibleGroupsStateProvider).value;
      await PsiphonManager.noteSelection(
        _selectedName(selected) ?? PsiphonNodes.autoName,
      );
    }
    if (!running && _isPsiphonProfile) {
      // The bypass rule for the Psiphon process needs process matching.
      ref
          .read(patchClashConfigProvider.notifier)
          .update((s) => s.copyWith(findProcessMode: FindProcessMode.always));
    }
    await ref.read(setupActionProvider.notifier).setRunning(!running);
  }

  String? _selectedName(List<Group> groups) {
    if (groups.isEmpty) return null;
    return ref.read(selectedProxyNameProvider(groups.first.name));
  }

  void _goto(PageLabel page) =>
      ref.read(currentPageLabelProvider.notifier).value = page;

  String _methodName(String? rung) => switch (rung) {
    'A' => 'CDN',
    'D' => _t('مستقیم', 'direct'),
    'C' => _t('رله', 'relay'),
    _ => '',
  };

  String _psiphonLine(PsiphonStatus s) {
    switch (s.stage) {
      case PsiphonStage.idle:
        return _t('Psiphon خاموش است', 'Psiphon is off');
      case PsiphonStage.starting:
        return _t('Psiphon در حال استارت…', 'Starting Psiphon…');
      case PsiphonStage.dialling:
        final method = _methodName(s.rung);
        final tries = s.pass > 0
            ? _t(' · تلاش ${s.pass + 1}', ' · attempt ${s.pass + 1}')
            : '';
        final why = switch (s.hint) {
          'refused' => _t(
            ' · پورت سرور واسط جواب نمی‌دهد',
            ' · the entry server port refuses connections',
          ),
          'timeout' => _t(
            ' · سرورها جواب نمی‌دهند',
            ' · servers are not answering',
          ),
          'blocked' => _t(
            ' · شبکه اتصال‌ها را می‌بندد',
            ' · the network closes the connections',
          ),
          _ => '',
        };
        return _t(
          'Psiphon در حال اتصال (روش $method$tries)…$why',
          'Psiphon connecting (method $method$tries)…$why',
        );
      case PsiphonStage.connected:
        return _t(
          'Psiphon وصل شد (${_methodName(s.rung)})',
          'Psiphon connected (${_methodName(s.rung)})',
        );
      case PsiphonStage.failed:
        return s.error == 'binary-missing'
            ? _t('فایل Psiphon پیدا نشد', 'Psiphon binary not found')
            : _t('Psiphon خطا داد', 'Psiphon failed');
    }
  }

  String _title() => switch (_phase) {
    _Phase.idle => _t('متصل نیستید', 'Not connected'),
    _Phase.connecting => _t('در حال اتصال…', 'Connecting…'),
    _Phase.verified => _t('متصل شد', 'Connected'),
    _Phase.problem => _t('اتصال کامل نیست', 'Connection is not complete'),
    _Phase.timedOut => _t('هنوز متصل نشد', 'Not connected yet'),
  };

  String _detail() {
    switch (_phase) {
      case _Phase.idle:
        return _baseline == null
            ? ''
            : _t('IP شما: $_baseline', 'Your IP: $_baseline');
      case _Phase.connecting:
        return _t('در حال بررسی اتصال…', 'Checking the connection…');
      case _Phase.verified:
        return _t('IP شما: $_coreIp', 'Your IP: $_coreIp');
      case _Phase.problem:
        return _link == LinkState.unchanged
            ? _t(
                'IP تغییر نکرده است؛ ترافیک از پروکسی رد نمی‌شود.',
                'The IP did not change, so traffic is not using the proxy.',
              )
            : _t(
                'پروکسی کار می‌کند ($_coreIp) ولی ترافیک سیستم از آن رد '
                    'نمی‌شود ($_systemIp). TUN یا پروکسی سیستم را روشن کنید.',
                'The proxy works ($_coreIp) but system traffic is not using '
                    'it ($_systemIp). Turn on TUN or the system proxy.',
              );
      case _Phase.timedOut:
        return _t(
          'جوابی نگرفتیم. ادامه بدهیم یا قطع کنیم؟',
          'No answer yet. Keep waiting or disconnect?',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final running = ref.watch(isStartProvider);
    final profile = ref.watch(currentProfileProvider);
    final server = easySelectedServer(ref);
    final isPsiphon = profile?.label == PsiphonNodes.profileLabel;

    final (Color bg, Color fg, IconData icon) = switch (_phase) {
      _Phase.idle => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        Icons.power_settings_new,
      ),
      _Phase.connecting => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.power_settings_new,
      ),
      _Phase.verified => (
        scheme.primary,
        scheme.onPrimary,
        Icons.check_rounded,
      ),
      _Phase.problem => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.warning_amber_rounded,
      ),
      _Phase.timedOut => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.priority_high_rounded,
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_phase == _Phase.connecting)
                    SizedBox(
                      width: 132,
                      height: 132,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: scheme.primary,
                      ),
                    ),
                  Material(
                    color: bg,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _toggle,
                      child: SizedBox(
                        width: 112,
                        height: 112,
                        child: Icon(icon, size: 52, color: fg),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(_title(), textAlign: TextAlign.center, style: text.titleLarge),
            const SizedBox(height: 2),
            Text(
              _detail(),
              textAlign: TextAlign.center,
              style: text.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isPsiphon && running)
              ValueListenableBuilder<PsiphonStatus>(
                valueListenable: PsiphonManager.instance.status,
                builder: (context, status, _) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _psiphonLine(status),
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: scheme.primary),
                  ),
                ),
              ),
            if (_phase == _Phase.timedOut || _phase == _Phase.problem)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_phase == _Phase.timedOut)
                      FilledButton.tonal(
                        onPressed: _keepWaiting,
                        child: Text(_t('ادامه بده', 'Keep waiting')),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _toggle,
                      child: Text(_t('قطع اتصال', 'Disconnect')),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.folder_outlined, size: 16),
                  label: Text(
                    profile?.realLabel ?? _t('پروفایلی نیست', 'No profile'),
                  ),
                  onPressed: () => _goto(PageLabel.profiles),
                ),
                if (server != null)
                  ActionChip(
                    avatar: const Icon(Icons.dns_outlined, size: 16),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: EmojiText(
                        server,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onPressed: () => _goto(PageLabel.proxies),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
