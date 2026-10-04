import 'package:fl_clash/easy/psiphon/psiphon_bypass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Psiphon process is sent DIRECT before every other rule', () {
    final out = PsiphonBypass.apply({
      'rules': ['DOMAIN-SUFFIX,example.com,Proxy', 'MATCH,Proxy'],
    });
    expect(out['rules'], [
      'PROCESS-NAME,psiphon-tunnel-core-i686.exe,DIRECT',
      'DOMAIN-SUFFIX,example.com,Proxy',
      'MATCH,Proxy',
    ]);
  });

  test('applying twice does not duplicate the rule; empty rules work', () {
    final once = PsiphonBypass.apply({'proxies': []});
    expect(once['rules'], [PsiphonBypass.rule]);
    final twice = PsiphonBypass.apply(once);
    expect(twice['rules'], [PsiphonBypass.rule]);
  });
}
