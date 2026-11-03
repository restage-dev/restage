import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// Verifies an Ed25519 [signature] by the 32-byte [publicKey] over [message].
///
/// Accepts exactly what libsodium's `crypto_sign_verify_detached` accepts:
/// cofactorless (`[S]B = R + [k]A` compared by encoding), S below the group
/// order, canonical encodings of A and R, and neither A nor R of small order.
/// Variable time: it handles only public data.
bool ed25519Verify(
    List<int> publicKey, List<int> message, List<int> signature) {
  if (!_wellFormed(publicKey, message, signature)) return false;
  if (identical(0, 0.0)) {
    return _BigVerify.verify(publicKey, message, signature);
  }
  return _FastVerify.verify(publicKey, message, signature);
}

// Exact lengths, and every element a byte.
bool _wellFormed(List<int> publicKey, List<int> message, List<int> signature) =>
    publicKey.length == 32 &&
    signature.length == 64 &&
    publicKey.every(_isByte) &&
    signature.every(_isByte) &&
    message.every(_isByte);

bool _isByte(int value) => value >= 0 && value <= 255;

/// The BigInt arithmetic web builds use, for tests on the VM.
@visibleForTesting
bool ed25519VerifyReference(
        List<int> publicKey, List<int> message, List<int> signature) =>
    _wellFormed(publicKey, message, signature) &&
    _BigVerify.verify(publicKey, message, signature);

