import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyvpn/core/providers/app_providers.dart';
import 'package:easyvpn/core/storage/storage_service.dart';
import 'package:easyvpn/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App boots to dashboard without a native core (stub mode)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const EasyVpnApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Desktop-width viewport -> NavigationRail with the Dashboard tab selected
    // (selected tabs render the filled icon variant).
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('EasyVPN'), findsOneWidget);
    expect(find.byIcon(Icons.dashboard), findsOneWidget);
  });
}
