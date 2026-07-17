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
      experimentEpoch: 3,
      paywallVersion: '0.0.1',
      paywallPublishedVersion: 7,
      cacheHit: false,
    );
    expect(v.bytes.length, 3);
    expect(v.paywallId, 'pro_upgrade');
    expect(v.variantId, 'variant-a');
    expect(v.experimentId, 'exp1');
    expect(v.experimentEpoch, 3);
    expect(v.paywallPublishedVersion, 7);
    expect(v.cacheHit, isFalse);
  });

  group('ResolvedVariant value equality (identity tuple)', () {
    ResolvedVariant make({
      List<int> bytes = const [1, 2, 3],
      String paywallId = 'pro_upgrade',
      String? variantId = 'variant-a',
      String? experimentId = 'exp1',
      int? experimentEpoch = 3,
      String? paywallVersion = '0.0.1',
      int? paywallPublishedVersion = 7,
      bool cacheHit = false,
    }) =>
        ResolvedVariant(
          bytes: Uint8List.fromList(bytes),
          paywallId: paywallId,
          variantId: variantId,
          experimentId: experimentId,
          experimentEpoch: experimentEpoch,
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
        make(experimentEpoch: 3),
        isNot(equals(make(experimentEpoch: 4))),
      );
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

  group('ResolvedVariant.copyWith (all-fields-preserved drop-class guard)', () {
    // Every field is a DISTINCT non-default value so a dropped/reset field is
    // caught field-by-field (the identity `==` deliberately ignores bytes +
    // cacheHit, so preservation is asserted per-field, NOT via equals).
    final full = ResolvedVariant(
      bytes: Uint8List.fromList([7, 8, 9]),
      paywallId: 'pro_upgrade',
      variantId: 'variant-a',
      experimentId: 'exp1',
      experimentEpoch: 3,
      paywallVersion: '0.0.1',
      paywallPublishedVersion: 7,
      cacheHit: false,
    );

    test('copyWith() with no overrides preserves every field', () {
      final copy = full.copyWith();
      expect(copy.bytes, full.bytes);
      expect(copy.paywallId, 'pro_upgrade');
      expect(copy.variantId, 'variant-a');
      expect(copy.experimentId, 'exp1');
      expect(copy.experimentEpoch, 3);
      expect(copy.paywallVersion, '0.0.1');
      expect(copy.paywallPublishedVersion, 7);
      expect(copy.cacheHit, isFalse);
    });

    test('copyWith(cacheHit: true) flips only cacheHit, preserves the rest',
        () {
      final hit = full.copyWith(cacheHit: true);
      expect(hit.cacheHit, isTrue);
      expect(hit.bytes, full.bytes);
      expect(hit.paywallId, 'pro_upgrade');
      expect(hit.variantId, 'variant-a');
      expect(hit.experimentId, 'exp1');
      expect(hit.experimentEpoch, 3);
      expect(hit.paywallVersion, '0.0.1');
      expect(hit.paywallPublishedVersion, 7);
    });

    test('each override lands independently', () {
      expect(full.copyWith(paywallId: 'other').paywallId, 'other');
      expect(full.copyWith(variantId: 'v2').variantId, 'v2');
      expect(full.copyWith(experimentId: 'e2').experimentId, 'e2');
      expect(full.copyWith(experimentEpoch: 4).experimentEpoch, 4);
      expect(full.copyWith(paywallVersion: '9').paywallVersion, '9');
      expect(
        full.copyWith(paywallPublishedVersion: 42).paywallPublishedVersion,
        42,
      );
      expect(
        full.copyWith(bytes: Uint8List.fromList([1])).bytes,
        Uint8List.fromList([1]),
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
