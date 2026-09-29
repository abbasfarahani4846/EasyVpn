import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/nav_provider.dart';
import '../../core/providers/routing_actions.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/util/formatters.dart';
import '../../l10n/strings.dart';
import '../subscription/subscription_page.dart';

/// First-run: pick (or auto-detect) the country so routing works out of the box.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  String? _picked;
  String? _detected;
  bool _busy = true;

  static const _choices = {
    'IR': 'Iran · ایران',
    'CN': 'China · 中国',
    'RU': 'Russia · Россия',
    '': 'Other',
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final cc = await ref.read(routingActionsProvider.notifier).detect();
      if (!mounted) return;
      setState(() {
        _detected = cc.toUpperCase();
        _picked = _choices.containsKey(_detected) && _detected!.isNotEmpty
            ? _detected
            : '';
        _busy = false;
      });
    });
  }

  Future<void> _finish({bool addProfile = false}) async {
    final actions = ref.read(routingActionsProvider.notifier);
    await actions.setCountry(_picked ?? '', auto: _picked == _detected);
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(onboarded: true));
    if (addProfile && mounted) {
      ref.read(navProvider.notifier).go(Dest.profiles);
      await showAddSheet(context, ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.shield_moon_outlined, size: 80, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    s.t('onboard.title'),
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t('onboard.subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    if (_detected != null && _detected!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          s.t('onboard.detected', {
                            'c': '${flagEmoji(_detected!)} $_detected',
                          }),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    RadioGroup<String>(
                      groupValue: _picked,
                      onChanged: (v) => setState(() => _picked = v),
                      child: Column(
                        children: [
                          for (final e in _choices.entries)
                            Card(
                              child: RadioListTile<String>(
                                value: e.key,
                                title: Text('${flagEmoji(e.key)}  ${e.value}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => _finish(addProfile: true),
                      child: Text(s.t('onboard.import')),
                    ),
                    TextButton(
                      onPressed: _finish,
                      child: Text(s.t('onboard.continue')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
