import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('supported policy reports round-trip to identical canonical bytes', () {
    final report = _report();
    final decoded =
        SdkSupportedPolicyRevisionsV1.fromCanonicalBytes(report.canonicalBytes);
    expect(decoded, report);
    expect(decoded.canonicalBytes, orderedEquals(report.canonicalBytes));
  });

  test('supported policy reports carry exactly the canonical members', () {
    final expected = <String, Object?>{
      'assignmentApiLevel': 1,
      'collectionBudgetFamily': collectionBudgetFamily,
      'collectionBudgetFloor': 2,
      'kind': 'sdkSupportedPolicyRevisions',
      'platform': 'web',
      'privacyClassificationRevisionId': privacyClassificationRevisionId,
      'privacyPolicyFamily': manifestPrivacyPolicyFamily,
      'privacyPolicyFloor': 1,
      'schemaVersion': kMeasurementSchemaVersion,
      'sdkVersion': '1.0.0',
    };
    expect(_report().toJson(), expected);
    expect(decodeCanonicalObject(_report().canonicalBytes).keys,
        orderedEquals(expected.keys));
  });

  test('decoding refuses unknown, missing, and unsupported members', () {
    final json = _report().toJson();
    final invalid = <Map<String, Object?>>[
      {...json, 'unknown': true},
      for (final key in json.keys) {...json}..remove(key),
      {...json, 'kind': 'other'},
      {...json, 'schemaVersion': kMeasurementSchemaVersion + 1},
      {...json, 'privacyPolicyFamily': 'other'},
      {...json, 'collectionBudgetFamily': 'other'},
      {...json, 'privacyClassificationRevisionId': 'other'},
    ];
    for (final document in invalid) {
      expect(() => SdkSupportedPolicyRevisionsV1.fromJson(document),
          throwsA(isA<CanonicalFormatException>()));
      expect(
          () => SdkSupportedPolicyRevisionsV1.fromCanonicalBytes(
              CanonicalJsonCodec.encode(document)),
          throwsA(isA<CanonicalFormatException>()));
    }
  });

  test('construction refuses empty strings and values outside the bounds', () {
    for (final construct in <SdkSupportedPolicyRevisionsV1 Function()>[
      () => _report(sdkVersion: ''),
      () => _report(sdkVersion: 'x' * 65),
      () => _report(platform: ''),
      () => _report(platform: 'x' * 33),
      () => _report(privacyPolicyFloor: -1),
      () => _report(collectionBudgetFloor: -1),
      () => _report(privacyPolicyFloor: kMaximumPortableJsonInteger + 1),
      () => _report(collectionBudgetFloor: kMaximumPortableJsonInteger + 1),
    ]) {
      expect(construct, throwsArgumentError);
    }
  });

  test('policy floors one and two fit the request carrier bound', () {
    final carrier =
        base64UrlEncode(_report().canonicalBytes).replaceAll('=', '');
    expect(carrier.length,
        lessThanOrEqualTo(sdkSupportedPolicyRevisionsMaximumCarrierCharacters));
  });
}

SdkSupportedPolicyRevisionsV1 _report({
  String sdkVersion = '1.0.0',
  String platform = 'web',
  int privacyPolicyFloor = 1,
  int collectionBudgetFloor = 2,
}) =>
    SdkSupportedPolicyRevisionsV1(
      sdkVersion: sdkVersion,
      assignmentApiLevel: 1,
      platform: platform,
      privacyPolicyFloor: privacyPolicyFloor,
      collectionBudgetFloor: collectionBudgetFloor,
    );
