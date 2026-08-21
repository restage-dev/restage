// Source-level hygiene of this package, asserted over its own files.
//
// These checks read `lib/` and `pubspec.yaml` from the package root, so they
// only mean anything from inside this package.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('draft and candidate sources use only allowed imports', () {
    const allowedImportsByPath = <String, Set<String>>{
      'lib/src/publication_candidate.dart': {
        'dart:convert',
        'dart:typed_data',
        'package:restage_measurement_schema/src/canonical.dart',
        'package:restage_measurement_schema/src/publication_draft.dart',
      },
      'lib/src/publication_draft.dart': {
        'dart:convert',
        'package:restage_measurement_schema/src/canonical.dart',
        'package:restage_measurement_schema/src/identifiers.dart',
        'package:restage_measurement_schema/src/lineage.dart',
        'package:restage_measurement_schema/src/manifest.dart',
        'package:restage_measurement_schema/src/publication_route.dart',
        'package:restage_measurement_schema/src/published_identity.dart',
      },
    };
    final importPattern = RegExp(
      r'''^\s*import\s+['"]([^'"]+)['"][^;]*;$''',
      multiLine: true,
    );

    for (final entry in allowedImportsByPath.entries) {
      final source = File(entry.key).readAsStringSync();
      final importMatches = importPattern.allMatches(source).toList();
      final importUris = importMatches.map((match) => match.group(1)!).toSet();
      expect(
        importMatches.length,
        equals(
          source
              .split('\n')
              .where((line) => line.trimLeft().startsWith('import '))
              .length,
        ),
        reason: entry.key,
      );
      expect(importUris, equals(entry.value), reason: entry.key);
      expect(
        importUris.every(
          (uri) =>
              uri.startsWith('dart:') ||
              uri.startsWith('package:restage_measurement_schema/'),
        ),
        isTrue,
        reason: entry.key,
      );
    }
  });

  test(
      'public binding barrel is dependency-clean and does not import '
      'publication', () {
    final barrel = File(
      'lib/restage_measurement_schema.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final source = File('lib/src/publication_binding.dart').readAsStringSync();

    expect(barrel, contains("export 'src/publication_binding.dart';"));
    expect(pubspec, isNot(contains('restage_shared:')));
    expect(pubspec, isNot(contains('restage:')));
    expect(source, isNot(contains('package:restage_shared/')));
    expect(source, isNot(contains('SurfacePublication')));
    expect(source, isNot(contains('SurfaceSourceKind')));
    expect(source, isNot(contains('SurfacePayloadKind')));
  });

  test('public bundled registry contract remains independent of publication',
      () {
    final barrel = File(
      'lib/restage_measurement_schema.dart',
    ).readAsStringSync();
    final source = File(
      'lib/src/publication_bundled_registry.dart',
    ).readAsStringSync();

    expect(barrel, contains("export 'src/publication_bundled_registry.dart';"));
    expect(source, isNot(contains('package:restage_shared/')));
    expect(source, isNot(contains('SurfacePublication')));
    expect(source, isNot(contains('SurfacePublicationArtifactRole')));
  });
}
