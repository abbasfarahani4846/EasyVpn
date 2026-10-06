import 'dart:convert';

import 'package:easy_vpn/easy/single_config/subscription_converter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const uuid = '11111111-2222-3333-4444-555555555555';
  final links = [
    'vless://$uuid@a.example.com:443?security=tls&type=ws&path=%2Fp#One',
    'trojan://pass@b.example.com:443#Two',
  ].join('\n');

  test('a base64 list of share links becomes a profile with its servers', () {
    final yaml = SubscriptionConverter.toClashYaml(
      base64Encode(utf8.encode(links)),
    );
    expect(yaml, isNotNull);
    final doc = loadYaml(yaml!) as YamlMap;
    expect((doc['proxies'] as YamlList).map((p) => p['name']), ['One', 'Two']);
    expect(doc['rules'], isNotEmpty);
  });

  test('plain links convert as well', () {
    final doc = loadYaml(SubscriptionConverter.toClashYaml(links)!) as YamlMap;
    expect(doc['proxies'], hasLength(2));
  });

  test('a Clash config or text without servers is left alone', () {
    expect(
      SubscriptionConverter.toClashYaml('mixed-port: 7890\nproxies: []\n'),
      isNull,
    );
    expect(
      SubscriptionConverter.toClashYaml('proxy-groups:\n- name: a\n'),
      isNull,
    );
    expect(SubscriptionConverter.toClashYaml('hello world'), isNull);
    expect(SubscriptionConverter.toClashYaml(''), isNull);
  });
}
