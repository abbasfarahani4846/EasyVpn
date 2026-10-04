import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The name of the server traffic currently leaves through, following the
/// first visible group down through nested groups.
String? easySelectedServer(WidgetRef ref) {
  final groups = ref.watch(visibleGroupsStateProvider).value;
  if (groups.isEmpty) return null;
  final byName = {for (final Group g in groups) g.name: g};
  String? name = ref.watch<String?>(
    selectedProxyNameProvider(groups.first.name),
  );
  for (var depth = 0; depth < 5; depth++) {
    final current = name;
    if (current == null) return null;
    final nested = byName[current];
    if (nested == null) return current;
    name = ref.watch<String?>(selectedProxyNameProvider(nested.name));
  }
  return name;
}
