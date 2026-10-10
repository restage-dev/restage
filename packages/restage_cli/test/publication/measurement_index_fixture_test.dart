import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

/// One tracked artifact a bundle declares.
typedef _TrackedArtifact = ({String logicalPath, String hex});

Uint8List _decodeDraft(String value) =>
    base64Url.decode(value.padRight((value.length + 3) ~/ 4 * 4, '='));

void main() {
  test(
    'the Measurement index fixture records the hashes the bundles declare',
    () {
      final root = locateCheckoutRoot();
      final bundleRoot = Directory(
        p.join(root.path, 'apps', 'examples', 'assets', 'restage', 'bundles'),
      );
      expect(
        bundleRoot.existsSync(),
        isTrue,
        reason: 'the example bundle tree is missing at ${bundleRoot.path}',
      );

      // Index every bundle artifact by content hash, and every flow document
      // by the flow it names, so a stale entry can be reported against a file.
      final declaredByHash = <String, String>{};
      final flowDocuments = <String, _TrackedArtifact>{};
      for (final file
          in bundleRoot
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => p.extension(file.path) == '.rsbundle')) {
        final bundle = RestageBundleCodec.decode(file.readAsBytesSync());
        for (final entry in bundle.entries) {
          final hex = entry.sha256.substring('sha256:'.length);
          declaredByHash[hex] = '${entry.role.name} ${entry.logicalPath}';
          if (entry.role != RestageBundleEntryRole.flowDocument) continue;
          final flow = FlowDocumentCodec.decodeJson(utf8.decode(entry.bytes));
          expect(
            flowDocuments.containsKey(flow.flow),
            isFalse,
            reason: 'two bundles declare the flow ${flow.flow}',
          );
          flowDocuments[flow.flow] = (logicalPath: entry.logicalPath, hex: hex);
        }
      }
      expect(declaredByHash, isNotEmpty);

      final fixtureFile = File(
        p.join(root.path, exampleMeasurementIndexFixturePath),
      );
      final index =
          jsonDecode(fixtureFile.readAsStringSync()) as Map<String, Object?>;
      final entries = index['entries']! as List<Object?>;
      expect(entries, isNotEmpty);

      const refresh =
          'Refresh it from the example app\'s generated Measurement '
          'publication index, as the note on '
          'exampleMeasurementIndexFixturePath describes.';

      for (final raw in entries) {
        final entry = raw! as Map<String, Object?>;
        final selector = entry['selector']! as Map<String, Object?>;
        final slug = selector['slug']! as String;
        final draft = MeasurementPublicationDraftV1.fromCanonicalBytes(
          _decodeDraft(entry['draftBase64']! as String),
        );
        expect(draft.artifacts, isNotEmpty, reason: '$slug declares none');

        // A flow document is nameable on its own, so compare it against the
        // exact tracked file first and report both hashes. The rest carry no
        // path, so they are checked against everything the bundles declare.
        for (final artifact in draft.artifacts.where(
          (artifact) =>
              artifact.artifactKind.value == 'publication.flow-document',
        )) {
          final tracked = flowDocuments[slug];
          expect(
            tracked,
            isNotNull,
            reason: 'no tracked bundle declares a flow document for $slug',
          );
          expect(
            artifact.contentHash.hex,
            tracked!.hex,
            reason:
                'the Measurement index fixture is stale for $slug: it records '
                '${artifact.contentHash.hex} for ${tracked.logicalPath}, and '
                'the tracked bundle declares ${tracked.hex}. $refresh',
          );
        }

        for (final artifact in draft.artifacts) {
          expect(
            declaredByHash.containsKey(artifact.contentHash.hex),
            isTrue,
            reason:
                'the Measurement index fixture is stale for $slug: no tracked '
                'bundle declares ${artifact.artifactKind.value} '
                '${artifact.contentHash.hex}. $refresh',
          );
        }
      }
    },
  );
}
