import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../core/providers/env.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/update/update_service.dart';
import '../../core/util/formatters.dart';
import '../../core/util/platform_service.dart';
import '../../l10n/strings.dart';
import '../../theme/brand.dart';
import 'home_menu.dart';
import 'location_picker.dart';

/// The default, one-button experience: a state-colored night sky, a large
/// animated power orb, the current location and a few quick actions. All
/// advanced features are one tap away in the menu.
class SimpleHome extends ConsumerWidget {
  const SimpleHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreControllerProvider);
    final color = Brand.forStatus(core.status);
    return Theme(
      data: Brand.theme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: Brand.night,
        body: Stack(
          children: [
            // State-driven glow behind the orb.
            AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.05,
                  colors: [
                    color.withValues(alpha: 0.30),
                    Brand.night2.withValues(alpha: 0.9),
                    Brand.night,
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      children: [
                        _TopBar(core: core),
                        const _UpdateBanner(),
                        const Spacer(flex: 2),
                        _Orb(core: core),
                        const SizedBox(height: 22),
                        _StatusText(core: core),
                        const Spacer(flex: 3),
                        const _BottomPanel(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.core});
  final CoreState core;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final on = core.isConnected;
    final c = Brand.forStatus(core.status);
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            on ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 14,
            color: c,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              on ? s.t('home.protected') : s.t('home.unprotected'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: Brand.orbGradient(
              on ? CoreStatus.connected : CoreStatus.disconnected,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.shield_rounded, size: 20, color: Brand.text),
        ),
        const SizedBox(width: 10),
        const Text(
          'EasyVPN',
          maxLines: 1,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: pill),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: s.t('home.menu'),
          icon: const Icon(Icons.grid_view_rounded),
          onPressed: () => showHomeMenu(context),
        ),
      ],
    );
  }
}

/// Large animated power button. Rings rotate while connecting and breathe
/// while connected.
class _Orb extends ConsumerStatefulWidget {
  const _Orb({required this.core});
  final CoreState core;
  @override
  ConsumerState<_Orb> createState() => _OrbState();
}

