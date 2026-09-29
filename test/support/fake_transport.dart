import 'dart:async';
import 'dart:convert';

import 'package:easyvpn/core/bridge/core_bridge.dart';
import 'package:flutter_test/flutter_test.dart' show TestFailure;

/// In-memory stand-in for the Go core used by widget/database tests.
class FakeTransport implements CoreTransport {
  FakeTransport({this.handlers = const {}});
  final Map<
    String,
    FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> args)
  >
  handlers;
  final calls = <String>[];
  final _events = StreamController<List<CoreEvent>>.broadcast();

  void emit(String type, dynamic payload) =>
      _events.add([CoreEvent(type, payload)]);

  @override
  bool get isAvailable => true;

  @override
  Stream<List<CoreEvent>> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    final h = handlers[method];
    if (h != null) {
      try {
        return await h(args ?? const {});
      } catch (e) {
        if (e is CoreException || e is TestFailure) rethrow;
        throw CoreException('$e');
      }
    }
    switch (method) {
      case 'Seal':
        return {
          'items': [
            for (final s in (args!['items'] as List))
              base64.encode(utf8.encode(s as String)),
          ],
        };
      case 'Open':
        return {
          'items': [
            for (final s in (args!['items'] as List))
              utf8.decode(base64.decode(s as String)),
          ],
        };
      case 'Info':
        return {
          'core': 'fake',
          'version': '0',
          'capabilities': <String>[],
          'system_proxy': true,
        };
      case 'GetStats':
        return {};
      default:
        return {};
    }
  }

  @override
  Future<void> dispose() async => _events.close();
}
