import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

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
import '../share/share_sheet.dart';

/// The default, one-button experience: a state-colored night sky, a large
/// animated power orb, the current location and a few quick actions. All
/// advanced features are one tap away in the menu.
class SimpleHome extends ConsumerWidget {
  const SimpleHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (PlatformService.isDesktop &&
        ref.watch(settingsProvider.select((x) => x.miniWindow))) {
      return const _WindscribeCard();
    }
    final core = ref.watch(coreControllerProvider);
    final color = Brand.forStatus(core.status);
    return Theme(
      data: Brand.theme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        // Compact arrangement applies only on desktop mini windows,
                        // never on mobile/Android devices.
                        final compact = PlatformService.isDesktop && c.maxHeight < 560;
                        return Column(
                          children: [
                            _TopBar(core: core),
                            if (!compact) const _UpdateBanner(),
                            const Spacer(flex: 2),
                            _Orb(core: core, size: compact ? 140 : 210),
                            SizedBox(height: compact ? 10 : 22),
                            _StatusText(core: core, compact: compact),
                            if (core.isConnected) ...[
                              SizedBox(height: compact ? 8 : 16),
                              _IpCard(compact: compact),
                            ],
                            const Spacer(flex: 3),
                            _BottomPanel(compact: compact),
                          ],
                        );
                      },
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            size: 13,
            color: c,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              on ? s.t('home.protected') : s.t('home.unprotected'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: Brand.orbGradient(
              on ? CoreStatus.connected : CoreStatus.disconnected,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.shield_rounded, size: 17, color: Brand.text),
        ),
        const SizedBox(width: 8),
        const Text(
          'EasyVPN',
          maxLines: 1,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: pill,
          ),
        ),
        const SizedBox(width: 4),
        if (PlatformService.isDesktop) ...[
          const ViewSwitcherButton(),
          const SizedBox(width: 2),
        ],
        IconButton(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          tooltip: s.t('home.menu'),
          icon: const Icon(Icons.grid_view_rounded, size: 19),
          onPressed: () => showHomeMenu(context),
        ),
      ],
    );
  }
}

/// Large animated power button. Rings rotate while connecting and breathe
/// while connected.
class _Orb extends ConsumerStatefulWidget {
  const _Orb({required this.core, this.size = 230});
  final CoreState core;
  final double size;
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
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _OrbPainter(st, _c.value, widget.size / 230),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: widget.size * 0.574,
                  height: widget.size * 0.574,
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
                  child: Icon(
                    Icons.power_settings_new_rounded,
                    size: widget.size * 0.25,
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
  _OrbPainter(this.status, this.t, [this.scale = 1]);
  final CoreStatus status;
  final double t;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final color = Brand.forStatus(status);
    final busy =
        status == CoreStatus.connecting || status == CoreStatus.disconnecting;
    final on = status == CoreStatus.connected;
    for (var i = 0; i < 3; i++) {
      final base = (76.0 + i * 17) * scale;
      final r = on ? base + math.sin((t + i / 3) * 2 * math.pi) * 3 : base;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.35 - i * 0.09);
      canvas.drawCircle(c, r, paint);
    }
    if (busy) {
      final rect = Rect.fromCircle(center: c, radius: 93 * scale);
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
  bool shouldRepaint(_OrbPainter o) =>
      o.t != t || o.status != status || o.scale != scale;
}

class _StatusText extends ConsumerStatefulWidget {
  const _StatusText({required this.core, this.compact = false});
  final CoreState core;
  final bool compact;
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
    String sub;
    if (core.isConnected) {
      final d = fmtDuration(DateTime.now().difference(_since!));
      sub = d;
    } else if (core.status == CoreStatus.error) {
      sub = core.detail == 'no_node' ? s.t('err.no_node') : s.t(core.detail);
    } else if (core.status == CoreStatus.connecting) {
      // Pressing the orb again cancels (also while "Fastest" is testing or verifying).
      sub = core.detail.isNotEmpty
          ? '${s.t(core.detail)}  ·  ${s.t('home.cancel')}'
          : s.t('home.cancel');
    } else {
      sub = s.t('home.tap');
    }
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: widget.compact ? 22 : 30,
            fontWeight: FontWeight.w800,
          ),
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

/// The address the internet sees through the tunnel, with a refresh button so
/// the user can tell that the connection really carries traffic.
class _IpCard extends ConsumerWidget {
  const _IpCard({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final v = ref.watch(exitInfoProvider);
    final info = v.value;
    final loading = v.isLoading;
    final failed = v.hasError && !loading;
    final where = info == null
        ? ''
        : [
            info.city,
            info.country,
            info.isp,
          ].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 6 : 10),
      decoration: Brand.glass(),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Brand.panel,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              info != null && info.countryCode.isNotEmpty
                  ? flagEmoji(info.countryCode)
                  : '🌐',
              style: const TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: info == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: info.ip));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(s.t('ip.copied'))));
                    },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    info != null
                        ? info.ip
                        : failed
                        ? s.t('ip.failed')
                        : s.t('ip.checking'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: info != null ? 18 : 13,
                      fontWeight: FontWeight.w700,
                      color: failed ? Brand.bad : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (where.isNotEmpty && !compact)
                    Text(
                      where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Brand.textDim,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: s.t('ip.refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: ref.read(exitInfoProvider.notifier).refresh,
                ),
        ],
      ),
    );
  }
}

