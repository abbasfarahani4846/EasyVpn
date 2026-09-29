import 'core_transport.dart';

/// Used when no native core could be loaded. Every call fails loudly; the UI
/// shows a "core unavailable" banner instead of faking a connection.
class UnavailableTransport implements CoreTransport {
  UnavailableTransport(this.reason);
  final String reason;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) => Future.error(CoreUnavailable(reason));

  @override
  Stream<List<CoreEvent>> get events => const Stream.empty();

  @override
  bool get isAvailable => false;

  String get unavailableReason => reason;

  @override
  Future<void> dispose() async {}
}
