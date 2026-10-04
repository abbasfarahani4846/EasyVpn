import 'package:fl_clash/easy/home/dashboard_items.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config.dart';
import 'package:fl_clash/views/dashboard/widget_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('easy dashboard widgets survive saving and loading the layout', () {
    final saved = [
      DashboardWidget.easyConnect,
      DashboardWidget.networkDetection,
      DashboardWidget.easyRoute,
    ].map((w) => w.name).toList();
    expect(dashboardWidgetsSafeFormJson(saved), [
      DashboardWidget.easyConnect,
      DashboardWidget.networkDetection,
      DashboardWidget.easyRoute,
    ]);
  });

  test('every dashboard widget builds a grid item keyed by itself', () {
    for (final widget in DashboardWidget.values) {
      final item = widget.widget;
      expect(dashboardWidgetOf(item), widget);
    }
    expect(DashboardWidget.easyConnect.widget, same(easyConnectItem));
    expect(DashboardWidget.easyRoute.widget, same(easyRouteItem));
  });

  test('the full app setting round-trips with the easy widgets', () {
    final json = AppSettingProps.fromJson({
      'dashboardWidgets': ['easyConnect', 'tunButton', 'easyRoute'],
    }).toJson();
    expect(json['dashboardWidgets'], ['easyConnect', 'tunButton', 'easyRoute']);
  });
}
