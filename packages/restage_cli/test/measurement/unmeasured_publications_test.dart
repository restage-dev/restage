import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/measurement/measurement_publication_candidate_assembler.dart';
import 'package:restage_cli/src/measurement/unmeasured_publications.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('unmeasured_publications_');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void writeIndex(Object? unmeasured) =>
      File(
        p.join(
          root.path,
          GeneratedOutputLayout.generatedDirectory.metadataDirectory,
          restageMeasurementPublicationIndexFileName,
        ),
      ).writeAsStringSync(
        jsonEncode({
          'entries': <Object?>[],
          'kind': 'restageMeasurementPublicationIndex',
          'package': fixturePackageName,
          'schemaVersion': 1,
          'unmeasured': ?unmeasured,
        }),
      );

  test('names the build reason for an unmeasured publication', () async {
    final entry = await seedGeneratedPaywall(root, slug: 'plus_paywall');
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: root,
    );
    expect(unmeasuredPublicationWarning(loaded, entry), isNull);

    writeIndex([
      {
        'reason': 'A callback is emitted more than once.',
        'selector': {
          'surface': 'paywall',
          'slug': 'other',
          'sourceKind': entry.publication.sourceKind.wireName,
        },
      },
      {
        'reason': 'A callback is emitted more than once.',
        'selector': {
          'surface': 'paywall',
          'slug': 'plus_paywall',
          'sourceKind': entry.publication.sourceKind.wireName,
        },
      },
    ]);
    expect(
      unmeasuredPublicationWarning(loaded, entry),
      'plus_paywall compiles unmeasured: A callback is emitted more than '
      'once. Its taps and views are not counted.',
    );

    writeIndex(null);
    expect(unmeasuredPublicationWarning(loaded, entry), isNull);
  });

  // The build's own index shape; the compiler's tests pin their output to it.
  test('reads the index the build writes for an unmeasured surface', () async {
    final entry = await seedGeneratedPaywall(root, slug: 'plus_paywall');
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: root,
    );
    File(
      p.join(
        root.path,
        GeneratedOutputLayout.generatedDirectory.metadataDirectory,
        restageMeasurementPublicationIndexFileName,
      ),
    ).writeAsBytesSync(
      File(
        'test/_fixtures/unmeasured.measurement.index.json',
      ).readAsBytesSync(),
    );
    expect(
      unmeasuredPublicationWarning(loaded, entry),
      'plus_paywall compiles unmeasured: A callback under a conditional '
      'combined with && or || is emitted more than once, so it cannot carry '
      'one route. Its taps and views are not counted.',
    );
  });
}
