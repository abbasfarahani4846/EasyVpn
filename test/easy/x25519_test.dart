import 'dart:typed_data';

import 'package:fl_clash/easy/warp/x25519.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
]);

String toHex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('RFC 7748 section 5.2 test vector 1', () {
    final out = X25519.scalarMult(
      hex('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4'),
      hex('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c'),
    );
    expect(
      toHex(out),
      'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552',
    );
  });

  test('RFC 7748 section 6.1 Diffie-Hellman', () {
    final alicePriv = hex(
      '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
    );
    final bobPriv = hex(
      '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
    );
    final alicePub = X25519.publicKey(alicePriv);
    final bobPub = X25519.publicKey(bobPriv);
    expect(
      toHex(alicePub),
      '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a',
    );
    expect(
      toHex(bobPub),
      'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f',
    );
    final shared = toHex(X25519.scalarMult(alicePriv, bobPub));
    expect(shared, '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');
    expect(toHex(X25519.scalarMult(bobPriv, alicePub)), shared);
  });

  test('generated keys are 32 bytes and differ', () {
    final a = X25519.generatePrivateKey();
    final b = X25519.generatePrivateKey();
    expect(a, hasLength(32));
    expect(a, isNot(b));
    expect(X25519.publicKey(a), hasLength(32));
  });
}
