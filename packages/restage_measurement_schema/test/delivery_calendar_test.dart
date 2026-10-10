import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('civil time uses exact Gregorian second precision and fixed encoding',
      () {
    for (final text in [
      '0001-01-01T00:00:00',
      '9999-12-31T23:59:59',
      '2000-02-29T12:30:45',
      '2024-02-29T00:00:00',
      '1900-02-28T00:00:00',
    ]) {
      final time = LocalCivilDateTimeV1.parse(text);
      expect(time.value, text);
      expect(time.toString(), text);
      expect(
        LocalCivilDateTimeV1.fromCanonicalBytes(time.canonicalBytes),
        time,
      );
      expect(
        utf8.decode(time.canonicalBytes),
        '{"kind":"localCivilDateTime","value":"$text"}',
      );
    }
    expect(
      LocalCivilDateTimeV1(year: 1, month: 1, day: 1).value,
      '0001-01-01T00:00:00',
    );
  });

  test('civil parser rejects overflows timezone and alternate precision', () {
    for (final invalid in [
      '0000-01-01T00:00:00',
      '10000-01-01T00:00:00',
      '2026-00-01T00:00:00',
      '2026-13-01T00:00:00',
      '2026-01-00T00:00:00',
      '2026-01-32T00:00:00',
      '2026-04-31T00:00:00',
      '2026-02-29T00:00:00',
      '1900-02-29T00:00:00',
      '2026-01-01T24:00:00',
      '2026-01-01T00:60:00',
      '2026-01-01T00:00:60',
      '2026-1-01T00:00:00',
      '2026-01-01T0:00:00',
      '2026-01-01 00:00:00',
      '2026-01-01t00:00:00',
      '2026-01-01T00:00:00Z',
      '2026-01-01T00:00:00+01:00',
      '2026-01-01T00:00:00.000',
      '2026-01-01T00:00',
      '2026-01-01T00:00:00\n',
      ' 2026-01-01T00:00:00',
    ]) {
      expect(
        () => LocalCivilDateTimeV1.parse(invalid),
        throwsA(isA<CanonicalFormatException>()),
        reason: invalid,
      );
    }
    expect(
      () => LocalCivilDateTimeV1(year: 2026, month: 2, day: 29),
      throwsArgumentError,
    );
    expect(
      () => LocalCivilDateTimeV1(year: 2026, month: 1, day: 1, second: -1),
      throwsArgumentError,
    );
  });

  test('civil ordering follows every component across Gregorian boundaries',
      () {
    final ordered = [
      '0001-01-01T00:00:00',
      '1899-12-31T23:59:59',
      '1900-01-01T00:00:00',
      '2000-02-28T23:59:59',
      '2000-02-29T00:00:00',
      '2000-03-01T00:00:00',
      '2026-10-04T01:00:00',
      '2026-10-04T01:01:00',
      '2026-10-04T01:01:01',
      '2026-10-05T00:00:00',
      '2026-11-01T00:00:00',
      '9999-12-31T23:59:59',
    ].map(LocalCivilDateTimeV1.parse).toList();
    for (var i = 1; i < ordered.length; i++) {
      expect(ordered[i - 1].compareTo(ordered[i]), lessThan(0));
      expect(ordered[i].compareTo(ordered[i - 1]), greaterThan(0));
    }
    expect(
      ordered.first.compareTo(LocalCivilDateTimeV1.parse(ordered.first.value)),
      0,
    );
  });

  test('local windows include starts and exclude ends with absent endpoints',
      () {
    final start = LocalCivilDateTimeV1.parse('2026-12-01T00:00:00');
    final end = LocalCivilDateTimeV1.parse('2027-01-01T00:00:00');
    final before = LocalCivilDateTimeV1.parse('2026-11-30T23:59:59');
    final during = LocalCivilDateTimeV1.parse('2026-12-31T23:59:59');
    final window =
        LocalDeliveryWindowV1(startsInclusive: start, endsExclusive: end);
    expect(window.contains(before), isFalse);
    expect(window.contains(start), isTrue);
    expect(window.contains(during), isTrue);
    expect(window.contains(end), isFalse);
    final from = LocalDeliveryWindowV1(startsInclusive: start);
    expect(from.contains(before), isFalse);
    expect(from.contains(start), isTrue);
    expect(from.contains(end), isTrue);
    expect(from.toJson(), isNot(contains('endsExclusive')));
    final until = LocalDeliveryWindowV1(endsExclusive: end);
    expect(until.contains(before), isTrue);
    expect(until.contains(during), isTrue);
    expect(until.contains(end), isFalse);
    expect(until.toJson(), isNot(contains('startsInclusive')));
  });

  test('local windows reject missing equal and reversed endpoints', () {
    final start = LocalCivilDateTimeV1.parse('2026-12-01T00:00:00');
    final end = LocalCivilDateTimeV1.parse('2027-01-01T00:00:00');
    expect(LocalDeliveryWindowV1.new, throwsArgumentError);
    expect(
      () => LocalDeliveryWindowV1(startsInclusive: start, endsExclusive: start),
      throwsArgumentError,
    );
    expect(
      () => LocalDeliveryWindowV1(startsInclusive: end, endsExclusive: start),
      throwsArgumentError,
    );
    expect(
      () => LocalDeliveryWindowV1.fromJson({'kind': 'localDeliveryWindow'}),
      throwsA(isA<CanonicalFormatException>()),
    );
    expect(
      () => LocalDeliveryWindowV1.fromJson({
        'kind': 'localDeliveryWindow',
        'startsInclusive': null,
        'endsExclusive': end.toJson(),
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test('request clock is bounded and missing malformed evidence is unavailable',
      () {
    for (final offset in [-1080, -60, 0, 60, 1080]) {
      final clock = DeliveryLocalClockV1(offset);
      expect(clock.utcOffsetMinutes, offset);
      expect(
        DeliveryLocalClockV1.fromCanonicalBytes(clock.canonicalBytes),
        clock,
      );
    }
    expect(() => DeliveryLocalClockV1(-1081), throwsArgumentError);
    expect(() => DeliveryLocalClockV1(1081), throwsArgumentError);
    for (final json in <Map<String, Object?>>[
      {'kind': 'deliveryLocalClock'},
      {'kind': 'deliveryLocalClock', 'utcOffsetMinutes': null},
      {'kind': 'deliveryLocalClock', 'utcOffsetMinutes': 1.0},
      {'kind': 'deliveryLocalClock', 'utcOffsetMinutes': '0'},
      {'kind': 'deliveryLocalClock', 'utcOffsetMinutes': 1081},
    ]) {
      expect(
        () => DeliveryLocalClockV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('clock uses UTC micros and current offset across date boundaries', () {
    final now =
        DateTime.utc(2026, 12, 31, 23, 59, 59, 999, 999).microsecondsSinceEpoch;
    expect(
      DeliveryLocalClockV1(60).localNow(nowMicros: now).value,
      '2027-01-01T00:59:59',
    );
    expect(
      DeliveryLocalClockV1(-60).localNow(nowMicros: now).value,
      '2026-12-31T22:59:59',
    );
    expect(
      DeliveryLocalClockV1(0).localNow(nowMicros: now).value,
      '2026-12-31T23:59:59',
    );
    final leap = DateTime.utc(2000, 3).microsecondsSinceEpoch;
    expect(
      DeliveryLocalClockV1(-1).localNow(nowMicros: leap).value,
      '2000-02-29T23:59:00',
    );
    expect(
      DeliveryLocalClockV1(0).localNow(nowMicros: -1).value,
      '1969-12-31T23:59:59',
    );
    final summer = DateTime.utc(2026, 6, 1, 7).microsecondsSinceEpoch;
    expect(
      DeliveryLocalClockV1(-480).localNow(nowMicros: summer).value,
      '2026-05-31T23:00:00',
    );
    expect(
      DeliveryLocalClockV1(-420).localNow(nowMicros: summer).value,
      '2026-06-01T00:00:00',
    );
    expect(
      DeliveryLocalClockV1(1080).localNow(nowMicros: 0).value,
      '1970-01-01T18:00:00',
    );
    expect(
      DeliveryLocalClockV1(-1080).localNow(nowMicros: 0).value,
      '1969-12-31T06:00:00',
    );
  });

  test('clock refuses input and offset sums outside portable integer bounds',
      () {
    expect(
      () => DeliveryLocalClockV1(0)
          .localNow(nowMicros: kMaximumPortableJsonInteger + 1),
      throwsArgumentError,
    );
    expect(
      () => DeliveryLocalClockV1(0)
          .localNow(nowMicros: kMinimumPortableJsonInteger - 1),
      throwsArgumentError,
    );
    expect(
      () => DeliveryLocalClockV1(1080)
          .localNow(nowMicros: kMaximumPortableJsonInteger),
      throwsArgumentError,
    );
    expect(
      () => DeliveryLocalClockV1(-1080)
          .localNow(nowMicros: kMinimumPortableJsonInteger),
      throwsArgumentError,
    );
    expect(
      () => DeliveryLocalClockV1(0)
          .localNow(nowMicros: kMaximumPortableJsonInteger),
      returnsNormally,
    );
    expect(
      () => DeliveryLocalClockV1(0)
          .localNow(nowMicros: kMinimumPortableJsonInteger),
      returnsNormally,
    );
  });

  test('calendar codecs preserve equality and refuse malformed bytes', () {
    final time = LocalCivilDateTimeV1.parse('2026-12-01T00:00:00');
    for (final (value, decode)
        in <(CanonicalValue, CanonicalValue Function(List<int>))>[
      (time, LocalCivilDateTimeV1.fromCanonicalBytes),
      (
        LocalDeliveryWindowV1(startsInclusive: time),
        LocalDeliveryWindowV1.fromCanonicalBytes
      ),
      (
        LocalDeliveryWindowV1(endsExclusive: time),
        LocalDeliveryWindowV1.fromCanonicalBytes
      ),
      (
        LocalDeliveryWindowV1(
          startsInclusive: time,
          endsExclusive: LocalCivilDateTimeV1.parse('2027-01-01T00:00:00'),
        ),
        LocalDeliveryWindowV1.fromCanonicalBytes
      ),
      (DeliveryLocalClockV1(0), DeliveryLocalClockV1.fromCanonicalBytes),
    ]) {
      final bytes = value.canonicalBytes;
      final decoded = decode(bytes);
      expect(decoded, value);
      expect(decoded.hashCode, value.hashCode);
      expect(decoded.canonicalBytes, bytes);
      bytes[0] = 0;
      expect(decode(value.canonicalBytes), value);
      expect(
        () => decode(
          CanonicalJsonCodec.encode({...value.toJson(), 'unknown': true}),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      final text = utf8.decode(value.canonicalBytes);
      final kind = jsonEncode(value.toJson()['kind']);
      expect(
        () => decode(
          utf8.encode(
            text.replaceFirst('"kind":$kind', '"kind":$kind,"kind":$kind'),
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => decode(utf8.encode('$text\n')),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => decode(
          CanonicalJsonCodec.encode(
            {...value.toJson(), 'kind': 'unknown'},
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  group('delivery cache validity', () {
    final target = TargetCoordinate(
      organizationId: OrganizationId(3),
      appId: ApplicationId(5),
      environmentTargetId: EnvironmentTargetId(7),
      namedEnvironmentId: NamedEnvironmentId(6),
      runtimePlane: RuntimePlane.live,
    );
    final placement = _selection(target, placement: true);
    final surface = _selection(target);
    final start = LocalCivilDateTimeV1.parse('2026-12-01T00:00:00');
    final end = LocalCivilDateTimeV1.parse('2027-01-01T00:00:00');

    test('zero one and two selected policies preserve canonical path order',
        () {
      for (final selections in <List<DeliveryPolicyDocumentSelectionV1>>[
        [],
        [placement],
        [surface],
        [placement, surface],
      ]) {
        final cache = _cache(policySelections: selections);
        final decoded = DeliveryCacheValidityV1.fromCanonicalBytes(
          cache.canonicalBytes,
        );
        expect(decoded, cache);
        expect(decoded.hashCode, cache.hashCode);
        expect(decoded.policySelections, orderedEquals(selections));
        expect(decoded.notBeforeLocal, isNull);
        expect(decoded.expiresBeforeLocal, isNull);
        expect(decoded.receiptExpiresAtMicros, isNull);
        expect(decoded.assignmentExpiresAtMicros, isNull);
        expect(decoded.contentExpiresAtMicros, isNull);
        expect(decoded.selectionIdentityDigest, CanonicalDigest('d' * 64));
        expect(
          decoded.toJson().keys,
          unorderedEquals([
            'kind',
            'policySelections',
            'hostContractHash',
            'installedCapabilityHash',
            'selectionIdentityDigest',
          ]),
        );
      }
    });

    test('selection list refuses duplicate scopes extra stages and wrong order',
        () {
      for (final selections in [
        [placement, placement],
        [surface, surface],
        [surface, placement],
        [placement, _selection(target, placement: true, name: 'other')],
        [surface, _selection(target, name: 'other')],
        [placement, surface, surface],
      ]) {
        expect(() => _cache(policySelections: selections), throwsArgumentError);
        expect(
          () => DeliveryCacheValidityV1.fromJson({
            ..._cache().toJson(),
            'policySelections':
                selections.map((value) => value.toJson()).toList(),
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('policy selections require agreement on every target coordinate', () {
      for (final (field, value) in <(String, Object?)>[
        ('organizationId', 4),
        ('appId', 8),
        ('environmentTargetId', 9),
        ('namedEnvironmentId', 10),
        ('runtimePlane', 'sandbox'),
      ]) {
        final otherTarget = TargetCoordinate.fromJson({
          ...target.toJson(),
          field: value,
        });
        final otherSurface = _selection(otherTarget);
        expect(
          () => _cache(policySelections: [placement, otherSurface]),
          throwsArgumentError,
          reason: field,
        );
        expect(
          () => DeliveryCacheValidityV1.fromJson({
            ..._cache().toJson(),
            'policySelections': [
              placement.toJson(),
              otherSurface.toJson(),
            ],
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: field,
        );
      }
    });

    test(
        'cache interval permits absent bounds and requires a nonempty interval',
        () {
      for (final (from, until) in <(
        LocalCivilDateTimeV1?,
        LocalCivilDateTimeV1?,
      )>[(null, null), (start, null), (null, end), (start, end)]) {
        final cache = _cache(notBeforeLocal: from, expiresBeforeLocal: until);
        expect(
          DeliveryCacheValidityV1.fromCanonicalBytes(cache.canonicalBytes),
          cache,
        );
        expect(cache.notBeforeLocal, from);
        expect(cache.expiresBeforeLocal, until);
      }
      for (final (from, until) in [(start, start), (end, start)]) {
        expect(
          () => _cache(notBeforeLocal: from, expiresBeforeLocal: until),
          throwsArgumentError,
        );
        expect(
          () => DeliveryCacheValidityV1.fromJson({
            ..._cache().toJson(),
            'notBeforeLocal': from.toJson(),
            'expiresBeforeLocal': until.toJson(),
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('each absolute expiry is nonnegative and portable without coercion',
        () {
      for (final expiry in [0, 1, kMaximumPortableJsonInteger]) {
        final cache = _cache(
          receiptExpiresAtMicros: expiry,
          assignmentExpiresAtMicros: expiry,
          contentExpiresAtMicros: expiry,
        );
        final decoded = DeliveryCacheValidityV1.fromCanonicalBytes(
          cache.canonicalBytes,
        );
        expect(decoded.receiptExpiresAtMicros, expiry);
        expect(decoded.assignmentExpiresAtMicros, expiry);
        expect(decoded.contentExpiresAtMicros, expiry);
      }
      for (final field in [
        'receiptExpiresAtMicros',
        'assignmentExpiresAtMicros',
        'contentExpiresAtMicros',
      ]) {
        for (final invalid in <Object?>[
          -1,
          kMaximumPortableJsonInteger + 1,
          1.0,
          '1',
          null,
        ]) {
          expect(
            () => DeliveryCacheValidityV1.fromJson({
              ..._cache().toJson(),
              field: invalid,
            }),
            throwsA(isA<CanonicalFormatException>()),
            reason: field,
          );
        }
      }
      for (final expiry in [-1, kMaximumPortableJsonInteger + 1]) {
        expect(
          () => _cache(receiptExpiresAtMicros: expiry),
          throwsArgumentError,
        );
        expect(
          () => _cache(assignmentExpiresAtMicros: expiry),
          throwsArgumentError,
        );
        expect(
          () => _cache(contentExpiresAtMicros: expiry),
          throwsArgumentError,
        );
      }
    });

    test('hash fields require the canonical sha256 algorithm spelling', () {
      for (final field in ['hostContractHash', 'installedCapabilityHash']) {
        for (final invalid in [
          '',
          'a' * 64,
          'sha256:${'A' * 64}',
          'SHA256:${'a' * 64}',
          'sha256:${'a' * 63}',
          'sha256:${'a' * 64}\n',
        ]) {
          expect(
            () => DeliveryCacheValidityV1.fromJson({
              ..._cache().toJson(),
              field: invalid,
            }),
            throwsA(isA<CanonicalFormatException>()),
          );
        }
      }
      expect(() => _cache(hostContractHash: 'a' * 64), throwsArgumentError);
      expect(
        () => _cache(installedCapabilityHash: 'a' * 64),
        throwsArgumentError,
      );
      expect(
        () => DeliveryCacheValidityV1.fromJson({
          ..._cache().toJson(),
          'selectionIdentityDigest': 'sha256:${'d' * 64}',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('cache codec rejects unknown duplicate and malformed nested fields',
        () {
      final cache = _cache(
        policySelections: [placement, surface],
        notBeforeLocal: start,
        expiresBeforeLocal: end,
      );
      for (final field in [
        'unknown',
        'publicProjectionDigest',
        'routingSelectionReceipt',
        'assignment',
        'canonicalDigest',
      ]) {
        expect(
          () => DeliveryCacheValidityV1.fromJson({
            ...cache.toJson(),
            field: 'x',
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      for (final field in _cache().toJson().keys) {
        expect(
          () => DeliveryCacheValidityV1.fromJson(
            _cache().toJson()..remove(field),
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      for (final field in ['notBeforeLocal', 'expiresBeforeLocal']) {
        expect(
          () => DeliveryCacheValidityV1.fromJson({
            ...cache.toJson(),
            field: null,
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      final nested =
          jsonDecode(jsonEncode(cache.toJson())) as Map<String, Object?>;
      ((nested['policySelections']! as List<Object?>).first!
              as Map<String, Object?>)['scope'] =
          placement.policyRevision.scope.toJson();
      expect(
        () => DeliveryCacheValidityV1.fromJson(nested),
        throwsA(isA<CanonicalFormatException>()),
      );
      final text = utf8.decode(cache.canonicalBytes);
      for (final invalid in [
        '$text\n',
        text.replaceFirst(
          '"kind":"deliveryCacheValidity"',
          '"kind":"deliveryCacheValidity","kind":"deliveryCacheValidity"',
        ),
        text.replaceFirst('"ordinal":1', '"ordinal":1,"ordinal":1'),
        text.replaceFirst('"ordinal":1', '"ordinal":1.0'),
      ]) {
        expect(invalid, isNot(text));
        expect(
          () => DeliveryCacheValidityV1.fromCanonicalBytes(
            utf8.encode(invalid),
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      expect(
        () => DeliveryCacheValidityV1.fromJson({
          ...cache.toJson(),
          'kind': 'unknown',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('cache list nested selections JSON and bytes are immutable', () {
      final selections = [placement, surface];
      final cache = _cache(policySelections: selections);
      final originalBytes = cache.canonicalBytes;
      final originalHash = cache.hashCode;
      selections.clear();
      expect(cache.policySelections, orderedEquals([placement, surface]));
      expect(cache.policySelections.clear, throwsUnsupportedError);
      expect(() => cache.policySelections[0] = surface, throwsUnsupportedError);
      final input = cache.canonicalBytes;
      final decoded = DeliveryCacheValidityV1.fromCanonicalBytes(input);
      input[0] = 0;
      decoded.canonicalBytes[0] = 0;
      final json = decoded.toJson();
      final first = (json['policySelections']! as List<Object?>).first!
          as Map<String, Object?>;
      (first['policyRevision']! as Map<String, Object?>)['revisionId'] =
          'other';
      (json['policySelections']! as List<Object?>)[0] = <String, Object?>{};
      json.clear();
      expect(decoded, cache);
      expect(decoded.hashCode, originalHash);
      expect(decoded.canonicalBytes, originalBytes);
      expect(decoded.policySelections, orderedEquals([placement, surface]));
    });
  });
}

DeliveryPolicyDocumentSelectionV1 _selection(
  TargetCoordinate target, {
  bool placement = false,
  String name = 'home',
}) =>
    DeliveryPolicyDocumentSelectionV1(
      policyRevision: DeliveryPolicyRevisionRefV1(
        scope: DeliveryPolicyScopeV1(
          root: placement
              ? DeliveryRootIdentityV1.placement(
                  PlacementIdentityV1(
                    target: target,
                    key: PlacementKeyV1.named(slug: name),
                  ),
                )
              : DeliveryRootIdentityV1.surface(
                  PublishedSurfaceIdentityV1(
                    target: target,
                    surfaceId: SurfaceId(name),
                  ),
                ),
          family: placement
              ? const DeliveryFamilySelectorV1.none()
              : const DeliveryFamilySelectorV1.general(),
        ),
        ordinal: 1,
        canonicalPolicyDigest: CanonicalDigest('b' * 64),
        revisionId: 'policy.1',
      ),
      documentRef: ExactRoutingDocumentRefV1(
        schemaVersion: 2,
        canonicalDigest: CanonicalDigest('c' * 64),
      ),
    );

DeliveryCacheValidityV1 _cache({
  List<DeliveryPolicyDocumentSelectionV1> policySelections = const [],
  LocalCivilDateTimeV1? notBeforeLocal,
  LocalCivilDateTimeV1? expiresBeforeLocal,
  int? receiptExpiresAtMicros,
  int? assignmentExpiresAtMicros,
  int? contentExpiresAtMicros,
  String? hostContractHash,
  String? installedCapabilityHash,
}) =>
    DeliveryCacheValidityV1(
      policySelections: policySelections,
      notBeforeLocal: notBeforeLocal,
      expiresBeforeLocal: expiresBeforeLocal,
      receiptExpiresAtMicros: receiptExpiresAtMicros,
      assignmentExpiresAtMicros: assignmentExpiresAtMicros,
      contentExpiresAtMicros: contentExpiresAtMicros,
      hostContractHash: hostContractHash ?? 'sha256:${'a' * 64}',
      installedCapabilityHash: installedCapabilityHash ?? 'sha256:${'b' * 64}',
      selectionIdentityDigest: CanonicalDigest('d' * 64),
    );
