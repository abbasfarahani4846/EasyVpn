import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../core/providers/env.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/util/formatters.dart';
import '../../core/util/platform_service.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';

/// Which connection modes this platform can offer.
List<ConnMode> availableModes() {
  if (PlatformService.isDesktop) return ConnMode.values;
  return const [ConnMode.tun, ConnMode.proxyOnly];
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreControllerProvider);
    final settings = ref.watch(settingsProvider);
    final s = context.s;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('app.name')),
        actions: [
          IconButton(
            tooltip: s.t('settings.logs'),
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/logs'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final left = _ConnectPanel(core: core);
          final right = const _StatsPanel();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  children: [
                    if (core.status == CoreStatus.unavailable)
                      _UnavailableBanner(core.detail),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 16),
                          Expanded(child: right),
                        ],
                      )
                    else ...[
                      left,
                      const SizedBox(height: 16),
                      right,
                    ],
                    if (core.isConnected) ...[
                      const SizedBox(height: 16),
                      const _ExitIpCard(),
                    ],
                    const SizedBox(height: 16),
                    _ModeCard(current: settings.mode, core: core),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UnavailableBanner extends StatelessWidget {
  const _UnavailableBanner(this.reason);
  final String reason;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: cs.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.s.t('core.unavailable'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onErrorContainer,
                    ),
                  ),
                  Text(
                    context.s.t('core.unavailable.body'),
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                  if (reason.isNotEmpty)
                    Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onErrorContainer.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectPanel extends ConsumerWidget {
  const _ConnectPanel({required this.core});
  final CoreState core;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final settings = ref.watch(settingsProvider);
    final cs = Theme.of(context).colorScheme;
    final label = switch (core.status) {
      CoreStatus.connected => s.t('status.connected'),
      CoreStatus.connecting => s.t('status.connecting'),
      CoreStatus.disconnecting => s.t('status.disconnecting'),
      CoreStatus.error => s.t('status.error'),
      CoreStatus.unavailable => s.t('core.unavailable'),
      CoreStatus.disconnected => s.t('status.disconnected'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            _ConnectButton(
              core: core,
              canConnect: settings.activeNodeId != null,
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (core.status == CoreStatus.connected) const _Duration(),
            if (core.status == CoreStatus.disconnected &&
                settings.activeNodeId == null)
              TextButton(
                onPressed: () =>
                    ref.read(navProvider.notifier).go(Dest.profiles),
                child: Text(s.t('dash.no_node')),
              )
            else if (core.status == CoreStatus.disconnected)
              Text(
                s.t('dash.tap_connect'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            if (core.status == CoreStatus.error) _ErrorDetail(core.detail),
            const SizedBox(height: 20),
            const _ActiveNodeTile(),
          ],
        ),
      ),
    );
  }
}

class _ErrorDetail extends ConsumerWidget {
  const _ErrorDetail(this.detail);
  final String detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final failure = ref.read(coreControllerProvider.notifier).lastFailure;
    final text = detail == 'no_node'
        ? s.t('err.no_node')
        : (failure?.capability != null
              ? s.t('err.needs_core', {'cap': failure!.capability})
              : detail);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(s.t('diag.copy')),
            onPressed: () {
              final logs = ref.read(logProvider);
              final tail = logs.length > 200
                  ? logs.sublist(logs.length - 200)
                  : logs;
              final buf = StringBuffer('error: $text\n\n');
              for (final l in tail) {
                buf.writeln(
                  '${l.time.toIso8601String()} ${l.level} ${l.message}',
                );
              }
              Clipboard.setData(ClipboardData(text: buf.toString()));
            },
          ),
        ],
      ),
    );
  }
}

class _Duration extends ConsumerStatefulWidget {
  const _Duration();
  @override
  ConsumerState<_Duration> createState() => _DurationState();
}

