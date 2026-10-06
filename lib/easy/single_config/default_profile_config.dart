import 'package:easy_vpn/common/yaml.dart';
import 'package:yaml/yaml.dart';

/// Pure helpers that keep the default profile's YAML in sync with its proxies.
class DefaultProfileConfig {
  const DefaultProfileConfig._();

  static const label = 'Default';
  static const selectGroup = 'Proxy';
  static const autoGroup = 'Fastest';
  static const _testUrl = 'https://www.gstatic.com/generate_204';

  static List<Map<String, Object?>> readProxies(String content) {
    if (content.trim().isEmpty) return [];
    final doc = _plain(loadYaml(content));
    if (doc is! Map || doc['proxies'] is! List) return [];
    return [
      for (final item in doc['proxies'] as List)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }

  /// Returns [existing] plus the entries of [added] that are not duplicates,
  /// renaming a clashing name instead of dropping the proxy.
  static ({List<Map<String, Object?>> proxies, int added, int skipped}) merge(
    List<Map<String, Object?>> existing,
    List<Map<String, Object?>> added,
  ) {
    final result = [...existing];
    final names = {for (final p in result) '${p['name']}'};
    final identities = {for (final p in result) _identity(p)};
    var addedCount = 0;
    var skipped = 0;
    for (final proxy in added) {
      if (!identities.add(_identity(proxy))) {
        skipped++;
        continue;
      }
      var name = '${proxy['name']}';
      if (names.contains(name)) {
        var i = 2;
        while (names.contains('$name ($i)')) {
          i++;
        }
        name = '$name ($i)';
      }
      names.add(name);
      result.add({...proxy, 'name': name});
      addedCount++;
    }
    return (proxies: result, added: addedCount, skipped: skipped);
  }

  static String build(
    List<Map<String, Object?>> proxies, {
    bool urlTest = true,
  }) {
    final names = [for (final p in proxies) '${p['name']}'];
    return yaml.encode({
      'proxies': proxies,
      'proxy-groups': [
        {
          'name': selectGroup,
          'type': 'select',
          'proxies': [if (urlTest) autoGroup, ...names],
        },
        if (urlTest)
          {
            'name': autoGroup,
            'type': 'url-test',
            'url': _testUrl,
            'interval': 300,
            'tolerance': 50,
            'proxies': names,
          },
      ],
      'rules': ['MATCH,$selectGroup'],
    });
  }

  static String _identity(Map<String, Object?> proxy) {
    final copy = Map<String, Object?>.from(proxy)..remove('name');
    final keys = copy.keys.toList()..sort();
    return keys.map((k) => '$k=${copy[k]}').join('&');
  }

  static Object? _plain(Object? node) {
    if (node is YamlMap) {
      return {for (final e in node.entries) '${e.key}': _plain(e.value)};
    }
    if (node is YamlList) return [for (final e in node) _plain(e)];
    return node;
  }
}
