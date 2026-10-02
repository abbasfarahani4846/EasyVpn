import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/env.dart';
import '../../core/update/update_service.dart';
import '../../l10n/strings.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final core = ref.read(envProvider).core;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings.about'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Icon(
              Icons.shield_moon_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              s.t('app.name'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: Text(s.t('about.version')),
            trailing: Text(buildLabel.startsWith('v') ? buildLabel.substring(1) : buildLabel),
          ),
          FutureBuilder<Map<String, dynamic>>(
            future: core.isAvailable ? core.info() : Future.value(const {}),
            builder: (_, snap) => ListTile(
              title: Text(s.t('about.core')),
              subtitle: Text(
                snap.hasData && snap.data!.isNotEmpty
                    ? '${snap.data!['core']} ${snap.data!['version']}\n${(snap.data!['protocols'] as List?)?.join(', ') ?? ''}'
                    : s.t('core.unavailable'),
              ),
            ),
          ),
          const Divider(),
          Text(
            s.t('about.gpl'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.t('about.geo'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                showLicensePage(context: context, applicationName: 'EasyVPN'),
            child: Text(s.t('about.license')),
          ),
        ],
      ),
    );
  }
}
