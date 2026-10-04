import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../entry_server/route_card.dart';
import 'easy_connect_card.dart';

/// The easy widgets as dashboard grid items, so FlClash's own edit mode can
/// move and remove them like any other widget.
const GridItem easyConnectItem = GridItem(
  key: ValueKey(DashboardWidget.easyConnect),
  crossAxisCellCount: 8,
  child: SizedBox(height: 330, child: EasyConnectCard()),
);

const GridItem easyRouteItem = GridItem(
  key: ValueKey(DashboardWidget.easyRoute),
  crossAxisCellCount: 8,
  child: SizedBox(height: 112, child: EasyRouteCard(alwaysShow: true)),
);
