import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('ResolvedVariant stores bytes + metadata', () {
    final v = ResolvedVariant(
      bytes: Uint8List.fromList([1, 2, 3]),
      paywallId: 'pro_upgrade',
      variantId: 'variant-a',
      experimentId: 'exp1',
      paywallVersion: '0.0.1',
      paywallPublishedVersion: 7,
      cacheHit: false,
    );
    expect(v.bytes.length, 3);
    expect(v.paywallId, 'pro_upgrade');
    expect(v.variantId, 'variant-a');
    expect(v.paywallPublishedVersion, 7);
    expect(v.cacheHit, isFalse);
  });

  group('ResolvedVariant value equality (identity tuple)', () {
    ResolvedVariant make({
      List<int> bytes = const [1, 2, 3],
      String paywallId = 'pro_upgrade',
      String? variantId = 'variant-a',
      String? experimentId = 'exp1',
      String? paywallVersion = '0.0.1',
      int? paywallPublishedVersion = 7,
      bool cacheHit = false,
    }) =>
        ResolvedVariant(
          bytes: Uint8List.fromList(bytes),
          paywallId: paywallId,
          variantId: variantId,
          experimentId: experimentId,
          paywallVersion: paywallVersion,
          paywallPublishedVersion: paywallPublishedVersion,
          cacheHit: cacheHit,
        );

    test('equal over the identity tuple, ignoring bytes and cacheHit', () {
      expect(
        make(bytes: const [1, 2, 3], cacheHit: false),
        equals(make(bytes: const [9, 9, 9], cacheHit: true)),
      );
      expect(
        make(bytes: const [1, 2, 3], cacheHit: false).hashCode,
        make(bytes: const [9, 9, 9], cacheHit: true).hashCode,
      );
    });

    test('differs when any identity field differs', () {
      expect(make(paywallId: 'a'), isNot(equals(make(paywallId: 'b'))));
      expect(make(variantId: 'a'), isNot(equals(make(variantId: 'b'))));
      expect(make(experimentId: 'a'), isNot(equals(make(experimentId: 'b'))));
      expect(
        make(paywallVersion: '1'),
        isNot(equals(make(paywallVersion: '2'))),
      );
      expect(make(variantId: null), isNot(equals(make(variantId: 'x'))));
    });

    test('differs when the published version differs (hosted republish)', () {
      // A hosted republish (v1 -> v2) changes the bytes, so the same id at a
      // different published version must NOT compare equal — otherwise a host's
      // "same variant, skip re-render" cache would show stale content. Null
      // (asset-resolved) vs an int (hosted) also differ.
      expect(
        make(paywallPublishedVersion: 1),
        isNot(equals(make(paywallPublishedVersion: 2))),
      );
      expect(
        make(paywallPublishedVersion: 1).hashCode,
        isNot(make(paywallPublishedVersion: 2).hashCode),
      );
      expect(
        make(paywallPublishedVersion: null),
        isNot(equals(make(paywallPublishedVersion: 3))),
      );
    });
  });

  test('RestagePaywallError exposes code + message', () {
    const e = RestagePaywallError(
      code: 'decode_failed',
      message: 'corrupt blob',
      retryable: false,
    );
    expect(e.code, 'decode_failed');
    expect(e.toString(), contains('corrupt blob'));
  });
}
