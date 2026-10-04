import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'psiphon/psiphon_page.dart';
import 'single_config/single_config_page.dart';
import 'warp/warp_page.dart';

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
      leading: const Icon(Icons.travel_explore),
      title: const Text('Psiphon'),
      subtitle: Text(
        fa
            ? 'اتصال رایگان؛ بعد از افزودن، از لیست سرورها انتخاب کنید'
            : 'Free tunnel; after adding, pick it from the servers list',
      ),
      widget: const PsiphonView(),
    ),
  ];
}
