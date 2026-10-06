import 'package:fl_clash/easy/country_bypass/country_bypass_config.dart';
import 'package:fl_clash/easy/country_bypass/country_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> base() => {
    'rules': <String>['DOMAIN-SUFFIX,example.com,Proxy', 'MATCH,Proxy'],
    'rule-providers': <String, dynamic>{
      'mine': {'type': 'http', 'url': 'u'},
    },
  };

  test('no selection or unknown country leaves config untouched', () {
    final raw = base();
    expect(identical(CountryBypassConfig.apply(raw, null), raw), isTrue);
    expect(
      identical(
        CountryBypassConfig.apply(raw, const CountrySelection(code: 'zz')),
        raw,
      ),
      isTrue,
    );
  });

  test('iran adds domain and ip providers and DIRECT rules first', () {
    final out = CountryBypassConfig.apply(
      base(),
      const CountrySelection(code: 'ir'),
    );
    final providers = out['rule-providers'] as Map;
    expect(
      providers.keys,
      containsAll(['mine', 'easy-ir-domain', 'easy-ir-ip']),
    );
    expect(providers['easy-ir-domain']['behavior'], 'domain');
    expect(
      providers['easy-ir-domain']['proxy'],
      'DIRECT',
      reason: 'the core fetches providers through its rules; loopback must not',
    );
    expect(providers['easy-ir-domain']['format'], 'mrs');
    expect(
      providers['easy-ir-domain']['url'],
      'https://raw.githubusercontent.com/Chocolate4U/Iran-clash-rules/release/ir.mrs',
    );
    expect(providers['easy-ir-ip']['behavior'], 'ipcidr');
    expect(out['rules'], [
      'RULE-SET,easy-ir-domain,DIRECT',
      'RULE-SET,easy-ir-ip,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,example.com,Proxy',
      'MATCH,Proxy',
    ]);
  });

  test('mirror switches urls to jsDelivr', () {
    final out = CountryBypassConfig.apply(
      base(),
      const CountrySelection(code: 'ir', mirror: true),
    );
    final url = (out['rule-providers'] as Map)['easy-ir-ip']['url'] as String;
    expect(url, startsWith('https://cdn.jsdelivr.net/gh/Chocolate4U/'));
  });

  test('ip-only country ignores the domain option', () {
    final out = CountryBypassConfig.apply(
      base(),
      const CountrySelection(code: 'tr'),
    );
    expect((out['rule-providers'] as Map).keys, ['mine', 'easy-tr-ip']);
    expect(
      (out['rules'] as List).first,
      'RULE-SET,easy-tr-ip,DIRECT,no-resolve',
    );
    expect(
      CountryBypassConfig.providerNames(const CountrySelection(code: 'tr')),
      ['easy-tr-ip'],
    );
  });

  test('both options off changes nothing, input is never mutated', () {
    final raw = base();
    final out = CountryBypassConfig.apply(
      raw,
      const CountrySelection(code: 'ir', ip: false, domain: false),
    );
    expect(identical(out, raw), isTrue);
    CountryBypassConfig.apply(raw, const CountrySelection(code: 'cn'));
    expect(raw['rules'], hasLength(2));
    expect((raw['rule-providers'] as Map).keys, ['mine']);
  });

  test('catalog is well formed', () {
    final codes = CountryCatalog.all.map((c) => c.code).toList();
    expect(codes.toSet(), hasLength(codes.length));
    expect(CountryCatalog.byCode('ir')!.flag, '\u{1F1EE}\u{1F1F7}');
    for (final c in CountryCatalog.all) {
      expect(c.ip.url(mirror: false), endsWith('.mrs'));
    }
  });
}
