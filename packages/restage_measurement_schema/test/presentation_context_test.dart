import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('full presentation context round-trips to identical canonical bytes',
      () {
    final value = MeasurementPresentationContextV1(
      presentationCountry: 'US',
      platform: 'ios',
      appBuildOrdinal: 42,
      deviceClass: 'phone',
    );
    final decoded = MeasurementPresentationContextV1.fromCanonicalBytes(
        value.canonicalBytes);
    expect(decoded, value);
    expect(decoded.canonicalBytes, orderedEquals(value.canonicalBytes));
    expect(
        decodeCanonicalObject(value.canonicalBytes).keys,
        orderedEquals([
          'appBuildOrdinal',
          'deviceClass',
          'kind',
          'platform',
          'presentationCountry',
          'schemaVersion',
        ]));
  });

  test('unknown observations emit only document kind and version', () {
    final value = MeasurementPresentationContextV1();
    expect(value.toJson(), {
      'kind': 'measurementPresentationContext',
      'schemaVersion': kMeasurementSchemaVersion,
    });
    expect(
        MeasurementPresentationContextV1.fromCanonicalBytes(
                value.canonicalBytes)
            .canonicalBytes,
        orderedEquals(value.canonicalBytes));
  });

  test('partially known observations round-trip', () {
    for (final value in [
      MeasurementPresentationContextV1(presentationCountry: 'GB'),
      MeasurementPresentationContextV1(platform: 'web', deviceClass: 'web'),
      MeasurementPresentationContextV1(appBuildOrdinal: 0),
      MeasurementPresentationContextV1(
          appBuildOrdinal: kMaximumPortableJsonInteger),
    ]) {
      expect(
          MeasurementPresentationContextV1.fromCanonicalBytes(
                  value.canonicalBytes)
              .canonicalBytes,
          orderedEquals(value.canonicalBytes));
    }
  });

  test('decoding refuses invalid presentation context members', () {
    final json = MeasurementPresentationContextV1().toJson();
    for (final invalid in <Map<String, Object?>>[
      {...json, 'unknown': true},
      {...json, 'kind': 'other'},
      {...json, 'schemaVersion': kMeasurementSchemaVersion + 1},
      {...json, 'presentationCountry': 'us'},
      {...json, 'presentationCountry': 'USA'},
      {...json, 'presentationCountry': 'US\n'},
      {...json, 'presentationCountry': 'ÉU'},
      {...json, 'platform': 'other'},
      {...json, 'deviceClass': 'other'},
      {...json, 'appBuildOrdinal': -1},
      {...json, 'appBuildOrdinal': kMaximumPortableJsonInteger + 1},
    ]) {
      expect(
          () => MeasurementPresentationContextV1.fromJson(invalid),
          throwsA(
              anyOf(isA<ArgumentError>(), isA<CanonicalFormatException>())));
      expect(
          () => MeasurementPresentationContextV1.fromCanonicalBytes(
              CanonicalJsonCodec.encode(invalid)),
          throwsA(
              anyOf(isA<ArgumentError>(), isA<CanonicalFormatException>())));
    }
  });
}
