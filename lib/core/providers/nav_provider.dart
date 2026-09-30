import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the selected top-level destination (so any widget can navigate).
class NavNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void go(int i) => state = i;
}

final navProvider = NotifierProvider<NavNotifier, int>(NavNotifier.new);

class Dest {
  static const dashboard = 0;
  static const proxies = 1;
  static const profiles = 2;
  static const routing = 3;
  static const settings = 4;
  static const tools = 5;
}
