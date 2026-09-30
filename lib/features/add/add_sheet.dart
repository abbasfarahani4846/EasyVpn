import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/env.dart';
import '../../core/providers/profiles_provider.dart';
import '../../core/util/file_io.dart';
import '../../l10n/strings.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';
import '../scan/scan_page.dart';

/// One place to add anything: a single config link (vless://, vmess://,
/// trojan://, ss://, hy2://, tuic://, wireguard://, ssh://...), several links,
/// a subscription URL, a Clash / sing-box / Xray JSON, .ovpn / .conf files,
/// a QR code from the camera or from an image / screenshot.
Future<void> showAddConfigSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Brand.night2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.radius)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const _AddSheet(),
    ),
  );
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();
  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Imports [input]: http(s) URL -> subscription, anything else -> content.
  Future<void> _import(String input) async {
    final v = input.trim();
    if (v.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final p = ref.read(profilesProvider.notifier);
    ImportResult r;
    try {
      final isSub =
          (v.startsWith('http://') || v.startsWith('https://')) &&
          !v.contains('\n');
      r = isSub ? await p.addSubscription(v) : await p.importText(v);
    } catch (e) {
      r = ImportResult(error: '$e');
    }
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context);
      showSnack(context, context.s.t('subs.imported', {'n': r.total}));
    } else {
      setState(() {
        _busy = false;
        _error = r.error;
      });
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) {
      setState(() => _error = context.s.t('add.clipboard_empty'));
      return;
    }
    _text.text = t;
    await _import(t);
  }

  Future<void> _camera() async {
    final v = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (v != null && mounted) await _import(v);
  }

  Future<void> _qrImage() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final f = r?.files.firstOrNull;
    if (f == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final core = ref.read(envProvider).core;
      final text = f.bytes != null
          ? await core.decodeQr(bytes: f.bytes)
          : await core.decodeQr(path: f.path ?? '');
      if (!mounted) return;
      _text.text = text;
      await _import(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _file() async {
    final c = await pickTextFile();
    if (c != null) await _import(c);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Widget tile(IconData i, String label, VoidCallback? onTap) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: Brand.glass(radius: 18),
          child: Column(
            children: [
              Icon(i, color: Brand.on),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
    return Theme(
      data: Brand.theme(Theme.of(context)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.t('add.title'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.t('add.hint'),
                style: const TextStyle(fontSize: 12, color: Brand.textDim),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  tile(Icons.content_paste_rounded, s.t('add.paste'), _paste),
                  const SizedBox(width: 8),
                  if (scanSupported) ...[
                    tile(
                      Icons.qr_code_scanner_rounded,
                      s.t('add.camera'),
                      _camera,
                    ),
                    const SizedBox(width: 8),
                  ],
                  tile(
                    Icons.image_search_rounded,
                    s.t('add.qr_image'),
                    _qrImage,
                  ),
                  const SizedBox(width: 8),
                  tile(Icons.file_open_rounded, s.t('add.file'), _file),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: s.t('add.field'),
                  prefixIcon: const Icon(Icons.link_rounded),
                  filled: true,
                  fillColor: Brand.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Brand.bad, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.on,
                  foregroundColor: Brand.night,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _busy ? null : () => _import(_text.text),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(s.t('add.import')),
              ),
              if (Platform.isWindows || Platform.isLinux)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.t('add.desktop_qr_hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Brand.textDim),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