class _DurationState extends ConsumerState<_Duration> {
  late final DateTime _start = DateTime.now();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    fmtDuration(DateTime.now().difference(_start)),
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class _ConnectButton extends ConsumerStatefulWidget {
  const _ConnectButton({required this.core, required this.canConnect});
  final CoreState core;
  final bool canConnect;

  @override
  ConsumerState<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends ConsumerState<_ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didUpdateWidget(covariant _ConnectButton old) {
    super.didUpdateWidget(old);
    if (widget.core.isBusy && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.core.isBusy && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    await ref.read(coreControllerProvider.notifier).toggle();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = widget.core.status;
    final color = switch (st) {
      CoreStatus.connected => const Color(0xFF22C55E),
      CoreStatus.connecting || CoreStatus.disconnecting => cs.tertiary,
      CoreStatus.error => cs.error,
      _ => cs.outline,
    };
    final enabled =
        st != CoreStatus.unavailable &&
        !widget.core.isBusy &&
        (widget.canConnect || widget.core.isConnected);
    return Semantics(
      button: true,
      label: 'connect',
      child: GestureDetector(
        onTap: enabled ? _onTap : null,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final glow = st == CoreStatus.connected
                ? 24.0
                : (widget.core.isBusy
                      ? 10 + 14 * math.sin(_pulse.value * math.pi)
                      : 0.0);
            return Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: enabled ? 0.14 : 0.06),
                border: Border.all(
                  color: color.withValues(alpha: enabled ? 1 : 0.4),
                  width: 5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: glow,
                    spreadRadius: glow / 4,
                  ),
                ],
              ),
              child: widget.core.isBusy
                  ? Padding(
                      padding: const EdgeInsets.all(56),
                      child: CircularProgressIndicator(
                        strokeWidth: 5,
                        color: color,
                      ),
                    )
                  : Icon(
                      Icons.power_settings_new_rounded,
                      size: 76,
                      color: color.withValues(alpha: enabled ? 1 : 0.4),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _ActiveNodeTile extends ConsumerWidget {
  const _ActiveNodeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(settingsProvider.select((s) => s.activeNodeId));
    final connected = ref.watch(
      coreControllerProvider.select((s) => s.isConnected),
    );
    final s = context.s;
    if (id == null) return const SizedBox.shrink();
    return FutureBuilder<NodeRow?>(
      future: ref.read(envProvider).repo.nodeRow(id),
      builder: (context, snap) {
        final n = snap.data;
        if (n == null) return const SizedBox.shrink();
        final exit = connected ? ref.watch(exitInfoProvider).value : null;
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => ref.read(navProvider.notifier).go(Dest.proxies),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ProtocolChip(protocolLabel(n.protocol)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          exit != null
                              ? '${flagEmoji(exit.countryCode)} ${exit.ip} · ${exit.city}'
                              : '${n.server}:${n.port}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        s.t('dash.active_node'),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      LatencyBadge(n.latency),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatsPanel extends ConsumerWidget {
  const _StatsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trafficProvider);
    final showChart = ref.watch(
      settingsProvider.select((s) => s.appearance.showSpeedChart),
    );
    final s = context.s;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.south_rounded,
                    color: const Color(0xFF22C55E),
                    label: s.t('dash.download'),
                    value: fmtSpeed(t.current.downBps),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.north_rounded,
                    color: cs.primary,
                    label: s.t('dash.upload'),
                    value: fmtSpeed(t.current.upBps),
                  ),
                ),
              ],
            ),
            if (showChart) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ChartPainter(
                    t.history,
                    cs.primary,
                    const Color(0xFF22C55E),
                    cs.outlineVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Small(
                    label: s.t('dash.session_total'),
                    value:
                        '${fmtBytes(t.current.totalDown)} ↓  ${fmtBytes(t.current.totalUp)} ↑',
                  ),
                ),
                Expanded(
                  child: _Small(
                    label: s.t('dash.connections'),
                    value: '${t.current.connections}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ],
  );
}

class _Small extends StatelessWidget {
  const _Small({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}

/// Two-series line chart (down/up) for the last 60 samples.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.history, this.upColor, this.downColor, this.grid);
  final List<TrafficStats> history;
  final Color upColor;
  final Color downColor;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (history.length < 2) return;
    var maxV = 1.0;
    for (final h in history) {
      maxV = math.max(maxV, math.max(h.downBps, h.upBps).toDouble());
    }
    Path line(double Function(TrafficStats) f) {
      final p = Path();
      for (var i = 0; i < history.length; i++) {
        final x = size.width * i / 59;
        final y = size.height - (f(history[i]) / maxV) * (size.height - 6) - 3;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    void draw(Path p, Color c) {
      final fill = Path.from(p)
        ..lineTo(size.width * (history.length - 1) / 59, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(fill, Paint()..color = c.withValues(alpha: 0.12));
      canvas.drawPath(
        p,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    draw(line((h) => h.downBps.toDouble()), downColor);
    draw(line((h) => h.upBps.toDouble()), upColor);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.history != history;
}

/// Segmented TUN | Proxy | Both selector with an explanation of the chosen mode.
class _ModeCard extends ConsumerWidget {
  const _ModeCard({required this.current, required this.core});
  final ConnMode current;
  final CoreState core;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final modes = availableModes();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('dash.mode'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ConnMode>(
                showSelectedIcon: false,
                segments: [
                  for (final m in modes)
                    ButtonSegment(value: m, label: Text(s.t('mode.${m.wire}'))),
                ],
                selected: {modes.contains(current) ? current : modes.first},
                onSelectionChanged:
                    core.isBusy || core.status == CoreStatus.unavailable
                    ? null
                    : (v) => ref
                          .read(coreControllerProvider.notifier)
                          .setMode(v.first),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.t('mode.${current.wire}.desc'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!PlatformService.isDesktop &&
                (current == ConnMode.systemProxy || current == ConnMode.both))
              Text(
                s.t('mode.unsupported'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

/// Real exit address (as seen from the internet) with a manual refresh.
class _ExitIpCard extends ConsumerWidget {
  const _ExitIpCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final cs = Theme.of(context).colorScheme;
    final v = ref.watch(exitInfoProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              v.value == null ? '🌐' : flagEmoji(v.value!.countryCode),
              style: const TextStyle(fontSize: 34),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: v.when(
                loading: () => Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Flexible(child: Text(s.t('dash.exit_checking'))),
                  ],
                ),
                error: (e, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('dash.exit_ip'),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      s.t('dash.exit_failed'),
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$e',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
                data: (i) => i == null
                    ? Text(s.t('dash.exit_failed'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('dash.exit_ip'),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          SelectableText(
                            i.ip,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            [
                              i.country.isNotEmpty ? i.country : i.countryCode,
                              i.city,
                              i.isp,
                            ].where((e) => e.isNotEmpty).join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            IconButton(
              tooltip: s.t('dash.exit_refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: v.isLoading
                  ? null
                  : ref.read(exitInfoProvider.notifier).refresh,
            ),
          ],
        ),
      ),
    );
  }
}
