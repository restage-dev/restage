import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

SdkInstalledLibrariesV1 _report() => SdkInstalledLibrariesV1(
      libraries: [
        SdkInstalledLibraryV1(namespace: 'zeta.widgets', version: null),
        SdkInstalledLibraryV1(
          namespace: 'acme.widgets',
          version: 4,
          compatibleSince: 4,
        ),
        SdkInstalledLibraryV1(
          namespace: 'app.widgets',
          version: 2,
          compatibleSince: 1,
        ),
      ],
    );

void main() {
  test('round-trips to identical canonical bytes in namespace order', () {
    final report = _report();
    final decoded =
        SdkInstalledLibrariesV1.fromCanonicalBytes(report.canonicalBytes);
    expect(decoded, report);
    expect(decoded.libraries.map((library) => library.namespace), [
      'acme.widgets',
      'app.widgets',
      'zeta.widgets',
    ]);
  });

  test('writes compatibleSince only above 1', () {
    expect(
      utf8.decode(_report().canonicalBytes),
      '{"kind":"sdkInstalledLibraries","libraries":['
      '{"compatibleSince":4,"namespace":"acme.widgets","version":4},'
      '{"namespace":"app.widgets","version":2},'
      '{"namespace":"zeta.widgets","version":null}],'
      '"schemaVersion":$kMeasurementSchemaVersion}',
    );
  });

  test('optional build metadata is bounded and round-trips canonically', () {
    for (final catalog in [1, kMaximumPortableJsonInteger]) {
      for (final version in ['2.4.1', 'x' * 64]) {
        final report = SdkInstalledLibrariesV1(
          libraries: _report().libraries,
          builtInCatalogVersion: catalog,
          appVersion: version,
        );
        final decoded =
            SdkInstalledLibrariesV1.fromCanonicalBytes(report.canonicalBytes);
        expect(decoded.builtInCatalogVersion, catalog);
        expect(decoded.appVersion, version);
        expect(decoded, report);
      }
    }
    final absent =
        SdkInstalledLibrariesV1.fromCanonicalBytes(_report().canonicalBytes);
    expect(absent.builtInCatalogVersion, isNull);
    expect(absent.appVersion, isNull);
    for (final fields in <Map<String, Object?>>[
      {'builtInCatalogVersion': 0},
      {'builtInCatalogVersion': -1},
      {'builtInCatalogVersion': kMaximumPortableJsonInteger + 1},
      {'builtInCatalogVersion': 1.5},
      {'builtInCatalogVersion': '2'},
      {'builtInCatalogVersion': null},
      {'appVersion': ''},
      {'appVersion': 'x' * 65},
      {'appVersion': '2.4\n'},
      {'appVersion': '2.4\u007f'},
      {'appVersion': 24},
      {'appVersion': null},
    ]) {
      expect(
        () => SdkInstalledLibrariesV1.fromCanonicalBytes(
          CanonicalJsonCodec.encode({..._report().toJson(), ...fields}),
        ),
        throwsA(isA<CanonicalFormatException>()),
        reason: fields.toString(),
      );
    }
  });

  test('decoding refuses noncanonical and out-of-contract documents', () {
    final json = _report().toJson();
    final libraries = json['libraries']! as List<Object?>;
    final invalid = <Map<String, Object?>>[
      {...json, 'unknown': true},
      {...json}..remove('libraries'),
      {...json, 'kind': 'other'},
      {...json, 'schemaVersion': kMeasurementSchemaVersion + 1},
      {
        ...json,
        'libraries': [libraries[1], libraries[0], libraries[2]],
      },
      {
        ...json,
        'libraries': [libraries[0], libraries[0]],
      },
      {
        ...json,
        'libraries': [
          {'namespace': 'acme.widgets', 'version': 4, 'compatibleSince': 1},
        ],
      },
      {
        ...json,
        'libraries': [
          {'namespace': 'acme.widgets', 'version': 4, 'compatibleSince': 5},
        ],
      },
      {
        ...json,
        'libraries': [
          {'namespace': 'acme.widgets', 'version': null, 'compatibleSince': 2},
        ],
      },
      {
        ...json,
        'libraries': [
          {'namespace': 'acme.widgets'},
        ],
      },
      {
        ...json,
        'libraries': [
          {'namespace': 'acme widgets', 'version': 1},
        ],
      },
      {
        ...json,
        'libraries': [
          {'namespace': 'acme.widgets', 'version': 1, 'since': 1},
        ],
      },
      {
        ...json,
        'libraries': [
          for (var i = 0; i <= sdkInstalledLibrariesMaximumLibraries; i++)
            {'namespace': 'lib${i.toString().padLeft(3, '0')}', 'version': 1},
        ],
      },
    ];
    for (final document in invalid) {
      expect(
        () => SdkInstalledLibrariesV1.fromCanonicalBytes(
          CanonicalJsonCodec.encode(document),
        ),
        throwsA(isA<CanonicalFormatException>()),
        reason: jsonEncode(document),
      );
    }
  });

  test('construction refuses values outside the bounds', () {
    for (final construct in <Object Function()>[
      () => SdkInstalledLibraryV1(namespace: '', version: 1),
      () => SdkInstalledLibraryV1(namespace: 'x' * 129, version: 1),
      () => SdkInstalledLibraryV1(namespace: '.lead', version: 1),
      () => SdkInstalledLibraryV1(namespace: 'a', version: 0),
      () => SdkInstalledLibraryV1(
            namespace: 'a',
            version: null,
            compatibleSince: 2,
          ),
      () =>
          SdkInstalledLibraryV1(namespace: 'a', version: 2, compatibleSince: 3),
      () => SdkInstalledLibrariesV1(
            libraries: [
              SdkInstalledLibraryV1(namespace: 'a', version: 1),
              SdkInstalledLibraryV1(namespace: 'a', version: 2),
            ],
          ),
      () => SdkInstalledLibrariesV1(
            libraries: [
              for (var i = 0; i <= sdkInstalledLibrariesMaximumLibraries; i++)
                SdkInstalledLibraryV1(namespace: 'lib$i', version: 1),
            ],
          ),
    ]) {
      expect(construct, throwsArgumentError);
    }
  });

  test('the largest report fits the request carrier bound', () {
    final report = SdkInstalledLibrariesV1(
      builtInCatalogVersion: kMaximumPortableJsonInteger,
      appVersion: 'x' * 64,
      libraries: [
        for (var i = 0; i < sdkInstalledLibrariesMaximumLibraries; i++)
          SdkInstalledLibraryV1(
            namespace: '${i.toString().padLeft(2, '0')}${'x' * 126}',
            version: kMaximumPortableJsonInteger,
            compatibleSince: kMaximumPortableJsonInteger,
          ),
      ],
    );
    final carrier = base64UrlEncode(report.canonicalBytes).replaceAll('=', '');
    expect(
      carrier.length,
      lessThanOrEqualTo(sdkInstalledLibrariesMaximumCarrierCharacters),
    );
  });

  test('writes generated only above 1 and round-trips it', () {
    final report = SdkInstalledLibrariesV1(
      libraries: [
        SdkInstalledLibraryV1(namespace: 'a.w', version: 1, generated: 2),
        SdkInstalledLibraryV1(namespace: 'b.w', version: 1, generated: 1),
      ],
    );
    expect(
      utf8.decode(report.canonicalBytes),
      contains('{"generated":2,"namespace":"a.w","version":1},'
          '{"namespace":"b.w","version":1}'),
    );
    final decoded =
        SdkInstalledLibrariesV1.fromCanonicalBytes(report.canonicalBytes);
    expect(decoded, report);
    expect(decoded.libraries.first.generated, 2);
  });
}
