import 'dart:async';

/// One event pushed by the Go core (state, stats, log, delay, ruleSync, subSync, crash).
class CoreEvent {
  const CoreEvent(this.type, this.payload);
  final String type;
  final dynamic payload;

  factory CoreEvent.fromJson(Map<String, dynamic> j) =>
      CoreEvent(j['type'] as String, j['payload']);
}

/// Error returned by a core method.
class CoreException implements Exception {
  CoreException(this.message);
  final String message;

  /// True for `unsupported_by_core:<cap>` errors (node needs another engine).
  bool get isUnsupported => message.contains('unsupported_by_core:');
  String? get capability {
    final m = RegExp(r'unsupported_by_core:(\w+)').firstMatch(message);
    return m?.group(1);
  }

  @override
  String toString() => message;
}

/// Thrown when no native core could be loaded (library/binary missing).
/// The UI shows "core unavailable" — it must never pretend to be connected.
class CoreUnavailable implements Exception {
  CoreUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'Core unavailable: $reason';
}

/// Transport between Dart and the Go core (in-process FFI or child process).
abstract class CoreTransport {
  /// Runs one RPC method and returns its decoded `result` object.
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]);

  /// Batched core events.
  Stream<List<CoreEvent>> get events;

  /// False for the placeholder used when no native core could be loaded.
  bool get isAvailable => true;

  Future<void> dispose();
}

/// Methods that may run for seconds and must not block state queries.
const heavyMethods = {
  'PingBatch',
  'SyncRuleSets',
  'FetchSubscription',
  'ParseContent',
  'Export',
  'BackupEncrypt',
  'BackupDecrypt',
  'Seal',
  'Open',
  'Start',
  'Stop',
  'SwitchNode',
};
