import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_refusal_reason.dart';
import 'package:restage/src/resolver/placement_fallback_log.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('a placement fallback logs once per reason', () {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message!);
    addTearDown(() {
      debugPrint = previous;
      resetPlacementFallbackLog();
    });
    final key = PlacementKeyV1.named(slug: 'home_card');
    debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.unavailable);
    debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.unavailable);
    debugLogPlacementFallback(
        key, PlacementBatchRefusalReasonV1.invalidAuthority);
    expect(lines, hasLength(2));
    expect(lines.first, startsWith('[restage] placement named:home_card'));
    expect(lines.first, contains('(unavailable)'));
    expect(lines.last, contains('(invalidAuthority)'));
    debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.unavailable,
        detail: 'noPublication');
    expect(lines.last, contains('(unavailable:noPublication)'));
    expect(
        placementFallbackReason(
            PlacementBatchRefusalReasonV1.unavailable, 'fitUnavailable'),
        'unavailable:fitUnavailable');
  });

  test('an upload refusal yields only a bounded reason', () {
    List<int> body(Object value) => utf8.encode(jsonEncode(value));
    expect(
        measurementRefusalReason(
            body({'error': 'invalid_request', 'reason': 'unknownBinding'})),
        'unknownBinding');
    expect(measurementRefusalReason(body({'error': 'invalid_request'})),
        'invalid_request');
    expect(measurementRefusalReason(body({'reason': 'a b'})), isNull);
    expect(measurementRefusalReason(body({'reason': 'x' * 65})), isNull);
    expect(measurementRefusalReason(utf8.encode('not json')), isNull);
    expect(measurementRefusalLogLine(400, 'unknownBinding'),
        '[restage] measurement upload refused (HTTP 400): unknownBinding');
  });
}
