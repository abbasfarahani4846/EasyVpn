import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/env.dart';
import '../../core/providers/routing_actions.dart';
import '../../core/providers/rules_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/util/formatters.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';

const _countryChoices = <String, String>{
  'IR': 'Iran · ایران',
  'CN': 'China · 中国',
  'RU': 'Russia · Россия',
  '': 'Other / none',
};
const _presets = [
  'bypass_local_country',
  'bypass_lan_only',
  'global_proxy',
  'bypass_proxy',
  'custom',
];
const _kinds = [
  'domain_suffix',
  'domain_keyword',
  'ip_cidr',
  'port',
  'process_name',
  'package_name',
  'rule_set',
];

class RoutingPage extends ConsumerWidget {
  const RoutingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final r = ref.watch(settingsProvider.select((x) => x.routing));
    final rules = ref.watch(rulesProvider);
    final set = ref.read(settingsProvider.notifier);
    final actions = ref.read(routingActionsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('routing.title'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          // ---- country -------------------------------------------------------
          SectionHeader(s.t('routing.country')),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: Text(
                    flagEmoji(r.country),
                    style: const TextStyle(fontSize: 28),
                  ),
                  title: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _countryChoices.containsKey(r.country)
                          ? r.country
                          : '',
                      items: [
                        for (final e in _countryChoices.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) =>
                          v == null ? null : actions.setCountry(v, auto: false),
                    ),
                  ),
                  subtitle: Text(
                    r.autoCountry
                        ? s.t('routing.country.auto')
                        : s.t('routing.country.manual'),
                  ),
                  trailing: IconButton(
                    tooltip: s.t('routing.detect'),
                    icon: const Icon(Icons.my_location),
                    onPressed: () async {
                      final cc = await actions.detectAndApply();
                      if (context.mounted && cc.isNotEmpty)
                        showSnack(
                          context,
                          s.t('onboard.detected', {'c': cc.toUpperCase()}),
                        );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ---- preset --------------------------------------------------------
          SectionHeader(s.t('routing.preset')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RadioGroup<String>(
              groupValue: r.mode,
              onChanged: (v) => set.setRouting((x) => x.copyWith(mode: v)),
              child: Column(
                children: [
                  for (final p in _presets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        color: r.mode == p
                            ? Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: 0.5)
                            : null,
                        child: RadioListTile<String>(
                          value: p,
                          title: Text(s.t('routing.preset.$p')),
                          subtitle: Text(s.t('routing.preset.$p.desc')),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      s.t('routing.rule_order'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---- toggles -------------------------------------------------------
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(s.t('routing.block_ads')),
                  value: r.blockAds,
                  onChanged: (v) =>
                      set.setRouting((x) => x.copyWith(blockAds: v)),
                ),
                SwitchListTile(
                  title: Text(s.t('routing.block_trackers')),
                  value: r.blockTrackers,
                  onChanged: (v) =>
                      set.setRouting((x) => x.copyWith(blockTrackers: v)),
                ),
                SwitchListTile(
                  title: Text(s.t('routing.bypass_lan')),
                  value: r.bypassLan,
                  onChanged: (v) =>
                      set.setRouting((x) => x.copyWith(bypassLan: v)),
                ),
              ],
            ),
          ),

          // ---- rule sets -----------------------------------------------------
          SectionHeader(
            s.t('routing.rulesets'),
            trailing: TextButton.icon(
              onPressed: rules.syncing
                  ? null
                  : () async {
                      await ref.read(rulesProvider.notifier).sync();
                      if (context.mounted) {
                        final failed =
                            ref.read(rulesProvider).lastError != null;
                        showSnack(
                          context,
                          failed
                              ? s.t('routing.sync_fail')
                              : s.t('routing.sync_ok'),
                          error: failed,
                        );
                      }
                    },
              icon: rules.syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: Text(
                rules.syncing ? s.t('routing.syncing') : s.t('routing.sync'),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(s.t('routing.auto_update')),
                  value: r.autoUpdateRules,
                  onChanged: (v) =>
                      set.setRouting((x) => x.copyWith(autoUpdateRules: v)),
                ),
                for (final st in rules.statuses)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      st.present ? Icons.check_circle : Icons.error_outline,
                      color: st.present
                          ? const Color(0xFF22C55E)
                          : Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    title: Text(st.tag),
                    subtitle: Text(
                      st.fetchedAt == null
                          ? (st.present
                                ? s.t('routing.baseline')
                                : s.t('routing.missing'))
                          : s.t('routing.updated', {'t': _ago(st.fetchedAt!)}),
                    ),
                    trailing: Text(
                      st.present ? fmtBytes(st.bytes) : '',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_link),
                  title: Text(s.t('routing.add_ruleset')),
                  onTap: () => _addRuleSet(context, ref),
                ),
              ],
            ),
          ),

          // ---- service overrides --------------------------------------------
          SectionHeader(s.t('routing.overrides')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              s.t('routing.overrides.desc'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _ChipList(
            title: s.t('routing.overrides.proxy'),
            values: r.overrideProxy,
            onChanged: (v) =>
                set.setRouting((x) => x.copyWith(overrideProxy: v)),
          ),
          _ChipList(
            title: s.t('routing.overrides.direct'),
            values: r.overrideDirect,
            onChanged: (v) =>
                set.setRouting((x) => x.copyWith(overrideDirect: v)),
          ),

          // ---- custom rules --------------------------------------------------
          SectionHeader(
            s.t('routing.custom_rules'),
            trailing: TextButton.icon(
              onPressed: () => _editRule(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.t('routing.add_rule')),
            ),
          ),
          if (r.customRules.isNotEmpty)
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onReorderItem: (a, b) {
                final list = [...r.customRules];
                list.insert(b, list.removeAt(a));
                set.setRouting((x) => x.copyWith(customRules: list));
              },
              children: [
                for (var i = 0; i < r.customRules.length; i++)
                  Card(
                    key: ValueKey(
                      'rule$i${r.customRules[i].kind}${r.customRules[i].values.join()}',
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _editRule(context, ref, i),
                      leading: _outIcon(r.customRules[i].outbound),
                      title: Text(s.t('routing.kind.${r.customRules[i].kind}')),
                      subtitle: Text(
                        r.customRules[i].values.join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => set.setRouting(
                              (x) => x.copyWith(
                                customRules: [...x.customRules]..removeAt(i),
                              ),
                            ),
                          ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

          // ---- DNS -----------------------------------------------------------
          SectionHeader(s.t('routing.dns')),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _DnsField(
                    label: s.t('routing.dns.remote'),
                    value: r.remoteDns,
                    onChanged: (v) =>
                        set.setRouting((x) => x.copyWith(remoteDns: v)),
                    hint: 'https://1.1.1.1/dns-query',
                  ),
                  const SizedBox(height: 10),
                  _DnsField(
                    label: s.t('routing.dns.local'),
                    value: r.localDns,
                    onChanged: (v) =>
                        set.setRouting((x) => x.copyWith(localDns: v)),
                    hint: 'udp://178.22.122.100',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.t('routing.dns.fakeip')),
                    value: r.fakeIp,
                    onChanged: (v) =>
                        set.setRouting((x) => x.copyWith(fakeIp: v)),
                  ),
                ],
              ),
            ),
          ),

          // ---- TLS tricks ----------------------------------------------------
          SectionHeader(s.t('routing.tls_tricks')),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: SwitchListTile(
              title: Text(s.t('routing.tls_fragment')),
              subtitle: Text(s.t('routing.tls_fragment.desc')),
              value: r.tlsFragment,
              onChanged: (v) =>
                  set.setRouting((x) => x.copyWith(tlsFragment: v)),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _outIcon(String o) => switch (o) {
    'direct' => const Icon(Icons.arrow_forward, color: Color(0xFF22C55E)),
    'block' => const Icon(Icons.block, color: Color(0xFFEF4444)),
    _ => const Icon(Icons.vpn_lock, color: Color(0xFF3B82F6)),
  };

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes} m';
    if (d.inDays < 1) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  Future<void> _addRuleSet(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final tag = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('routing.add_ruleset')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tag,
              decoration: InputDecoration(
                labelText: s.t('routing.ruleset.tag'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: url,
              decoration: InputDecoration(
                labelText: s.t('routing.ruleset.url'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('common.add')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(envProvider).core.addRuleSet(tag.text.trim(), [
        url.text.trim(),
      ]);
      await ref.read(rulesProvider.notifier).sync(tags: [tag.text.trim()]);
    } catch (e) {
      if (context.mounted) showSnack(context, '$e', error: true);
    }
  }

  Future<void> _editRule(
    BuildContext context,
    WidgetRef ref,
    int? index,
  ) async {
    final s = context.s;
    final set = ref.read(settingsProvider.notifier);
    final existing = index == null
        ? null
        : ref.read(settingsProvider).routing.customRules[index];
    var kind = existing?.kind ?? 'domain_suffix';
    var out = existing?.outbound ?? 'proxy';
    final values = TextEditingController(
      text: existing?.values.join(', ') ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(s.t('routing.add_rule')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: InputDecoration(
                    labelText: s.t('routing.rule.kind'),
                  ),
                  items: [
                    for (final k in _kinds)
                      DropdownMenuItem(
                        value: k,
                        child: Text(s.t('routing.kind.$k')),
                      ),
                  ],
                  onChanged: (v) => setS(() => kind = v ?? kind),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: values,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: s.t('routing.rule.values'),
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    for (final o in ['direct', 'proxy', 'block'])
                      ButtonSegment(
                        value: o,
                        label: Text(s.t('routing.out.$o')),
                      ),
                  ],
                  selected: {out},
                  onSelectionChanged: (v) => setS(() => out = v.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('common.save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final vs = values.text
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (vs.isEmpty) return;
    final rule = CustomRule(kind: kind, values: vs, outbound: out);
    set.setRouting((x) {
      final list = [...x.customRules];
      index == null ? list.add(rule) : list[index] = rule;
      return x.copyWith(
        customRules: list,
        mode: x.mode == 'bypass_lan_only' ? 'custom' : x.mode,
      );
    });
  }
}

class _ChipList extends StatelessWidget {
  const _ChipList({
    required this.title,
    required this.values,
    required this.onChanged,
  });
  final String title;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in values)
                InputChip(
                  label: Text(v),
                  onDeleted: () => onChanged([...values]..remove(v)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text(s.t('common.add')),
                onPressed: () async {
                  final t = await promptText(
                    context,
                    title: title,
                    hint: s.t('routing.overrides.hint'),
                  );
                  if (t == null || t.isEmpty) return;
                  final add = t
                      .split(RegExp(r'[,\s]+'))
                      .where((e) => e.isNotEmpty);
                  onChanged({...values, ...add}.toList());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DnsField extends StatefulWidget {
  const _DnsField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.hint,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  @override
  State<_DnsField> createState() => _DnsFieldState();
}

class _DnsFieldState extends State<_DnsField> {
  late final _c = TextEditingController(text: widget.value);
  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    onChanged: widget.onChanged,
    decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
  );
}
