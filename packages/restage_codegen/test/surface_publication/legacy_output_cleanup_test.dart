import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/surface_publication/legacy_output_cleanup.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('restage-cleanup-'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String path, List<int> bytes) {
    final file = File.fromUri(root.uri.resolve(path));
    file.parent.createSync(recursive: true);
    return file..writeAsBytesSync(bytes);
  }

  test('removes recognized old artifacts and preserves Dart and authored files',
      () {
    final bytes = RestageBundleCodec.encode(RestageBundle(
      packageName: 'fixture',
      authoredLibraryPath: 'lib/screen.dart',
      entries: [],
    ));
    final bundle = write('lib/restage.generated/screen.rsbundle', bytes);
    final dart =
        write('lib/restage.generated/screen.restage.g.dart', [1, 2, 3]);
    final authored = write('lib/restage.generated/notes.rsbundle', [3, 2, 1]);
    const manifestSource = '{"publications":[],"schemaVersion":1}';
    final manifest = write(
        'lib/generated/restage.publication.json', utf8.encode(manifestSource));
    final index = write(
        'lib/generated/restage.outputs.json',
        utf8.encode(jsonEncode({
          'schemaVersion': 1,
          'package': 'fixture',
          'physicalRoot': '.',
          'publicationManifestPath': 'lib/generated/restage.publication.json',
          'generationFingerprint':
              'sha256:${sha256.convert(utf8.encode(manifestSource))}',
          'entries': [
            {
              'bundle': 'lib/restage.generated/screen.rsbundle',
              'path': 'assets/screen.rfw',
              'entry': 'assets/screen.rfw',
              'sha256': 'sha256:${'0' * 64}'
            },
            {
              'bundle': 'lib/restage.generated/notes.rsbundle',
              'path': 'assets/notes.rfw',
              'entry': 'assets/notes.rfw',
              'sha256': 'sha256:${'0' * 64}'
            }
          ],
        })));
    cleanLegacyRestageOutputsInDirectory(
        root, 'fixture', RestageOutputPlacementPlan.defaults);
    expect(bundle.existsSync(), isFalse);
    expect(index.existsSync(), isFalse);
    expect(manifest.existsSync(), isFalse);
    expect(dart.readAsBytesSync(), [1, 2, 3]);
    expect(authored.readAsBytesSync(), [3, 2, 1]);
    expect(dart.parent.existsSync(), isTrue);
  });

  test(
      'preserves authored or malformed documents with generated-looking markers',
      () {
    for (final path in [
      'lib/generated/restage.analytics-id.metadata.json',
      kRestageAnalyticsIdControlOutputPath,
      'lib/generated/restage.measurement.index.json',
      'assets/restage/source-index.json',
      'assets/restage/output-roster.json',
    ]) {
      final bytes = utf8.encode(jsonEncode({
        'schemaVersion': 1,
        'package': 'fixture',
        'publications': <Object?>[],
        'kind': 'authoredNotes',
        'notes': 'keep this',
      }));
      final file = write(path, bytes);
      cleanLegacyRestageOutputsInDirectory(
          root, 'fixture', RestageOutputPlacementPlan.defaults);
      expect(file.readAsBytesSync(), bytes, reason: path);
    }
  });

  test('removes documents validated by their generated artifact family', () {
    const span = RestageSourceSpan(
        path: 'lib/screen.dart',
        startLine: 1,
        startColumn: 1,
        endLine: 2,
        endColumn: 1);
    const claim = RestageIdentityClaim(namespace: 'general', key: 'screen');
    const output = RestageOutputClaim(
        path: 'lib/restage.generated/screen.rsbundle',
        role: 'bundle',
        builder: 'restage_codegen:outputs');
    final roster = RestageSourceRoster(declarations: [
      const RestageSourceDeclaration(
          kind: RestageRosterSourceKind.screen,
          libraryIdentity: 'package:fixture/screen.dart',
          libraryPath: 'lib/screen.dart',
          declarationIdentity: 'package:fixture/screen.dart#Screen',
          sourcePath: 'lib/screen.dart',
          explicitId: 'screen',
          span: span,
          identityClaims: [claim],
          outputs: [output]),
    ], issues: []);
    final documents = {
      'assets/restage/source-index.json': roster.encodeSourceIndex('fixture'),
      'assets/restage/output-roster.json': roster.encodeOutputRoster('fixture'),
      'lib/generated/restage.measurement.index.json': utf8.decode(
          RestageMeasurementCompilerOutputV1.empty()
              .outputIndexBytes('fixture')),
      'lib/generated/restage.analytics-id.metadata.json':
          AnalyticsIdControlOutputV1(packageName: 'fixture', publications: [])
              .encodeJson(),
      kRestageAnalyticsIdControlOutputPath:
          AnalyticsIdControlOutputV1(packageName: 'fixture', publications: [])
              .encodeJson(),
    };
    for (final entry in documents.entries) {
      final file = write(entry.key, utf8.encode(entry.value));
      cleanLegacyRestageOutputsInDirectory(
          root, 'fixture', RestageOutputPlacementPlan.defaults);
      expect(file.existsSync(), isFalse, reason: entry.key);
      final malformed = jsonDecode(entry.value) as Map<String, Object?>;
      final listKey = ['sources', 'outputs', 'entries', 'publications']
          .singleWhere(malformed.containsKey);
      malformed[listKey] = [<String, Object?>{}];
      final malformedBytes = utf8.encode(jsonEncode(malformed));
      write(entry.key, malformedBytes);
      cleanLegacyRestageOutputsInDirectory(
          root, 'fixture', RestageOutputPlacementPlan.defaults);
      expect(file.readAsBytesSync(), malformedBytes, reason: entry.key);
    }
  });

  test('preserves malformed nested roster entries', () {
    final bytes = utf8.encode(jsonEncode({
      'schemaVersion': 1,
      'package': 'fixture',
      'valid': true,
      'sources': [
        {
          'kind': 'screen',
          'span': {'path': 'lib/a.dart'}
        }
      ],
    }));
    final file = write('assets/restage/source-index.json', bytes);
    cleanLegacyRestageOutputsInDirectory(
        root, 'fixture', RestageOutputPlacementPlan.defaults);
    expect(file.readAsBytesSync(), bytes);
  });

  test('preserves unrecognized old metadata and source directories', () {
    final file =
        write('lib/generated/restage.outputs.json', utf8.encode('authored'));
    final roster = write('assets/restage/source-index.json',
        utf8.encode('{"notes":"authored"}'));
    cleanLegacyRestageOutputsInDirectory(
        root, 'fixture', RestageOutputPlacementPlan.defaults);
    expect(file.readAsStringSync(), 'authored');
    expect(roster.existsSync(), isTrue);
  });
}