/// Signs [message] with the key derived from the 32-byte [seed]; returns the
/// public key and the signature. Variable time, so for tests only.
(Uint8List, Uint8List) ed25519SignForTesting(
    List<int> seed, List<int> message) {
  final h = crypto.sha512.convert(seed).bytes;
  final a = Uint8List.fromList(h.sublist(0, 32));
  a[0] &= 248;
  a[31] &= 127;
  a[31] |= 64;
  final scalarA = _fromLe(a) % _l;
  Uint8List baseMultiple(BigInt scalar) => identical(0, 0.0)
      ? _BigVerify.baseMultiple(scalar)
      : _FastVerify.baseMultiple(_toLe32(scalar));
  final publicKey = baseMultiple(scalarA);
  final r =
      _fromLe(crypto.sha512.convert([...h.sublist(32), ...message]).bytes) % _l;
  final encodedR = baseMultiple(r);
  final k = _fromLe(
        crypto.sha512.convert([...encodedR, ...publicKey, ...message]).bytes,
      ) %
      _l;
  final s = (r + k * scalarA) % _l;
  return (publicKey, Uint8List.fromList([...encodedR, ..._toLe32(s)]));
}

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _l = (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');

BigInt _fromLe(List<int> bytes) {
  var result = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

Uint8List _toLe32(BigInt value) {
  final out = Uint8List(32);
  var v = value;
  for (var i = 0; i < 32; i++) {
    out[i] = (v & BigInt.from(255)).toInt();
    v = v >> 8;
  }
  return out;
}

/// h = SHA-512(R || A || M) mod L, or null when S is not below L.
(Uint8List, Uint8List)? _scalars(
    List<int> publicKey, List<int> message, List<int> signature) {
  final s = _fromLe(signature.sublist(32, 64));
  if (s >= _l) return null;
  final digest = crypto.sha512
      .convert([...signature.sublist(0, 32), ...publicKey, ...message]).bytes;
  return (_toLe32(_fromLe(digest) % _l), _toLe32(s));
}

// Field elements mod 2^255 - 19 in ten signed limbs of 26 and 25 bits.
typedef _Fe = Int64List;

_Fe _fe() => Int64List(10);

abstract final class _FastVerify {
  static final _Fe _d = _feFromBig(
      (_p - BigInt.from(121665)) * BigInt.from(121666).modInverse(_p) % _p);
  static final _Fe _d2 = _feFromBig(BigInt.two *
      (_p - BigInt.from(121665)) *
      BigInt.from(121666).modInverse(_p) %
      _p);
  static final _Fe _sqrtM1 =
      _feFromBig(BigInt.two.modPow((_p - BigInt.one) >> 2, _p));
  static final List<_Point> _baseOdd = _oddMultiples(_basePoint());

  static _Fe _feFromBig(BigInt value) => _feFromBytes(_toLe32(value));

  static _Point _basePoint() {
    final y = BigInt.from(4) * BigInt.from(5).modInverse(_p) % _p;
    final bytes = _toLe32(y);
    return _decompress(bytes)!;
  }

  static bool verify(
      List<int> publicKey, List<int> message, List<int> signature) {
    final scalars = _scalars(publicKey, message, signature);
    if (scalars == null) return false;
    final a = _decompress(publicKey);
    if (a == null || _hasSmallOrder(a)) return false;
    final r = _decompress(signature.sublist(0, 32));
    if (r == null || _hasSmallOrder(r)) return false;
    // -A, so the sum below is [s]B - [h]A.
    _neg(a.x, a.x);
    _neg(a.t, a.t);
    final encoded = _encode(_doubleScalarMult(scalars.$1, a, scalars.$2));
    for (var i = 0; i < 32; i++) {
      if (encoded[i] != signature[i]) return false;
    }
    return true;
  }

  // Whether [8]p is the identity.
  static bool _hasSmallOrder(_Point p) {
    final q = _Point.zero();
    _double(q, p);
    _double(q, q);
    _double(q, q);
    final t = _fe();
    _sub(t, q.y, q.z);
    return _isZero(q.x) && _isZero(t);
  }

  static Uint8List baseMultiple(List<int> scalar) {
    final identity = _Point.zero();
    return _encode(_doubleScalarMult(Uint8List(32), identity, scalar));
  }

  static _Fe _feFromBytes(List<int> s) {
    int load3(int i) => s[i] | (s[i + 1] << 8) | (s[i + 2] << 16);
    int load4(int i) => load3(i) | (s[i + 3] << 24);
    final h = _fe();
    h[0] = load4(0);
    h[1] = load3(4) << 6;
    h[2] = load3(7) << 5;
    h[3] = load3(10) << 3;
    h[4] = load3(13) << 2;
    h[5] = load4(16);
    h[6] = load3(20) << 7;
    h[7] = load3(23) << 5;
    h[8] = load3(26) << 4;
    h[9] = (load3(29) & 8388607) << 2;
    _carry(h);
    return h;
  }

  static Uint8List _toBytes(_Fe f) {
    final h = Int64List.fromList(f);
    var q = (19 * h[9] + (1 << 24)) >> 25;
    for (var i = 0; i < 10; i++) {
      q = (h[i] + q) >> (i.isEven ? 26 : 25);
    }
    h[0] += 19 * q;
    for (var i = 0; i < 9; i++) {
      final bits = i.isEven ? 26 : 25;
      final c = h[i] >> bits;
      h[i + 1] += c;
      h[i] -= c << bits;
    }
    h[9] &= (1 << 25) - 1;
    final s = Uint8List(32);
    s[0] = h[0];
    s[1] = h[0] >> 8;
    s[2] = h[0] >> 16;
    s[3] = (h[0] >> 24) | (h[1] << 2);
    s[4] = h[1] >> 6;
    s[5] = h[1] >> 14;
    s[6] = (h[1] >> 22) | (h[2] << 3);
    s[7] = h[2] >> 5;
    s[8] = h[2] >> 13;
    s[9] = (h[2] >> 21) | (h[3] << 5);
    s[10] = h[3] >> 3;
    s[11] = h[3] >> 11;
    s[12] = (h[3] >> 19) | (h[4] << 6);
    s[13] = h[4] >> 2;
    s[14] = h[4] >> 10;
    s[15] = h[4] >> 18;
    s[16] = h[5];
    s[17] = h[5] >> 8;
    s[18] = h[5] >> 16;
    s[19] = (h[5] >> 24) | (h[6] << 1);
    s[20] = h[6] >> 7;
    s[21] = h[6] >> 15;
    s[22] = (h[6] >> 23) | (h[7] << 3);
    s[23] = h[7] >> 5;
    s[24] = h[7] >> 13;
    s[25] = (h[7] >> 21) | (h[8] << 4);
    s[26] = h[8] >> 4;
    s[27] = h[8] >> 12;
    s[28] = (h[8] >> 20) | (h[9] << 6);
    s[29] = h[9] >> 2;
    s[30] = h[9] >> 10;
    s[31] = h[9] >> 18;
    return s;
  }

  static void _carry(_Fe h) {
    var h0 = h[0], h1 = h[1], h2 = h[2], h3 = h[3], h4 = h[4];
    var h5 = h[5], h6 = h[6], h7 = h[7], h8 = h[8], h9 = h[9];
    int c;
    c = (h0 + (1 << 25)) >> 26;
    h1 += c;
    h0 -= c << 26;
    c = (h4 + (1 << 25)) >> 26;
    h5 += c;
    h4 -= c << 26;
    c = (h1 + (1 << 24)) >> 25;
    h2 += c;
    h1 -= c << 25;
    c = (h5 + (1 << 24)) >> 25;
    h6 += c;
    h5 -= c << 25;
    c = (h2 + (1 << 25)) >> 26;
    h3 += c;
    h2 -= c << 26;
    c = (h6 + (1 << 25)) >> 26;
    h7 += c;
    h6 -= c << 26;
    c = (h3 + (1 << 24)) >> 25;
    h4 += c;
    h3 -= c << 25;
    c = (h7 + (1 << 24)) >> 25;
    h8 += c;
    h7 -= c << 25;
    c = (h4 + (1 << 25)) >> 26;
    h5 += c;
    h4 -= c << 26;
    c = (h8 + (1 << 25)) >> 26;
    h9 += c;
    h8 -= c << 26;
    c = (h9 + (1 << 24)) >> 25;
    h0 += c * 19;
    h9 -= c << 25;
    c = (h0 + (1 << 25)) >> 26;
    h1 += c;
    h0 -= c << 26;
    h[0] = h0;
    h[1] = h1;
    h[2] = h2;
    h[3] = h3;
    h[4] = h4;
    h[5] = h5;
    h[6] = h6;
    h[7] = h7;
    h[8] = h8;
    h[9] = h9;
  }

  static void _add(_Fe h, _Fe f, _Fe g) {
    for (var i = 0; i < 10; i++) {
      h[i] = f[i] + g[i];
    }
    _carry(h);
  }

  static void _sub(_Fe h, _Fe f, _Fe g) {
    for (var i = 0; i < 10; i++) {
      h[i] = f[i] - g[i];
    }
    _carry(h);
  }

  static void _neg(_Fe h, _Fe f) {
    for (var i = 0; i < 10; i++) {
      h[i] = -f[i];
    }
  }

  // h may alias f or g.
  static void _mul(_Fe h, _Fe f, _Fe g) {
    final f0 = f[0], f1 = f[1], f2 = f[2], f3 = f[3], f4 = f[4];
    final f5 = f[5], f6 = f[6], f7 = f[7], f8 = f[8], f9 = f[9];
    final g0 = g[0], g1 = g[1], g2 = g[2], g3 = g[3], g4 = g[4];
    final g5 = g[5], g6 = g[6], g7 = g[7], g8 = g[8], g9 = g[9];
    final f1x2 = 2 * f1, f3x2 = 2 * f3, f5x2 = 2 * f5;
    final f7x2 = 2 * f7, f9x2 = 2 * f9;
    final g1x19 = 19 * g1, g2x19 = 19 * g2, g3x19 = 19 * g3;
    final g4x19 = 19 * g4, g5x19 = 19 * g5, g6x19 = 19 * g6;
    final g7x19 = 19 * g7, g8x19 = 19 * g8, g9x19 = 19 * g9;
    var h0 = f0 * g0 +
        f1x2 * g9x19 +
        f2 * g8x19 +
        f3x2 * g7x19 +
        f4 * g6x19 +
        f5x2 * g5x19 +
        f6 * g4x19 +
        f7x2 * g3x19 +
        f8 * g2x19 +
        f9x2 * g1x19;
    var h1 = f0 * g1 +
        f1 * g0 +
        f2 * g9x19 +
        f3 * g8x19 +
        f4 * g7x19 +
        f5 * g6x19 +
        f6 * g5x19 +
        f7 * g4x19 +
        f8 * g3x19 +
        f9 * g2x19;
    var h2 = f0 * g2 +
        f1x2 * g1 +
        f2 * g0 +
        f3x2 * g9x19 +
        f4 * g8x19 +
        f5x2 * g7x19 +
        f6 * g6x19 +
        f7x2 * g5x19 +
        f8 * g4x19 +
        f9x2 * g3x19;
    var h3 = f0 * g3 +
        f1 * g2 +
        f2 * g1 +
        f3 * g0 +
        f4 * g9x19 +
        f5 * g8x19 +
        f6 * g7x19 +
        f7 * g6x19 +
        f8 * g5x19 +
        f9 * g4x19;
    var h4 = f0 * g4 +
        f1x2 * g3 +
        f2 * g2 +
        f3x2 * g1 +
        f4 * g0 +
        f5x2 * g9x19 +
        f6 * g8x19 +
        f7x2 * g7x19 +
        f8 * g6x19 +
        f9x2 * g5x19;
    var h5 = f0 * g5 +
        f1 * g4 +
        f2 * g3 +
        f3 * g2 +
        f4 * g1 +
        f5 * g0 +
        f6 * g9x19 +
        f7 * g8x19 +
        f8 * g7x19 +
        f9 * g6x19;
    var h6 = f0 * g6 +
        f1x2 * g5 +
        f2 * g4 +
        f3x2 * g3 +
        f4 * g2 +
        f5x2 * g1 +
        f6 * g0 +
        f7x2 * g9x19 +
        f8 * g8x19 +
        f9x2 * g7x19;
    var h7 = f0 * g7 +
        f1 * g6 +
        f2 * g5 +
        f3 * g4 +
        f4 * g3 +
        f5 * g2 +
        f6 * g1 +
        f7 * g0 +
        f8 * g9x19 +
        f9 * g8x19;
    var h8 = f0 * g8 +
        f1x2 * g7 +
        f2 * g6 +
        f3x2 * g5 +
        f4 * g4 +
        f5x2 * g3 +
        f6 * g2 +
        f7x2 * g1 +
        f8 * g0 +
        f9x2 * g9x19;
    var h9 = f0 * g9 +
        f1 * g8 +
        f2 * g7 +
        f3 * g6 +
        f4 * g5 +
        f5 * g4 +
        f6 * g3 +
        f7 * g2 +
        f8 * g1 +
        f9 * g0;
    h[0] = h0;
    h[1] = h1;
    h[2] = h2;
    h[3] = h3;
    h[4] = h4;
    h[5] = h5;
    h[6] = h6;
    h[7] = h7;
    h[8] = h8;
    h[9] = h9;
    _carry(h);
  }

  static void _sq(_Fe h, _Fe f) => _mul(h, f, f);

  static void _sqTimes(_Fe h, _Fe f, int times) {
    _sq(h, f);
    for (var i = 1; i < times; i++) {
      _sq(h, h);
    }
  }

  static bool _isZero(_Fe f) => _toBytes(f).every((b) => b == 0);

  static bool _isNegative(_Fe f) => _toBytes(f)[0] & 1 == 1;

  // z^(2^250 - 1), and z^11 as a by-product.
  static (_Fe, _Fe) _pow250(_Fe z) {
    final z2 = _fe(), z9 = _fe(), z11 = _fe(), t = _fe();
    _sq(z2, z);
    _sqTimes(t, z2, 2);
    _mul(z9, z, t);
    _mul(z11, z2, z9);
    final z5 = _fe();
    _sq(t, z11);
    _mul(z5, z9, t); // 2^5 - 1
    final z10 = _fe();
    _sqTimes(t, z5, 5);
    _mul(z10, t, z5); // 2^10 - 1
    final z20 = _fe();
    _sqTimes(t, z10, 10);
    _mul(z20, t, z10); // 2^20 - 1
    final z40 = _fe();
    _sqTimes(t, z20, 20);
    _mul(z40, t, z20); // 2^40 - 1
    final z50 = _fe();
    _sqTimes(t, z40, 10);
    _mul(z50, t, z10); // 2^50 - 1
    final z100 = _fe();
    _sqTimes(t, z50, 50);
    _mul(z100, t, z50); // 2^100 - 1
    final z200 = _fe();
    _sqTimes(t, z100, 100);
    _mul(z200, t, z100); // 2^200 - 1
    final z250 = _fe();
    _sqTimes(t, z200, 50);
    _mul(z250, t, z50); // 2^250 - 1
    return (z250, z11);
  }

  static _Fe _invert(_Fe z) {
    final (z250, z11) = _pow250(z);
    final out = _fe();
    _sqTimes(out, z250, 5);
    _mul(out, out, z11); // 2^255 - 21
    return out;
  }

  static _Fe _pow22523(_Fe z) {
    final (z250, _) = _pow250(z);
    final out = _fe();
    _sqTimes(out, z250, 2);
    _mul(out, out, z); // 2^252 - 3
    return out;
  }

  static _Point? _decompress(List<int> s) {
    final y = _feFromBytes(s);
    // Refuse a non-canonical y.
    final canonical = _toBytes(y);
    for (var i = 0; i < 31; i++) {
      if (canonical[i] != s[i]) return null;
    }
    if (canonical[31] != s[31] & 127) return null;
    final one = _fe()..[0] = 1;
    final u = _fe(), v = _fe(), y2 = _fe();
    _sq(y2, y);
    _sub(u, y2, one);
    _mul(v, y2, _d);
    _add(v, v, one);
    final v3 = _fe(), x = _fe(), t = _fe();
    _sq(v3, v);
    _mul(v3, v3, v);
    _sq(x, v3);
    _mul(x, x, v);
    _mul(x, x, u); // u v^7
    final p = _pow22523(x);
    _mul(x, p, v3);
    _mul(x, x, u); // u v^3 (u v^7)^((p-5)/8)
    final check = _fe();
    _sq(check, x);
    _mul(check, check, v);
    _sub(t, check, u);
    if (!_isZero(t)) {
      _add(t, check, u);
      if (!_isZero(t)) return null;
      _mul(x, x, _sqrtM1);
    }
    final sign = s[31] >> 7;
    if (_isZero(x) && sign == 1) return null;
    if ((_isNegative(x) ? 1 : 0) != sign) _neg(x, x);
    final point = _Point(x, y, one, _fe());
    _mul(point.t, x, y);
    return point;
  }

  static Uint8List _encode(_Point p) {
    final zi = _invert(p.z);
    final x = _fe(), y = _fe();
    _mul(x, p.x, zi);
    _mul(y, p.y, zi);
    final s = _toBytes(y);
    if (_isNegative(x)) s[31] ^= 128;
    return s;
  }

  static final _Fe _a = _fe(), _b = _fe(), _c = _fe(), _dd = _fe();
  static final _Fe _e = _fe(), _f = _fe(), _g = _fe(), _h = _fe();

  // r = p + q; r may alias p.
  static void _addPoints(_Point r, _Point p, _Point q) {
    _sub(_a, p.y, p.x);
    _sub(_b, q.y, q.x);
    _mul(_a, _a, _b);
    _add(_b, p.y, p.x);
    _add(_c, q.y, q.x);
    _mul(_b, _b, _c);
    _mul(_c, p.t, q.t);
    _mul(_c, _c, _d2);
    _mul(_dd, p.z, q.z);
    _add(_dd, _dd, _dd);
    _sub(_e, _b, _a);
    _sub(_f, _dd, _c);
    _add(_g, _dd, _c);
    _add(_h, _b, _a);
    _mul(r.x, _e, _f);
    _mul(r.y, _g, _h);
    _mul(r.t, _e, _h);
    _mul(r.z, _f, _g);
  }

  // r = p - q; r may alias p.
  static void _subPoints(_Point r, _Point p, _Point q) {
    final negated = _Point(_fe(), q.y, q.z, _fe());
    _neg(negated.x, q.x);
    _neg(negated.t, q.t);
    _addPoints(r, p, negated);
  }

  // r = 2p; r may alias p.
  static void _double(_Point r, _Point p) {
    _sq(_a, p.x);
    _sq(_b, p.y);
    _sq(_c, p.z);
    _add(_c, _c, _c);
    _add(_e, p.x, p.y);
    _sq(_e, _e);
    _sub(_e, _e, _a);
    _sub(_e, _e, _b);
    _sub(_g, _b, _a); // -A + B
    _sub(_f, _g, _c);
    _neg(_h, _a);
    _sub(_h, _h, _b); // -A - B
    _mul(r.x, _e, _f);
    _mul(r.y, _g, _h);
    _mul(r.t, _e, _h);
    _mul(r.z, _f, _g);
  }

  static List<_Point> _oddMultiples(_Point p) {
    final twice = _Point.zero();
    _double(twice, p);
    final out = [p];
    for (var i = 1; i < 8; i++) {
      final next = _Point.zero();
      _addPoints(next, out[i - 1], twice);
      out.add(next);
    }
    return out;
  }

  static Int8List _slide(List<int> a) {
    final r = Int8List(256);
    for (var i = 0; i < 256; i++) {
      r[i] = 1 & (a[i >> 3] >> (i & 7));
    }
    for (var i = 0; i < 256; i++) {
      if (r[i] == 0) continue;
      for (var b = 1; b <= 6 && i + b < 256; b++) {
        if (r[i + b] == 0) continue;
        if (r[i] + (r[i + b] << b) <= 15) {
          r[i] += r[i + b] << b;
          r[i + b] = 0;
        } else if (r[i] - (r[i + b] << b) >= -15) {
          r[i] -= r[i + b] << b;
          for (var k = i + b; k < 256; k++) {
            if (r[k] == 0) {
              r[k] = 1;
              break;
            }
            r[k] = 0;
          }
        } else {
          break;
        }
      }
    }
    return r;
  }

  // [a]A + [b]B.
  static _Point _doubleScalarMult(List<int> a, _Point point, List<int> b) {
    final aSlide = _slide(a);
    final bSlide = _slide(b);
    final ai = _oddMultiples(point);
    final bi = _baseOdd;
    final r = _Point.zero();
    var i = 255;
    while (i >= 0 && aSlide[i] == 0 && bSlide[i] == 0) {
      i--;
    }
    for (; i >= 0; i--) {
      _double(r, r);
      final da = aSlide[i], db = bSlide[i];
      if (da > 0) {
        _addPoints(r, r, ai[da ~/ 2]);
      } else if (da < 0) {
        _subPoints(r, r, ai[-da ~/ 2]);
      }
      if (db > 0) {
        _addPoints(r, r, bi[db ~/ 2]);
      } else if (db < 0) {
        _subPoints(r, r, bi[-db ~/ 2]);
      }
    }
    return r;
  }
}

final class _Point {
  _Point(this.x, this.y, this.z, this.t);

  _Point.zero()
      : x = _fe(),
        y = _fe()..[0] = 1,
        z = _fe()..[0] = 1,
        t = _fe();

  final _Fe x, y, z, t;
}

// The reference arithmetic on BigInt, for platforms without 64-bit integers.
abstract final class _BigVerify {
  static final BigInt _d =
      (_p - BigInt.from(121665)) * BigInt.from(121666).modInverse(_p) % _p;
  static final BigInt _sqrtM1 = BigInt.two.modPow((_p - BigInt.one) >> 2, _p);

  static bool verify(
      List<int> publicKey, List<int> message, List<int> signature) {
    final scalars = _scalars(publicKey, message, signature);
    if (scalars == null) return false;
    final a = _decompress(publicKey);
    final r = _decompress(signature.sublist(0, 32));
    final base = _decompress(
        _toLe32(BigInt.from(4) * BigInt.from(5).modInverse(_p) % _p));
    if (a == null || r == null || base == null) return false;
    if (_smallOrder(a) || _smallOrder(r)) return false;
    final negA = ((_p - a.$1) % _p, a.$2, a.$3, (_p - a.$4) % _p);
    final sum =
        _add(_mul(_fromLe(scalars.$2), base), _mul(_fromLe(scalars.$1), negA));
    final zi = sum.$3.modInverse(_p);
    final x = sum.$1 * zi % _p, y = sum.$2 * zi % _p;
    final encoded = _toLe32(y);
    if (x.isOdd) encoded[31] |= 128;
    for (var i = 0; i < 32; i++) {
      if (encoded[i] != signature[i]) return false;
    }
    return true;
  }

  static Uint8List baseMultiple(BigInt scalar) {
    final base = _decompress(
        _toLe32(BigInt.from(4) * BigInt.from(5).modInverse(_p) % _p))!;
    final q = _mul(scalar, base);
    final zi = q.$3.modInverse(_p);
    final x = q.$1 * zi % _p;
    final encoded = _toLe32(q.$2 * zi % _p);
    if (x.isOdd) encoded[31] |= 128;
    return encoded;
  }

  static bool _smallOrder((BigInt, BigInt, BigInt, BigInt) p) {
    final q = _mul(BigInt.from(8), p);
    return q.$1 % _p == BigInt.zero && (q.$2 - q.$3) % _p == BigInt.zero;
  }

  static (BigInt, BigInt, BigInt, BigInt)? _decompress(List<int> s) {
    final bytes = Uint8List.fromList(s);
    final sign = bytes[31] >> 7;
    bytes[31] &= 127;
    final y = _fromLe(bytes);
    if (y >= _p) return null;
    final u = (y * y - BigInt.one) % _p;
    final v = (_d * y * y + BigInt.one) % _p;
    var x = u *
        v.modPow(BigInt.from(3), _p) *
        (u * v.modPow(BigInt.from(7), _p))
            .modPow((_p - BigInt.from(5)) >> 3, _p) %
        _p;
    final check = v * x * x % _p;
    if (check != u) {
      if (check != (_p - u) % _p) return null;
      x = x * _sqrtM1 % _p;
    }
    if (x == BigInt.zero && sign == 1) return null;
    if ((x.isOdd ? 1 : 0) != sign) x = (_p - x) % _p;
    return (x, y, BigInt.one, x * y % _p);
  }

  static (BigInt, BigInt, BigInt, BigInt) _add(
      (BigInt, BigInt, BigInt, BigInt) p, (BigInt, BigInt, BigInt, BigInt) q) {
    final a = (p.$2 - p.$1) * (q.$2 - q.$1) % _p;
    final b = (p.$2 + p.$1) * (q.$2 + q.$1) % _p;
    final c = BigInt.two * _d * p.$4 * q.$4 % _p;
    final d = BigInt.two * p.$3 * q.$3 % _p;
    final e = b - a, f = d - c, g = d + c, h = b + a;
    return (e * f % _p, g * h % _p, f * g % _p, e * h % _p);
  }

  static (BigInt, BigInt, BigInt, BigInt) _mul(
      BigInt scalar, (BigInt, BigInt, BigInt, BigInt) point) {
    var result = (BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);
    for (var i = scalar.bitLength - 1; i >= 0; i--) {
      result = _add(result, result);
      if ((scalar >> i).isOdd) result = _add(result, point);
    }
    return result;
  }
}
