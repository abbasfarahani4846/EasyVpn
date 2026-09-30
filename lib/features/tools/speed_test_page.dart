import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/core_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../l10n/strings.dart';
import '../../theme/brand.dart';

class SpeedTestPage extends ConsumerStatefulWidget {
  const SpeedTestPage({super.key});

  @override
  ConsumerState<SpeedTestPage> createState() => _SpeedTestPageState();
}

class _SpeedTestPageState extends ConsumerState<SpeedTestPage> {
  bool _running = false;
  String _phase = 'idle'; // idle | ping | download | upload | done
  int _pingMs = 0;
  double _downMbps = 0.0;
  double _upMbps = 0.0;
  double _progress = 0.0;
  String? _error;

  HttpClient _buildClient() {
    final s = ref.read(settingsProvider);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = ((cert, host, port) => true);
    if (s.mode == ConnMode.proxyOnly) {
      client.findProxy = (_) => 'PROXY 127.0.0.1:${s.localPort}';
    }
    return client;
  }

  Future<void> _startTest() async {
    if (_running) return;
    setState(() {
      _running = true;
      _phase = 'ping';
      _pingMs = 0;
      _downMbps = 0.0;
      _upMbps = 0.0;
      _progress = 0.1;
      _error = null;
    });

    final client = _buildClient();

    try {
      // 1. Ping test
      final pings = <int>[];
      for (var i = 0; i < 3; i++) {
        if (!mounted || !_running) return;
        final sw = Stopwatch()..start();
        final req = await client.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=0'));
        final res = await req.close();
        await res.drain<void>();
        sw.stop();
        pings.add(sw.elapsedMilliseconds);
        setState(() {
          _pingMs = (pings.reduce((a, b) => a + b) / pings.length).round();
          _progress = 0.15 + (i * 0.05);
        });
      }

      // 2. Download test (10MB stream)
      if (!mounted || !_running) return;
      setState(() {
        _phase = 'download';
        _progress = 0.3;
      });

      final downSw = Stopwatch()..start();
      final downReq = await client.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=12000000'));
      final downRes = await downReq.close();
      var receivedBytes = 0;

      await for (final chunk in downRes) {
        if (!mounted || !_running) {
          client.close(force: true);
          return;
        }
        receivedBytes += chunk.length;
        final seconds = downSw.elapsedMilliseconds / 1000.0;
        if (seconds > 0.2) {
          final mbps = (receivedBytes * 8) / (seconds * 1000000);
          setState(() {
            _downMbps = double.parse(mbps.toStringAsFixed(1));
            _progress = (0.3 + (receivedBytes / 12000000) * 0.4).clamp(0.3, 0.7);
          });
        }
      }
      downSw.stop();

      // 3. Upload test (3MB payload)
      if (!mounted || !_running) return;
      setState(() {
        _phase = 'upload';
        _progress = 0.75;
      });

      final upBytes = Uint8List(3 * 1024 * 1024);
      final upSw = Stopwatch()..start();
      final upReq = await client.postUrl(Uri.parse('https://speed.cloudflare.com/__up'));
      upReq.contentLength = upBytes.length;
      upReq.add(upBytes);
      final upRes = await upReq.close();
      await upRes.drain<void>();
      upSw.stop();

      final upSeconds = upSw.elapsedMilliseconds / 1000.0;
      if (upSeconds > 0.1) {
        final mbps = (upBytes.length * 8) / (upSeconds * 1000000);
        setState(() {
          _upMbps = double.parse(mbps.toStringAsFixed(1));
          _progress = 1.0;
          _phase = 'done';
          _running = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _running = false;
          _phase = 'idle';
        });
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isConnected = ref.watch(coreControllerProvider.select((x) => x.isConnected));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('speed.title')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isConnected)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Brand.busy.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Brand.busy.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Brand.busy, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.t('speed.not_connected_warning'),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              // Gauge / Main stat
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: Brand.orbGradient(
                            _running ? CoreStatus.connecting : CoreStatus.connected,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Brand.on.withValues(alpha: _running ? 0.35 : 0.15),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _phase == 'upload'
                                  ? Icons.upload_rounded
                                  : Icons.download_rounded,
                              size: 32,
                              color: Brand.on,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _phase == 'upload'
                                  ? '$_upMbps'
                                  : '$_downMbps',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Text(
                              'Mbps',
                              style: TextStyle(
                                fontSize: 13,
                                color: Brand.textDim,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _phase == 'ping'
                            ? s.t('speed.testing_ping')
                            : _phase == 'download'
                            ? s.t('speed.testing_download')
                            : _phase == 'upload'
                            ? s.t('speed.testing_upload')
                            : _phase == 'done'
                            ? s.t('speed.test_complete')
                            : s.t('speed.ready'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_running) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: 200,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: _progress,
                              minHeight: 6,
                              backgroundColor: Brand.panel,
                              color: Brand.on,
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Brand.bad, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Results card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: Brand.glass(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ResultTile(
                      icon: Icons.network_ping_rounded,
                      title: s.t('speed.ping'),
                      value: _pingMs > 0 ? '$_pingMs ms' : '—',
                      color: Brand.busy,
                    ),
                    _ResultTile(
                      icon: Icons.arrow_downward_rounded,
                      title: s.t('speed.download'),
                      value: _downMbps > 0 ? '$_downMbps' : '—',
                      unit: 'Mbps',
                      color: Brand.on,
                    ),
                    _ResultTile(
                      icon: Icons.arrow_upward_rounded,
                      title: s.t('speed.upload'),
                      value: _upMbps > 0 ? '$_upMbps' : '—',
                      unit: 'Mbps',
                      color: Brand.on2,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Start / Restart button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: _running ? null : _startTest,
                icon: Icon(_phase == 'done' ? Icons.replay_rounded : Icons.play_arrow_rounded),
                label: Text(
                  _phase == 'done'
                      ? s.t('speed.retest')
                      : _running
                      ? s.t('speed.testing')
                      : s.t('speed.start'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.value,
    this.unit = '',
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(title, style: const TextStyle(fontSize: 12, color: Brand.textDim)),
          ],
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            text: value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Brand.text,
            ),
            children: [
              if (unit.isNotEmpty && value != '—')
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(fontSize: 10, color: Brand.textDim),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
