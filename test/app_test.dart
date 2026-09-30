import 'dart:convert';

import 'package:easyvpn/core/models/models.dart';
import 'package:easyvpn/core/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';
import 'support/pump_app.dart';

Map<String, dynamic> node(int i) => {
  'id': 'id$i',
  'name': 'Node $i',
  'type': 'vless',
  'server': 'h$i.example.com',
  'port': 443,
  'uuid': 'u$i',
};

void main() {
  testWidgets('shows onboarding on first run and reaches the dashboard', (
    tester,
  ) async {
    final t = FakeTransport(
      handlers: {
        'DetectCountry': (_) => {
          'country': 'ir',
          'source': 'locale',
          'confidence': 0.7,
        },
        'SetCountry': (a) => {
          'routing': {},
          'pack': {
            'name': 'Iran',
            'tls_tricks': {'fragment': true},
            'service_overrides': {
              'proxy': ['whatsapp.com'],
              'direct': [],
            },
          },
        },
        'RuleSetStatus': (_) => {'statuses': []},
        'SyncRuleSets': (_) => {'events': []},
      },
    );
    await pumpApp(
      tester,
      settings: const AppSettings(onboarded: false),
      transport: t,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Welcome to EasyVPN'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    // New users land on the one-button home.
    expect(find.text('Not protected'), findsWidgets);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
    expect(t.calls, contains('SetCountry'));
  });

  testWidgets('onboarding "add profile" imports on the FIRST try', (
    tester,
  ) async {
    final t = FakeTransport(
      handlers: {
        'DetectCountry': (_) => {'country': 'ir', 'source': 'locale'},
        'SetCountry': (_) => {
          'routing': {},
          'pack': {'tls_tricks': {}, 'service_overrides': {}},
        },
        'RuleSetStatus': (_) => {'statuses': []},
        'SyncRuleSets': (_) => {'events': []},
        'FetchSubscription': (a) => {
          'nodes': [node(1), node(2)],
          'via': 'direct',
        },
      },
    );
    final app = await pumpApp(
      tester,
      settings: const AppSettings(onboarded: false),
      transport: t,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add a profile now'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.enterText(
      find.byType(TextField).first,
      'https://sub.example.com/abc',
    );
    final import = tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text('Import'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    );
    import.onPressed!();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(t.calls, contains('FetchSubscription'));
    expect(await app.env.repo.count(), 2);
    expect(find.byType(BottomSheet), findsNothing); // closed on success
  });

  testWidgets(
    'dashboard reports core unavailable and never fakes a connection',
    (tester) async {
      await pumpApp(tester, transport: unavailableTransport());
      expect(find.text('Core unavailable'), findsWidgets);
      expect(find.text('Connected'), findsNothing);
      // tapping the power button must not start anything
      await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
      await tester.pump();
      expect(find.text('Connecting…'), findsNothing);
    },
  );

  testWidgets('connect flow: start -> state events -> connected -> stop', (
    tester,
  ) async {
    late FakeTransport t;
    t = FakeTransport(
      handlers: {
        'SetRouting': (_) => {},
        'Start': (a) {
          expect(a['mode'], 'proxy_only');
          expect((a['node'] as Map)['id'], 'id1');
          t.emit('state', {
            'state': 'connected',
            'detail': '',
            'mode': 'proxy_only',
          });
          return {};
        },
        'Stop': (_) {
          t.emit('state', {
            'state': 'disconnected',
            'detail': '',
            'mode': 'proxy_only',
          });
          return {};
        },
        'ExitInfo': (_) => {
          'ip': '1.2.3.4',
          'country': 'Germany',
          'countryCode': 'DE',
          'city': 'Berlin',
        },
      },
    );
    await pumpApp(
      tester,
      settings: const AppSettings(
        onboarded: true,
        activeNodeId: 'id1',
        activeProfileId: 'p1',
        uiMode: 'advanced',
      ),
      transport: t,
      seed: (repo) async => repo.importNodes('p1', [node(1)]),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Connected'), findsOneWidget);
    expect(t.calls, contains('Start'));

    // Real exit IP card appears after connect.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('1.2.3.4'), findsOneWidget);
    expect(t.calls, contains('ExitInfo'));

    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Disconnected'), findsOneWidget);
  });

  testWidgets(
    'connect failure with an unsupported node shows the capability hint',
    (tester) async {
      final t = FakeTransport(
        handlers: {
          'SetRouting': (_) => {},
          'Start': (_) =>
              throw CoreErr('unsupported_by_core:xhttp (not available)'),
        },
      );
      await pumpApp(
        tester,
        settings: const AppSettings(
          onboarded: true,
          activeNodeId: 'id1',
          activeProfileId: 'p1',
          uiMode: 'advanced',
        ),
        transport: t,
        seed: (repo) async => repo.importNodes('p1', [node(1)]),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('xhttp'), findsWidgets);
    },
  );

  testWidgets('Persian locale switches to RTL and translated labels', (
    tester,
  ) async {
    final s = const AppSettings(
      onboarded: true,
      uiMode: 'advanced',
      appearance: AppearanceSettings(locale: 'fa'),
    );
    await pumpApp(tester, settings: s);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('داشبورد'), findsWidgets);
    final dir = Directionality.of(tester.element(find.text('داشبورد').first));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('routing page: choosing a preset updates and persists settings', (
    tester,
  ) async {
    final t = FakeTransport(
      handlers: {
        'SetCountry': (_) => {
          'routing': {},
          'pack': {
            'tls_tricks': {'fragment': false},
            'service_overrides': {},
          },
        },
        'RuleSetStatus': (_) => {
          'statuses': [
            {'tag': 'geosite-ir', 'present': true, 'bytes': 310119},
          ],
        },
        'SyncRuleSets': (_) => {'events': []},
      },
    );
    final app = await pumpApp(tester, transport: t);
    await tester.tap(find.text('Routing').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Global proxy'));
    await tester.pump(const Duration(milliseconds: 400));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    expect(container.read(settingsProvider).routing.mode, 'global_proxy');
    await tester.pump(const Duration(milliseconds: 400)); // debounce flush
    final stored = await app.env.db.kvGet('settings');
    expect(jsonDecode(stored!)['routing']['mode'], 'global_proxy');
  });

  testWidgets('simple home: one tap connects, shows exit IP, then stops', (
    tester,
  ) async {
    late FakeTransport t;
    t = FakeTransport(
      handlers: {
        'SetRouting': (_) => {},
        'Start': (a) {
          t.emit('state', {'state': 'connected', 'detail': '', 'mode': 'tun'});
          return {};
        },
        'Stop': (_) {
          t.emit('state', {
            'state': 'disconnected',
            'detail': '',
            'mode': 'tun',
          });
          return {};
        },
        'ExitInfo': (_) => {'ip': '9.9.9.9', 'countryCode': 'DE'},
      },
    );
    await pumpApp(
      tester,
      settings: const AppSettings(
        onboarded: true,
        activeNodeId: 'id1',
        activeProfileId: 'p1',
        mode: ConnMode.proxyOnly,
      ),
      transport: t,
      seed: (repo) async => repo.importNodes('p1', [node(1)]),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Node 1'), findsOneWidget); // location card
    expect(find.text('Not protected'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Protected'), findsOneWidget);
    expect(find.textContaining('9.9.9.9'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Not protected'), findsOneWidget);
  });

  testWidgets('simple home menu opens advanced pages', (tester) async {
    await pumpApp(
      tester,
      settings: const AppSettings(onboarded: true),
      transport: FakeTransport(handlers: {}),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Chains & WARP'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Exit via WARP'), findsWidgets);
    expect(find.text('WARP in WARP'), findsOneWidget);
  });

  test('AppSettings JSON round trip keeps every field', () {
    const s = AppSettings(
      mode: ConnMode.both,
      localPort: 3000,
      perAppMode: 'include',
      perAppPackages: ['a.b'],
      routing: RoutingSettings(
        country: 'RU',
        customRules: [
          CustomRule(
            kind: 'domain_suffix',
            values: ['x.com'],
            outbound: 'block',
          ),
        ],
      ),
      appearance: AppearanceSettings(
        amoled: true,
        accent: 0xFF123456,
        locale: 'fa',
      ),
    );
    final r = AppSettings.decode(s.encode());
    final r2 = AppSettings.decode(
      const AppSettings(
        ipCheckUrl: 'https://x/ip',
        uiMode: 'advanced',
        chainNodeIds: ['a', 'b'],
        exitNodeId: 'w',
        updateChannel: 'stable',
        autoUpdateCheck: false,
      ).encode(),
    );
    expect(r2.ipCheckUrl, 'https://x/ip');
    expect(r2.uiMode, 'advanced');
    expect(r2.chainNodeIds, ['a', 'b']);
    expect(r2.exitNodeId, 'w');
    expect(r2.updateChannel, 'stable');
    expect(r2.autoUpdateCheck, isFalse);
    expect(r.mode, ConnMode.both);
    expect(r.localPort, 3000);
    expect(r.perAppPackages, ['a.b']);
    expect(r.routing.country, 'RU');
    expect(r.routing.customRules.single.outbound, 'block');
    expect(r.appearance.amoled, isTrue);
    expect(r.appearance.accent, 0xFF123456);
    expect(r.routing.toCoreModel()['custom_rules'], isNotEmpty);
  });
}

/// Throws like a failing core method.
class CoreErr implements Exception {
  CoreErr(this.m);
  final String m;
  @override
  String toString() => m;
}
