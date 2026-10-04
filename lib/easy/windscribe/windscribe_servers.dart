import 'dart:convert';

import 'package:dio/dio.dart';

class WindscribeCity {
  final String country;
  final String countryCode;
  final String city;
  final String nick;
  final String groupId;
  final bool pro;
  final String wgPublicKey;

  /// A node address when the list carries one, else the group's hostname.
  final String endpoint;

  const WindscribeCity({
    required this.country,
    required this.countryCode,
    required this.city,
    required this.nick,
    required this.groupId,
    required this.pro,
    required this.wgPublicKey,
    required this.endpoint,
  });

  WindscribeCity withPro(bool value) => WindscribeCity(
    country: country,
    countryCode: countryCode,
    city: city,
    nick: nick,
    groupId: groupId,
    pro: value,
    wgPublicKey: wgPublicKey,
    endpoint: endpoint,
  );

  String get flag => countryCode.length == 2
      ? String.fromCharCodes(
          countryCode.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
        )
      : '';

  String get label {
    final place = nick.isEmpty ? city : '$city ($nick)';
    return '${flag.isEmpty ? '' : '$flag '}$country · $place';
  }
}

/// Windscribe's public server list (no login needed) turned into WireGuard
/// peers, so one downloaded WireGuard config can serve every location.
class WindscribeServers {
  const WindscribeServers._();

  /// Every city (marked pro) and the list that marks which ones are free.
  static const listUrl = 'https://assets.windscribe.com/serverlist/mob-v2/1/1';
  static const freeListUrl =
      'https://assets.windscribe.com/serverlist/mob-v2/0/1';

  static Future<List<WindscribeCity>> fetch({Dio? client}) async {
    final dio = client ?? Dio();
    final all = parse(await _get(dio, listUrl));
    // The full list marks every city pro; only the free list says which are free.
    final free = freeGroupIds(await _get(dio, freeListUrl));
    return [for (final c in all) c.withPro(!free.contains(c.groupId))];
  }

  static Future<Map<String, dynamic>> _get(Dio dio, String url) async {
    final Response<dynamic> response;
    try {
      response = await dio.get<dynamic>(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw Exception(
        'Could not download the Windscribe server list '
        '(${e.response?.statusCode ?? e.type.name})',
      );
    }
    final body = response.data;
    return jsonDecode(body is String ? body : jsonEncode(body))
        as Map<String, dynamic>;
  }

  /// Ids of the cities a free account may use (`pro` is not 1 in that list).
  static Set<String> freeGroupIds(Map<String, dynamic> json) => {
    for (final c in parse(json))
      if (!c.pro) c.groupId,
  };

  static List<WindscribeCity> parse(Map<String, dynamic> json) {
    final cities = <WindscribeCity>[];
    for (final location in (json['data'] as List? ?? const [])) {
      if (location is! Map) continue;
      if ('${location['status']}' == '0') continue;
      for (final group in (location['groups'] as List? ?? const [])) {
        if (group is! Map) continue;
        final key = '${group['wg_pubkey'] ?? ''}';
        if (key.isEmpty) continue;
        String endpoint = '${group['wg_endpoint'] ?? ''}';
        for (final node in (group['nodes'] as List? ?? const [])) {
          final ip = node is Map ? '${node['ip3'] ?? ''}' : '';
          if (ip.isNotEmpty) {
            endpoint = ip;
            break;
          }
        }
        if (endpoint.isEmpty) continue;
        cities.add(
          WindscribeCity(
            country: '${location['name'] ?? ''}',
            countryCode: '${location['country_code'] ?? ''}',
            city: '${group['city'] ?? ''}',
            nick: '${group['nick'] ?? ''}',
            groupId: '${group['id'] ?? ''}',
            pro: '${group['pro']}' == '1',
            wgPublicKey: key,
            endpoint: endpoint,
          ),
        );
      }
    }
    return cities;
  }

  /// One WireGuard proxy per city, all sharing the account-level material
  /// (private key, address, preshared key, DNS) of [wgProxy], which came from
  /// a config the user downloaded. Free accounts get only the free cities.
  static List<Map<String, Object?>> expand(
    Map<String, Object?> wgProxy,
    List<WindscribeCity> cities, {
    required bool proAccount,
    int port = 443,
  }) {
    final names = <String>{};
    final result = <Map<String, Object?>>[];
    for (final city in cities) {
      if (city.pro && !proAccount) continue;
      var name = city.label;
      if (!names.add(name)) {
        name = '$name #${city.groupId}';
        names.add(name);
      }
      result.add({
        ...wgProxy,
        'name': name,
        'server': city.endpoint,
        'port': port,
        'public-key': city.wgPublicKey,
      });
    }
    return result;
  }
}
