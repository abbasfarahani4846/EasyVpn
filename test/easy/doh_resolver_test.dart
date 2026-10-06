import 'package:easy_vpn/easy/windscribe/doh_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private and tampered ranges are bogons, real ones are not', () {
    for (final ip in [
      '10.10.34.36',
      '10.0.0.1',
      '192.168.1.1',
      '172.16.5.5',
      '172.31.255.255',
      '127.0.0.1',
      '169.254.1.1',
      '100.64.0.1',
      '198.18.0.5',
      '0.0.0.0',
    ]) {
      expect(DohResolver.isBogon(ip), isTrue, reason: ip);
    }
    for (final ip in ['135.136.3.3', '8.8.8.8', '172.32.0.1', '100.63.0.1']) {
      expect(DohResolver.isBogon(ip), isFalse, reason: ip);
    }
  });

  test('parses a DoH answer and ignores tampered or non-A records', () {
    expect(
      DohResolver.parseAnswer(
        '{"Answer":[{"type":5,"data":"alias."},'
        '{"type":1,"data":"10.10.34.36"},{"type":1,"data":"135.136.3.3"}]}',
      ),
      '135.136.3.3',
    );
    expect(
      DohResolver.parseAnswer('{"Answer":[{"type":1,"data":"10.10.34.36"}]}'),
      isNull,
    );
    expect(DohResolver.parseAnswer('{"Status":3}'), isNull);
    expect(DohResolver.parseAnswer('not json'), isNull);
  });

  test('an address that is already an IP is kept as is', () async {
    expect(await DohResolver.resolve('135.136.3.3'), '135.136.3.3');
  });
}
