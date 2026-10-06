import 'package:easy_vpn/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'psiphon/psiphon_add.dart';
import 'single_config/single_config_page.dart';
import 'warp/warp_page.dart';
import 'windscribe/windscribe_page.dart';

/// Entries the easy features add to the "Add profile" page.
List<Widget> easyAddProfileItems(BuildContext context) {
  final fa = Localizations.localeOf(context).languageCode == 'fa';
  return [
    ListItem(
      leading: const Icon(Icons.add_link),
      title: Text(fa ? 'کانفیگ تکی' : 'Single config'),
      subtitle: Text(
        fa
            ? 'افزودن لینک یا کانفیگ به پروفایل پیش‌فرض'
            : 'Add a link or config to the default profile',
      ),
      onTap: showSingleConfigPage,
    ),
    ListItem.open(
      leading: const Icon(Icons.cloud),
      title: const Text('Cloudflare WARP'),
      subtitle: Text(
        fa
            ? 'ساخت حساب رایگان WARP و افزودن به پروفایل'
            : 'Create a free WARP account and add it to a profile',
      ),
      widget: const WarpView(),
    ),
    ListItem.open(
      leading: const Icon(Icons.vpn_key_outlined),
      title: const Text('Windscribe / OpenVPN / WireGuard'),
      subtitle: Text(
        fa
            ? 'افزودن کانفیگ‌های .ovpn و .conf (مثل Config Generator سایت Windscribe)'
            : 'Add .ovpn and .conf files (like Windscribe\'s Config Generator)',
      ),
      widget: const WindscribeView(),
    ),
    const EasyPsiphonAddItem(),
  ];
}
