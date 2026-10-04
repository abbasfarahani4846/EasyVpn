import 'country_catalog.dart';

class CountrySelection {
  final String code;
  final bool ip;
  final bool domain;
  final bool mirror;

  const CountrySelection({
    required this.code,
    this.ip = true,
    this.domain = true,
    this.mirror = false,
  });

  CountrySelection copyWith({
    String? code,
    bool? ip,
    bool? domain,
    bool? mirror,
  }) => CountrySelection(
    code: code ?? this.code,
    ip: ip ?? this.ip,
    domain: domain ?? this.domain,
    mirror: mirror ?? this.mirror,
  );

  Map<String, Object?> toJson() => {
    'code': code,
    'ip': ip,
    'domain': domain,
    'mirror': mirror,
  };

  static CountrySelection? fromJson(Object? json) {
    if (json is! Map || json['code'] is! String) return null;
    return CountrySelection(
      code: json['code'] as String,
      ip: json['ip'] != false,
      domain: json['domain'] != false,
      mirror: json['mirror'] == true,
    );
  }
}

/// Adds the chosen country's IP and domain lists as rule providers and puts
/// DIRECT rules for them ahead of the profile's own rules, so that country's
/// traffic never goes through the proxy.
class CountryBypassConfig {
  const CountryBypassConfig._();

  static const updateInterval = 86400;

  static List<String> providerNames(CountrySelection selection) {
    final country = CountryCatalog.byCode(selection.code);
    if (country == null) return const [];
    return [
      if (selection.domain && country.domain != null) country.domainProvider,
      if (selection.ip) country.ipProvider,
    ];
  }

  static Map<String, dynamic> apply(
    Map<String, dynamic> rawConfig,
    CountrySelection? selection,
  ) {
    final country = CountryCatalog.byCode(selection?.code);
    if (selection == null || country == null) return rawConfig;
    final useDomain = selection.domain && country.domain != null;
    if (!useDomain && !selection.ip) return rawConfig;

    final config = Map<String, dynamic>.from(rawConfig);
    final providers = Map<String, dynamic>.from(
      (config['rule-providers'] as Map?) ?? const {},
    );
    final rules = <String>[];

    if (useDomain) {
      providers[country.domainProvider] = _provider(
        'domain',
        country.domain!.url(mirror: selection.mirror),
      );
      rules.add('RULE-SET,${country.domainProvider},DIRECT');
    }
    if (selection.ip) {
      providers[country.ipProvider] = _provider(
        'ipcidr',
        country.ip.url(mirror: selection.mirror),
      );
      rules.add('RULE-SET,${country.ipProvider},DIRECT,no-resolve');
    }

    config['rule-providers'] = providers;
    config['rules'] = [
      ...rules,
      for (final r in (config['rules'] as List? ?? const [])) r,
    ];
    return config;
  }

  static Map<String, Object?> _provider(String behavior, String url) => {
    'type': 'http',
    'behavior': behavior,
    'format': 'mrs',
    'url': url,
    'interval': updateInterval,
  };
}
