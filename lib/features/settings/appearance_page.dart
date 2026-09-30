import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/platform_service.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final a = ref.watch(settingsProvider.select((x) => x.appearance));
    final set = ref.read(settingsProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings.appearance'))),
      body: ListView(
        children: [
          SectionHeader(s.t('appearance.theme')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                for (final m in ['system', 'light', 'dark'])
                  ButtonSegment(
                    value: m,
                    label: Text(s.t('appearance.theme.$m')),
                  ),
              ],
              selected: {a.themeMode},
              onSelectionChanged: (v) =>
                  set.setAppearance((x) => x.copyWith(themeMode: v.first)),
            ),
          ),
          SwitchListTile(
            title: Text(s.t('appearance.amoled')),
            value: a.amoled,
            onChanged: (v) => set.setAppearance((x) => x.copyWith(amoled: v)),
          ),
          SwitchListTile(
            title: Text(s.t('appearance.dynamic')),
            value: a.dynamicColor,
            onChanged: (v) =>
                set.setAppearance((x) => x.copyWith(dynamicColor: v)),
          ),
          SectionHeader(s.t('appearance.accent')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in accentPresets)
                  GestureDetector(
                    onTap: () => set.setAppearance(
                      (x) => x.copyWith(accent: c, dynamicColor: false),
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: a.accent == c && !a.dynamicColor
                              ? cs.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: a.accent == c && !a.dynamicColor
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.colorize, size: 18),
                  label: const Text('#hex'),
                  onPressed: () async {
                    final t = await promptText(
                      context,
                      title: s.t('appearance.accent'),
                      hint: 'RRGGBB',
                      initial: a.accent
                          .toRadixString(16)
                          .substring(2)
                          .toUpperCase(),
                    );
                    final v = t == null
                        ? null
                        : int.tryParse(t.replaceAll('#', ''), radix: 16);
                    if (v != null && t!.replaceAll('#', '').length == 6)
                      set.setAppearance(
                        (x) => x.copyWith(
                          accent: 0xFF000000 | v,
                          dynamicColor: false,
                        ),
                      );
                  },
                ),
              ],
            ),
          ),
          SectionHeader(s.t('appearance.font_scale')),
          Slider(
            value: a.fontScale,
            min: 0.85,
            max: 1.3,
            divisions: 9,
            label: '${(a.fontScale * 100).round()}%',
            onChanged: (v) =>
                set.setAppearance((x) => x.copyWith(fontScale: v)),
          ),
          SectionHeader(s.t('appearance.radius')),
          Slider(
            value: a.cornerRadius,
            min: 4,
            max: 28,
            divisions: 12,
            label: '${a.cornerRadius.round()}',
            onChanged: (v) =>
                set.setAppearance((x) => x.copyWith(cornerRadius: v)),
          ),
          SectionHeader(s.t('appearance.density')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                for (final m in ['comfortable', 'compact'])
                  ButtonSegment(
                    value: m,
                    label: Text(s.t('appearance.density.$m')),
                  ),
              ],
              selected: {a.density},
              onSelectionChanged: (v) =>
                  set.setAppearance((x) => x.copyWith(density: v.first)),
            ),
          ),
          SectionHeader(s.t('appearance.language')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'system',
                  label: Text(s.t('appearance.language.system')),
                ),
                const ButtonSegment(value: 'en', label: Text('English')),
                const ButtonSegment(value: 'fa', label: Text('فارسی')),
              ],
              selected: {a.locale},
              onSelectionChanged: (v) =>
                  set.setAppearance((x) => x.copyWith(locale: v.first)),
            ),
          ),
          SectionHeader(s.t('appearance.nav')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                for (final m in ['auto', 'bottom', 'rail'])
                  ButtonSegment(
                    value: m,
                    label: Text(s.t('appearance.nav.$m')),
                  ),
              ],
              selected: {a.navStyle},
              onSelectionChanged: (v) =>
                  set.setAppearance((x) => x.copyWith(navStyle: v.first)),
            ),
          ),
          SwitchListTile(
            title: Text(s.t('appearance.chart')),
            value: a.showSpeedChart,
            onChanged: (v) =>
                set.setAppearance((x) => x.copyWith(showSpeedChart: v)),
          ),
          if (PlatformService.isDesktop) ...[
            SectionHeader(s.t('view.switcher')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Consumer(
                builder: (context, ref, _) {
                  final settings = ref.watch(settingsProvider);
                  final current = settings.miniWindow
                      ? 'mini'
                      : (settings.uiMode == 'advanced' ? 'advanced' : 'simple');
                  return SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'mini',
                        icon: const Icon(Icons.crop_16_9_rounded, size: 16),
                        label: Text(s.t('view.mini')),
                      ),
                      ButtonSegment(
                        value: 'simple',
                        icon: const Icon(Icons.smartphone_rounded, size: 16),
                        label: Text(s.t('view.simple')),
                      ),
                      ButtonSegment(
                        value: 'advanced',
                        icon: const Icon(Icons.desktop_windows_rounded, size: 16),
                        label: Text(s.t('view.advanced')),
                      ),
                    ],
                    selected: {current},
                    onSelectionChanged: (v) {
                      final val = v.first;
                      if (val == 'mini') {
                        set.update((x) => x.copyWith(uiMode: 'simple', miniWindow: true));
                      } else if (val == 'simple') {
                        set.update((x) => x.copyWith(uiMode: 'simple', miniWindow: false));
                      } else if (val == 'advanced') {
                        set.update((x) => x.copyWith(uiMode: 'advanced', miniWindow: false));
                      }
                    },
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
