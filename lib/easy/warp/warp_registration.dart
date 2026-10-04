import 'dart:convert';

import 'package:dio/dio.dart';

import 'x25519.dart';

class WarpException implements Exception {
  final String message;

  const WarpException(this.message);

  @override
  String toString() => message;
}

/// Registers an anonymous Cloudflare WARP device (the same call the official
/// app makes) and turns the answer into a mihomo `wireguard` proxy.
class WarpRegistration {
  const WarpRegistration._();

  static const _endpoint = 'https://api.cloudflareclient.com/v0a2158/reg';

  static Future<Map<String, Object?>> register({
    String name = 'WARP',
    Dio? client,
  }) async {
    final privateKey = X25519.generatePrivateKey();
    final publicKey = X25519.publicKey(privateKey);
    final dio = client ?? Dio();
    final Response<dynamic> response;
    try {
      response = await dio.post<dynamic>(
        _endpoint,
        data: jsonEncode({
          'key': base64.encode(publicKey),
          'install_id': '',
          'fcm_token': '',
          'tos': DateTime.now().toUtc().toIso8601String(),
          'type': 'Android',
          'model': 'PC',
          'locale': 'en_US',
        }),
        options: Options(
          headers: {
            'User-Agent': 'okhttp/3.12.1',
            'CF-Client-Version': 'a-6.10-2158',
            'Content-Type': 'application/json; charset=UTF-8',
          },
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
    } on DioException catch (e) {
      throw WarpException(
        'WARP registration failed: ${e.response?.statusCode ?? e.type.name}',
      );
    }
    final data = response.data;
    final json = data is String ? jsonDecode(data) : data;
    if (json is! Map<String, dynamic>) {
      throw const WarpException('WARP registration returned unexpected data');
    }
    return buildProxy(
      privateKey: base64.encode(privateKey),
      response: json,
      name: name,
    );
  }

  static Map<String, Object?> buildProxy({
    required String privateKey,
    required Map<String, dynamic> response,
    required String name,
  }) {
    try {
      final config = response['config'] as Map<String, dynamic>;
      final peer = (config['peers'] as List).first as Map<String, dynamic>;
      final addresses =
          (config['interface'] as Map<String, dynamic>)['addresses']
              as Map<String, dynamic>;
      final host = (peer['endpoint'] as Map<String, dynamic>)['host'] as String;
      final hostName = host.contains(':')
          ? host.substring(0, host.lastIndexOf(':'))
          : host;
      final port = host.contains(':')
          ? int.parse(host.substring(host.lastIndexOf(':') + 1))
          : 2408;
      final clientId = config['client_id'] as String?;
      return {
        'name': name,
        'type': 'wireguard',
        'server': hostName,
        'port': port,
        'ip': addresses['v4'],
        if (addresses['v6'] != null) 'ipv6': addresses['v6'],
        'private-key': privateKey,
        'public-key': peer['public_key'],
        'allowed-ips': ['0.0.0.0/0', '::/0'],
        if (clientId != null && clientId.isNotEmpty)
          'reserved': base64.decode(clientId).take(3).toList(),
        'udp': true,
        'mtu': 1280,
        'remote-dns-resolve': true,
        'dns': ['1.1.1.1', '1.0.0.1'],
      };
    } catch (e) {
      if (e is WarpException) rethrow;
      throw const WarpException('WARP registration returned unexpected data');
    }
  }
}
