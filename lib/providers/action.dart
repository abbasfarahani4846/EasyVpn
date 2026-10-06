import 'dart:async';
import 'dart:io';

import 'package:easy_vpn/common/boot_guard.dart';
import 'package:easy_vpn/common/common.dart';
import 'package:easy_vpn/common/system_dns.dart';
import 'package:easy_vpn/core/core.dart';
import 'package:easy_vpn/easy/easy_config.dart'; // EASY-HOOK
import 'package:easy_vpn/easy/endpoint_healer/profile_heal.dart';
import 'package:easy_vpn/database/database.dart';
import 'package:easy_vpn/enum/enum.dart';
import 'package:easy_vpn/models/models.dart';
import 'package:easy_vpn/plugins/app.dart';
import 'package:easy_vpn/plugins/service.dart';
import 'package:easy_vpn/providers/actions/system_exit.dart';
import 'package:easy_vpn/providers/providers.dart';
import 'package:easy_vpn/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show basename, join;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'actions/common.dart';
part 'actions/setup.dart';
part 'actions/backup.dart';
part 'actions/core.dart';
part 'actions/system.dart';
part 'actions/store.dart';
part 'actions/theme.dart';
part 'actions/proxies.dart';
part 'actions/profiles.dart';
part 'actions/scripts.dart';
part 'actions/clash_providers.dart';
part 'actions/geo_resource.dart';
part 'actions/updating.dart';
part 'generated/action.g.dart';
