import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../warp/warp_registration.dart';
import 'share_link_parser.dart';
import 'single_config_service.dart';

void showSingleConfigPage() {
  final context = globalState.navigatorKey.currentState!.context;
  final fa = Localizations.localeOf(context).languageCode == 'fa';
  showExtend(
    context,
    builder: (context) => CommonScaffold(
      title: fa ? 'افزودن کانفیگ تکی' : 'Add single config',
      body: const SingleConfigView(),
    ),
  );
}

class SingleConfigView extends ConsumerStatefulWidget {
  const SingleConfigView({super.key});

  @override
  ConsumerState<SingleConfigView> createState() => _SingleConfigViewState();
}

class _SingleConfigViewState extends ConsumerState<SingleConfigView> {
  final _controller = TextEditingController();
  bool _busy = false;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    setState(() => _controller.text = text);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await SingleConfigService.add(ref, text);
      if (!mounted) return;
      final message = _fa
          ? '${result.added} کانفیگ اضافه شد'
                '${result.skipped > 0 ? '، ${result.skipped} تکراری' : ''}'
                '${result.errors.isNotEmpty ? '، ${result.errors.length} ناموفق' : ''}'
          : '${result.added} added'
                '${result.skipped > 0 ? ', ${result.skipped} duplicate' : ''}'
                '${result.errors.isNotEmpty ? ', ${result.errors.length} failed' : ''}';
      dialogs.showNotifier(
        message,
        level: result.added > 0 ? MessageLevel.success : MessageLevel.warning,
      );
      globalState.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      ref.read(currentPageLabelProvider.notifier).toProfiles();
    } catch (e) {
      dialogs.showNotifier(compactError(e), level: MessageLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addWarp() async {
    if (_busy) return;
    setState(() => _busy = true);
    final fa = _fa;
    try {
      final proxy = await WarpRegistration.register(name: 'WARP');
      final result = await SingleConfigService.addParsed(
        ref,
        ShareLinkParseResult([proxy], const []),
      );
      if (!mounted) return;
      dialogs.showNotifier(
        result.added > 0
            ? (fa ? 'WARP اضافه شد' : 'WARP added')
            : (fa ? 'WARP از قبل وجود دارد' : 'WARP already exists'),
        level: MessageLevel.success,
      );
      globalState.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      ref.read(currentPageLabelProvider.notifier).toProfiles();
    } catch (e) {
      dialogs.showNotifier(compactError(e), level: MessageLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = _fa;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
      children: [
        Text(
          fa
              ? 'لینک (vless, vmess, trojan, ss, hysteria2, tuic, anytls)، '
                    'چند لینک در چند خط، یا YAML کلش را بچسبانید. کانفیگ‌ها '
                    'به پروفایل «Default» اضافه می‌شوند.'
              : 'Paste a share link (vless, vmess, trojan, ss, hysteria2, '
                    'tuic, anytls), several links on separate lines, or a '
                    'Clash YAML. Configs are added to the "Default" profile.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          minLines: 6,
          maxLines: 12,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: fa ? 'کانفیگ' : 'Config',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _paste,
              icon: const Icon(Icons.content_paste),
              label: Text(fa ? 'چسباندن' : 'Paste'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(fa ? 'افزودن' : 'Add'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud),
          title: const Text('Cloudflare WARP'),
          subtitle: Text(
            fa
                ? 'یک حساب رایگان و ناشناس WARP می‌سازد و به پروفایل Default اضافه می‌کند'
                : 'Creates a free anonymous WARP device and adds it to the Default profile',
          ),
          trailing: OutlinedButton(
            onPressed: _busy ? null : _addWarp,
            child: Text(fa ? 'افزودن' : 'Add'),
          ),
        ),
      ],
    );
  }
}