class _BottomPanel extends ConsumerWidget {
  const _BottomPanel({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final settings = ref.watch(settingsProvider);
    final core = ref.watch(coreControllerProvider);
    final traffic = ref.watch(trafficProvider).current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: Brand.glass(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LocationTile(nodeId: settings.activeNodeId),
          if (!compact) const SizedBox(height: 10),
          if (!compact)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _Chip(
                  icon: Icons.bolt_rounded,
                  label: s.t('home.fastest'),
                  onTap: () => ref
                      .read(coreControllerProvider.notifier)
                      .connectFastest(),
                ),
                _Chip(
                  icon: Icons.travel_explore_rounded,
                  label: s.t('menu.sites'),
                  onTap: () => openMenuPage(context, MenuTarget.sites),
                ),
                _ModeChip(mode: settings.mode),
              ],
            ),
          if (core.isConnected && !compact) ...[
            const SizedBox(height: 10),
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
            onLongPress: nodeId == null
                ? null
                : () => showShareNode(context, ref, nodeId!),
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
                  if (row != null) SignalBars(row.latency, showLabel: true),
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
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.panel,
      shape: const StadiumBorder(
        side: BorderSide(color: Brand.panelBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Brand.text),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
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

/// Allows switching between Mini Card, Standard, and Advanced layout views.
class ViewSwitcherButton extends ConsumerWidget {
  const ViewSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final settings = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier);

    return PopupMenuButton<String>(
      tooltip: s.t('view.switcher'),
      icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Brand.night2,
      onSelected: (mode) {
        if (mode == 'mini') {
          set.update((x) => x.copyWith(uiMode: 'simple', miniWindow: true));
        } else if (mode == 'simple') {
          set.update((x) => x.copyWith(uiMode: 'simple', miniWindow: false));
        } else if (mode == 'advanced') {
          set.update((x) => x.copyWith(uiMode: 'advanced', miniWindow: false));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'mini',
          child: Row(
            children: [
              Icon(Icons.crop_16_9_rounded, size: 18, color: settings.miniWindow ? Brand.on : Brand.textDim),
              const SizedBox(width: 8),
              Text(s.t('view.mini'), style: TextStyle(fontWeight: settings.miniWindow ? FontWeight.w700 : null)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'simple',
          child: Row(
            children: [
              Icon(Icons.smartphone_rounded, size: 18, color: (!settings.miniWindow && settings.uiMode == 'simple') ? Brand.on : Brand.textDim),
              const SizedBox(width: 8),
              Text(s.t('view.simple'), style: TextStyle(fontWeight: (!settings.miniWindow && settings.uiMode == 'simple') ? FontWeight.w700 : null)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'advanced',
          child: Row(
            children: [
              Icon(Icons.desktop_windows_rounded, size: 18, color: settings.uiMode == 'advanced' ? Brand.on : Brand.textDim),
              const SizedBox(width: 8),
              Text(s.t('view.advanced'), style: TextStyle(fontWeight: settings.uiMode == 'advanced' ? FontWeight.w700 : null)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Windscribe-style horizontal mini card layout (370x270 fixed).
class _WindscribeCard extends ConsumerWidget {
  const _WindscribeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final core = ref.watch(coreControllerProvider);
    final settings = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier);
    final color = Brand.forStatus(core.status);
    final exitInfo = ref.watch(exitInfoProvider).value;

    return Theme(
      data: Brand.theme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.6, -0.2),
              radius: 1.15,
              colors: [
                color.withValues(alpha: 0.28),
                Brand.night2.withValues(alpha: 0.96),
                Brand.night,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar
              Row(
                children: [
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.menu_rounded, size: 20),
                    onPressed: () => showHomeMenu(context),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'EasyVPN',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  const ViewSwitcherButton(),
                  const SizedBox(width: 2),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    tooltip: s.t('conn.start_minimized'),
                    icon: const Icon(Icons.remove_rounded, size: 18),
                    onPressed: () => windowManager.minimize(),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    tooltip: s.t('tray.quit'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => windowManager.close(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Center row: Info on left, Power Orb on right
              Expanded(
                child: Row(
                  children: [
                    // Left info column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FutureBuilder<NodeRow?>(
                            future: settings.activeNodeId == null
                                ? Future.value(null)
                                : ref.read(envProvider).repo.nodeRow(settings.activeNodeId!),
                            builder: (context, snap) {
                              final row = snap.data;
                              final flag = row == null ? null : leadingFlag(row.name);
                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => showLocationPicker(context),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (flag != null) ...[
                                            Text(flag, style: const TextStyle(fontSize: 15)),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            row != null ? row.protocol.toUpperCase() : 'VPN',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Brand.on,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          if (row != null)
                                            SignalBars(row.latency, showLabel: true),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        row == null ? s.t('home.choose') : cleanName(row.name),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Brand.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 3),
                          // IP Address
                          Text(
                            exitInfo != null ? exitInfo.ip : (core.isConnected ? s.t('ip.checking') : s.t('home.unprotected')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: core.isConnected ? Brand.textDim : Brand.bad,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Kill switch
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'KILL SWITCH',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: settings.tunStrictRoute ? Brand.on : Brand.textDim,
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                height: 20,
                                width: 36,
                                child: Switch(
                                  value: settings.tunStrictRoute,
                                  onChanged: (v) => set.update((x) => x.copyWith(tunStrictRoute: v)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Right power orb
                    _Orb(core: core, size: 95),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Bottom Locations bar
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showLocationPicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: Brand.glass(radius: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: Brand.textDim),
                      const SizedBox(width: 6),
                      Text(s.t('home.location'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Brand.textDim),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
