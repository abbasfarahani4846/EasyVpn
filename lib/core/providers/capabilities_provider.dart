import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';

/// Node capabilities (xhttp, mlkem, tcphttp, openvpn, ...) the running core
/// build can honor — the union of all bundled engines. Nodes requiring
/// anything else are flagged in the UI instead of failing at connect time.
final supportedCapsProvider = FutureProvider<Set<String>>((ref) async {
  final core = ref.read(envProvider).core;
  if (!core.isAvailable) return const <String>{};
  try {
    final info = await core.info();
    return ((info['capabilities'] as List?) ?? const []).cast<String>().toSet();
  } catch (_) {
    return const <String>{};
  }
});
