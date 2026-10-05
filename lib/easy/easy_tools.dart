import 'package:material_ui/material_ui.dart';

import 'country_bypass/country_bypass_page.dart';
import 'endpoint_healer/endpoint_heal_item.dart';
import 'entry_server/entry_server_page.dart';

/// Entries the easy features add to the Tools > settings list.
const List<Widget> easySettingItems = [
  EasyEntryServerItem(),
  EasyCountryBypassItem(),
  EasyEndpointHealItem(),
];
