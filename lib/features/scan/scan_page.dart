import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/strings.dart';

/// True where the camera scanner plugin works.
bool get scanSupported =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Full-screen QR scanner; pops with the first decoded string.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('scan.title'))),
      body: !scanSupported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.t('scan.unsupported'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    if (_done) return;
                    for (final b in capture.barcodes) {
                      final v = b.rawValue;
                      if (v != null && v.isNotEmpty) {
                        _done = true;
                        Navigator.of(context).pop(v);
                        return;
                      }
                    }
                  },
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      s.t('scan.hint'),
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
