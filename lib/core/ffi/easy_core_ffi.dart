import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Native function typedefs
typedef InitCoreC = Void Function(Pointer<Utf8> cacheDir);
typedef InitCoreDart = void Function(Pointer<Utf8> cacheDir);

typedef StartProxyC = Int32 Function(Pointer<Utf8> nodeJson, Int32 tun);
typedef StartProxyDart = int Function(Pointer<Utf8> nodeJson, int tun);

typedef StopProxyC = Int32 Function();
typedef StopProxyDart = int Function();

typedef SwitchProxyC = Int32 Function(Pointer<Utf8> nodeJson);
typedef SwitchProxyDart = int Function(Pointer<Utf8> nodeJson);

typedef GetStatsJSONC = Pointer<Utf8> Function();
typedef GetStatsJSONDart = Pointer<Utf8> Function();

typedef ParseSubscriptionC = Pointer<Utf8> Function(Pointer<Utf8> content);
typedef ParseSubscriptionDart = Pointer<Utf8> Function(Pointer<Utf8> content);

typedef TestBatchPingC = Pointer<Utf8> Function(Pointer<Utf8> nodesJson);
typedef TestBatchPingDart = Pointer<Utf8> Function(Pointer<Utf8> nodesJson);

typedef SetCountryC = Void Function(Pointer<Utf8> code);
typedef SetCountryDart = void Function(Pointer<Utf8> code);

typedef SetRoutingModeC = Void Function(Pointer<Utf8> mode);
typedef SetRoutingModeDart = void Function(Pointer<Utf8> mode);

typedef FreeStringC = Void Function(Pointer<Utf8> str);
typedef FreeStringDart = void Function(Pointer<Utf8> str);

class EasyCoreFFI {
  static final EasyCoreFFI instance = EasyCoreFFI._internal();
  DynamicLibrary? _lib;
  bool _isLoaded = false;

  InitCoreDart? _initCore;
  StartProxyDart? _startProxy;
  StopProxyDart? _stopProxy;
  SwitchProxyDart? _switchProxy;
  GetStatsJSONDart? _getStatsJSON;
  ParseSubscriptionDart? _parseSubscription;
  TestBatchPingDart? _testBatchPing;
  SetCountryDart? _setCountry;
  SetRoutingModeDart? _setRoutingMode;
  FreeStringDart? _freeString;

  EasyCoreFFI._internal();

  bool get isLoaded => _isLoaded;

  void initialize(String cacheDir) {
    try {
      _lib = _loadLibrary();
      if (_lib != null) {
        _initCore = _lib!.lookupFunction<InitCoreC, InitCoreDart>('InitCore');
        _startProxy = _lib!.lookupFunction<StartProxyC, StartProxyDart>('StartProxy');
        _stopProxy = _lib!.lookupFunction<StopProxyC, StopProxyDart>('StopProxy');
        _switchProxy = _lib!.lookupFunction<SwitchProxyC, SwitchProxyDart>('SwitchProxy');
        _getStatsJSON = _lib!.lookupFunction<GetStatsJSONC, GetStatsJSONDart>('GetStatsJSON');
        _parseSubscription = _lib!.lookupFunction<ParseSubscriptionC, ParseSubscriptionDart>('ParseSubscription');
        _testBatchPing = _lib!.lookupFunction<TestBatchPingC, TestBatchPingDart>('TestBatchPing');
        _setCountry = _lib!.lookupFunction<SetCountryC, SetCountryDart>('SetCountry');
        _setRoutingMode = _lib!.lookupFunction<SetRoutingModeC, SetRoutingModeDart>('SetRoutingMode');
        _freeString = _lib!.lookupFunction<FreeStringC, FreeStringDart>('FreeString');

        final dirPtr = cacheDir.toNativeUtf8();
        _initCore!(dirPtr);
        calloc.free(dirPtr);
        _isLoaded = true;
      }
    } catch (e) {
      // Dynamic library not compiled yet, fallback to Dart emulator mode
      _isLoaded = false;
    }
  }

  DynamicLibrary? _loadLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('easycore.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libeasycore.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libeasycore.dylib');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libeasycore.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    return null;
  }

  int startProxy(Map<String, dynamic> node, bool tun) {
    if (!_isLoaded || _startProxy == null) return 0; // Simulated success in stub mode
    final jsonStr = jsonEncode(node).toNativeUtf8();
    final res = _startProxy!(jsonStr, tun ? 1 : 0);
    calloc.free(jsonStr);
    return res;
  }

  int stopProxy() {
    if (!_isLoaded || _stopProxy == null) return 0;
    return _stopProxy!();
  }

  int switchProxy(Map<String, dynamic> node) {
    if (!_isLoaded || _switchProxy == null) return 0;
    final jsonStr = jsonEncode(node).toNativeUtf8();
    final res = _switchProxy!(jsonStr);
    calloc.free(jsonStr);
    return res;
  }

  Map<String, dynamic> getStats() {
    if (!_isLoaded || _getStatsJSON == null || _freeString == null) {
      return {
        'upload_speed': 0,
        'download_speed': 0,
        'total_upload': 0,
        'total_download': 0,
        'connections': 0,
      };
    }
    final ptr = _getStatsJSON!();
    final str = ptr.toDartString();
    _freeString!(ptr);
    try {
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> parseSubscription(String content) {
    if (!_isLoaded || _parseSubscription == null || _freeString == null) {
      // Fallback simple Dart parser if native library is absent
      return _fallbackDartParser(content);
    }
    final contentPtr = content.toNativeUtf8();
    final resPtr = _parseSubscription!(contentPtr);
    calloc.free(contentPtr);
    final resStr = resPtr.toDartString();
    _freeString!(resPtr);
    try {
      return jsonDecode(resStr) as Map<String, dynamic>;
    } catch (_) {
      return {'error': 'Failed to parse JSON response', 'nodes': []};
    }
  }

  List<dynamic> testBatchPing(List<Map<String, dynamic>> nodes) {
    if (!_isLoaded || _testBatchPing == null || _freeString == null) {
      return nodes.map((n) => {'node_id': n['id'], 'latency_ms': 45 + (n['port'] ?? 443) % 150}).toList();
    }
    final jsonPtr = jsonEncode(nodes).toNativeUtf8();
    final resPtr = _testBatchPing!(jsonPtr);
    calloc.free(jsonPtr);
    final resStr = resPtr.toDartString();
    _freeString!(resPtr);
    try {
      return jsonDecode(resStr) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  void setCountry(String code) {
    if (!_isLoaded || _setCountry == null) return;
    final ptr = code.toNativeUtf8();
    _setCountry!(ptr);
    calloc.free(ptr);
  }

  void setRoutingMode(String mode) {
    if (!_isLoaded || _setRoutingMode == null) return;
    final ptr = mode.toNativeUtf8();
    _setRoutingMode!(ptr);
    calloc.free(ptr);
  }

  Map<String, dynamic> _fallbackDartParser(String content) {
    final lines = content.split('\n');
    final nodes = <Map<String, dynamic>>[];
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final uri = Uri.tryParse(line);
      if (uri != null && uri.hasScheme) {
        nodes.add({
          'id': line.hashCode.toString(),
          'name': uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : '${uri.scheme}-${uri.host}:${uri.port}',
          'type': uri.scheme,
          'server': uri.host,
          'port': uri.port > 0 ? uri.port : 443,
          'latency_ms': -1,
          'raw_config': line,
        });
      }
    }
    return {'error': '', 'nodes': nodes};
  }
}