class _OrbState extends ConsumerState<_Orb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.core.status;
    final canTap = st != CoreStatus.unavailable;
    return Semantics(
      button: true,
      label: widget.core.isConnected ? 'Disconnect' : 'Connect',
      child: GestureDetector(
        onTap: canTap
            ? () => ref.read(coreControllerProvider.notifier).toggle()
            : null,
        child: SizedBox(
          width: 230,
          height: 230,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _OrbPainter(st, _c.value),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: Brand.orbGradient(st),
                    boxShadow: [
                      BoxShadow(
                        color: Brand.forStatus(st).withValues(alpha: 0.55),
                        blurRadius: widget.core.isConnected ? 48 : 18,
                        spreadRadius: widget.core.isConnected ? 4 : 0,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.power_settings_new_rounded,
                    size: 58,
                    color: Brand.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.status, this.t);
  final CoreStatus status;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final color = Brand.forStatus(status);
    final busy =
        status == CoreStatus.connecting || status == CoreStatus.disconnecting;
    final on = status == CoreStatus.connected;
    for (var i = 0; i < 3; i++) {
      final base = 76.0 + i * 17;
      final r = on ? base + math.sin((t + i / 3) * 2 * math.pi) * 3 : base;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.35 - i * 0.09);
      canvas.drawCircle(c, r, paint);
    }
    if (busy) {
      final rect = Rect.fromCircle(center: c, radius: 93);
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..shader = SweepGradient(
          colors: [color.withValues(alpha: 0), color],
          transform: GradientRotation(t * 2 * math.pi),
        ).createShader(rect);
      canvas.drawArc(rect, t * 2 * math.pi, math.pi * 1.2, false, sweep);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter o) => o.t != t || o.status != status;
}

class _StatusText extends ConsumerStatefulWidget {
  const _StatusText({required this.core});
  final CoreState core;
  @override
  ConsumerState<_StatusText> createState() => _StatusTextState();
}

class _StatusTextState extends ConsumerState<_StatusText> {
  DateTime? _since;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _since != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final core = widget.core;
    if (core.isConnected) {
      _since ??= DateTime.now();
    } else {
      _since = null;
    }
    final title = switch (core.status) {
      CoreStatus.connected => s.t('status.connected'),
      CoreStatus.connecting => s.t('home.connecting'),
      CoreStatus.disconnecting => s.t('home.disconnecting'),
      CoreStatus.error => s.t('status.error'),
      CoreStatus.unavailable => s.t('status.unavailable'),
      _ => s.t('status.disconnected'),
    };
    final exit = core.isConnected ? ref.watch(exitInfoProvider) : null;
    final ip = exit?.value;
    String sub;
    if (core.isConnected) {
      final d = fmtDuration(DateTime.now().difference(_since!));
      sub = ip == null ? d : '$d  ·  ${flagEmoji(ip.countryCode)} ${ip.ip}';
    } else if (core.status == CoreStatus.error) {
      sub = core.detail == 'no_node' ? s.t('err.no_node') : s.t(core.detail);
    } else {
      sub = s.t('home.tap');
    }
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: core.status == CoreStatus.error ? Brand.bad : Brand.textDim,
            fontSize: 14,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _BottomPanel extends ConsumerWidget {
  const _BottomPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final settings = ref.watch(settingsProvider);
    final core = ref.watch(coreControllerProvider);
    final traffic = ref.watch(trafficProvider).current;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: Brand.glass(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LocationTile(nodeId: settings.activeNodeId),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Chip(
                  icon: Icons.bolt_rounded,
                  label: s.t('home.fastest'),
                  onTap: () => ref
                      .read(coreControllerProvider.notifier)
                      .connectFastest(),
                ),
                const SizedBox(width: 8),
                _Chip(
                  icon: Icons.link_rounded,
                  label: _chainLabel(s, settings),
                  active:
                      settings.chainNodeIds.isNotEmpty ||
                      settings.exitNodeId.isNotEmpty,
                  onTap: () => openMenuPage(context, MenuTarget.chain),
                ),
                const SizedBox(width: 8),
                _ModeChip(mode: settings.mode),
              ],
            ),
          ),
          if (core.isConnected) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.south_rounded, size: 16, color: Brand.on),
                const SizedBox(width: 4),
                Text(fmtSpeed(traffic.downBps)),
                const Spacer(),
                const Icon(Icons.north_rounded, size: 16, color: Brand.on2),
                const SizedBox(width: 4),
                Text(fmtSpeed(traffic.upBps)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _chainLabel(S s, AppSettings st) {
    if (st.exitNodeId.isNotEmpty) return s.t('home.chain.warp');
    if (st.chainNodeIds.isNotEmpty) {
      return s.t('home.chain.custom', {'n': st.chainNodeIds.length});
    }
    return '${s.t('home.chain')}: ${s.t('home.chain.off')}';
  }
}

class _LocationTile extends ConsumerWidget {
  const _LocationTile({required this.nodeId});
  final String? nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return FutureBuilder<NodeRow?>(
      future: nodeId == null
          ? Future.value(null)
          : ref.read(envProvider).repo.nodeRow(nodeId!),
      builder: (context, snap) {
        final row = snap.data;
        final flag = row == null ? null : leadingFlag(row.name);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showLocationPicker(context),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Brand.panel,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: flag != null
                        ? Text(flag, style: const TextStyle(fontSize: 26))
                        : const Icon(Icons.public_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t('home.location'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Brand.textDim,
                          ),
                        ),
                        Text(
                          row == null
                              ? s.t('home.choose')
                              : cleanName(row.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (row != null)
                          Text(
                            row.protocol.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Brand.textDim,
                              letterSpacing: 0.8,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (row != null) SignalBars(row.latency),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: Brand.textDim),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Brand.on.withValues(alpha: 0.18) : Brand.panel,
      shape: StadiumBorder(
        side: BorderSide(color: active ? Brand.on : Brand.panelBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? Brand.on : Brand.text),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends ConsumerWidget {
  const _ModeChip({required this.mode});
  final ConnMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final modes = [
      ConnMode.tun,
      if (PlatformService.isDesktop) ConnMode.systemProxy,
      ConnMode.proxyOnly,
    ];
    return PopupMenuButton<ConnMode>(
      initialValue: mode,
      onSelected: (m) => ref.read(coreControllerProvider.notifier).setMode(m),
      itemBuilder: (_) => [
        for (final m in modes)
          PopupMenuItem(value: m, child: Text(s.t('mode.${m.wire}'))),
      ],
      child: IgnorePointer(
        child: _Chip(
          icon: mode.usesTun ? Icons.vpn_lock_rounded : Icons.lan_rounded,
          label: s.t('mode.${mode.wire}'),
          onTap: () {},
        ),
      ),
    );
  }
}

/// Shows "update ready" inline without blocking anything.
class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(updateProvider);
    if (!u.hasUpdate) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Brand.on2.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openMenuPage(context, MenuTarget.updates),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: Brand.on2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.s.t('upd.banner', {'v': u.latest})),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
