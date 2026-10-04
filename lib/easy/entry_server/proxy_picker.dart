import 'dart:async';

import '../psiphon/psiphon_manager.dart';

/// Lets another screen borrow the Proxies page as a chooser: while a handler is
/// armed, tapping a proxy there reports its name instead of selecting it in
/// its group.
class EasyProxyPicker {
  const EasyProxyPicker._();

  static void Function(String proxyName)? _handler;

  static bool get isPicking => _handler != null;

  static void arm(void Function(String proxyName) handler) {
    _handler = handler;
  }

  static void disarm() {
    _handler = null;
  }

  /// Returns true when the tap was consumed by a picker.
  static bool tryPick(String proxyName) {
    // Every proxy tap passes here; Psiphon nodes pick the egress country.
    unawaited(PsiphonManager.noteSelection(proxyName));
    final handler = _handler;
    if (handler == null) return false;
    handler(proxyName);
    return true;
  }
}
