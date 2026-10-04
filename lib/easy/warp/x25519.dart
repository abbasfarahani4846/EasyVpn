import 'dart:math';
import 'dart:typed_data';

/// X25519 (RFC 7748), used only to make WireGuard key pairs for WARP.
class X25519 {
  const X25519._();

  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _a24 = BigInt.from(121665);

  static Uint8List generatePrivateKey([Random? random]) {
    final rng = random ?? Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  static Uint8List publicKey(Uint8List privateKey) {
    final basePoint = Uint8List(32)..[0] = 9;
    return scalarMult(privateKey, basePoint);
  }

  static Uint8List scalarMult(Uint8List scalar, Uint8List uCoordinate) {
    final k = _clamp(scalar);
    final u = _decode(uCoordinate) & ((BigInt.one << 255) - BigInt.one);

    final x1 = u;
    var x2 = BigInt.one;
    var z2 = BigInt.zero;
    var x3 = u;
    var z3 = BigInt.one;
    var swap = 0;

    for (var t = 254; t >= 0; t--) {
      final kt = ((k >> t) & BigInt.one).toInt();
      swap ^= kt;
      if (swap == 1) {
        (x2, x3) = (x3, x2);
        (z2, z3) = (z3, z2);
      }
      swap = kt;

      final a = (x2 + z2) % _p;
      final aa = (a * a) % _p;
      final b = (x2 - z2) % _p;
      final bb = (b * b) % _p;
      final e = (aa - bb) % _p;
      final c = (x3 + z3) % _p;
      final d = (x3 - z3) % _p;
      final da = (d * a) % _p;
      final cb = (c * b) % _p;
      x3 = pow2(da + cb);
      z3 = (x1 * pow2(da - cb)) % _p;
      x2 = (aa * bb) % _p;
      z2 = (e * (aa + _a24 * e)) % _p;
    }
    if (swap == 1) {
      (x2, x3) = (x3, x2);
      (z2, z3) = (z3, z2);
    }
    final result = (x2 * z2.modPow(_p - BigInt.two, _p)) % _p;
    return _encode(result);
  }

  static BigInt pow2(BigInt v) => (v * v) % _p;

  static BigInt _clamp(Uint8List scalar) {
    final bytes = Uint8List.fromList(scalar);
    bytes[0] &= 248;
    bytes[31] &= 127;
    bytes[31] |= 64;
    return _decode(bytes);
  }

  static BigInt _decode(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  static Uint8List _encode(BigInt value) {
    final out = Uint8List(32);
    var v = value;
    for (var i = 0; i < 32; i++) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }
}
