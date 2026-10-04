import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../single_config/share_link_parser.dart';
import '../single_config/single_config_service.dart';
import 'vpn_config_parser.dart';

const windscribeProfileLabel = 'Windscribe';

/// Adds OpenVPN (.ovpn) and WireGuard (.conf) configs, such as the ones
/// Windscribe's Config Generator produces, to their own "Windscribe" profile.
class WindscribeView extends ConsumerStatefulWidget {
  const WindscribeView({super.key});

  @override
  ConsumerState<WindscribeView> createState() => _WindscribeViewState();
}

class _WindscribeViewState extends ConsumerState<WindscribeView> {
  final _name = TextEditingController();
  final _text = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _t(String fa, String en) => _fa ? fa : en;

  /// Every OpenVPN file gets the fields (WireGuard keeps its keys inside the
  /// file); they are required only when the file has `auth-user-pass`.
  bool get _needsCredentials => VpnConfigParser.looksLikeOpenVpn(_text.text);

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await globalState.safeRun(picker.pickerFile);
    if (file == null) return;
    final bytes = await file.readBytes();
    if (!mounted) return;
    setState(() {
      _text.text = utf8.decode(bytes, allowMalformed: true);
      if (_name.text.isEmpty) {
        _name.text = file.name.replaceAll(RegExp(r'\.(ovpn|conf)$'), '');
      }
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    setState(() => _text.text = text);
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final name = _name.text.trim();
      final proxy = VpnConfigParser.parse(
        _text.text,
        name: name.isEmpty ? null : name,
        username: _user.text.trim(),
        password: _pass.text,
      );
      final result = await SingleConfigService.addParsed(
        ref,
        ShareLinkParseResult([proxy], const []),
        label: windscribeProfileLabel,
        select: true,
      );
      if (!mounted) return;
      dialogs.showNotifier(
        result.added > 0
            ? _t(
                'به پروفایل Windscribe اضافه شد؛ دکمه‌ی اتصال را بزنید',
                'Added to the Windscribe profile; press connect',
              )
            : _t('این کانفیگ از قبل وجود دارد', 'This config already exists'),
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
    return CommonScaffold(
      title: 'Windscribe / OpenVPN / WireGuard',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
        children: [
          Text(
            _t(
              'در سایت Windscribe بخش Config Generator را باز کنید، '
                  'OpenVPN یا WireGuard، مکان و پورت را انتخاب و '
                  '«Download Config» را بزنید (برای OpenVPN «Get Credentials» '
                  'هم لازم است). فایل را اینجا انتخاب کنید یا متنش را '
                  'بچسبانید. IKEv2 پشتیبانی نمی‌شود.',
              'In Windscribe open Config Generator, pick OpenVPN or '
                  'WireGuard, the location and port, and press Download '
                  'Config (OpenVPN also needs Get Credentials). Choose the '
                  'file here or paste its text. IKEv2 is not supported.',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.upload_file),
                label: Text(_t('انتخاب فایل', 'Choose file')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste),
                label: Text(_t('چسباندن', 'Paste')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: _t('نام (اختیاری)', 'Name (optional)'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 10,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: _t('محتوای کانفیگ', 'Config content'),
            ),
          ),
          if (_needsCredentials) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _t('نام کاربری OpenVPN', 'OpenVPN username'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              autocorrect: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _t('رمز OpenVPN', 'OpenVPN password'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _busy || _text.text.trim().isEmpty
                  ? null
                  : () => unawaited(_add()),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_t('افزودن', 'Add')),
            ),
          ),
        ],
      ),
    );
  }
}
