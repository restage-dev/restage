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

/// One draft of the example index fixture, decoded once for every test.
typedef _IndexedDraft = ({
  String slug,
  Uint8List bytes,
  MeasurementPublicationDraftV1 draft,
});

final List<_IndexedDraft> _indexedDrafts = () {
  final index =
      jsonDecode(
            File(
              p.join(
                locateCheckoutRoot().path,
                exampleMeasurementIndexFixturePath,
              ),
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  return [
    for (final raw in index['entries']! as List<Object?>)
      _indexedDraft(raw! as Map<String, Object?>),
  ];
}();

_IndexedDraft _indexedDraft(Map<String, Object?> entry) {
  final value = entry['draftBase64']! as String;
  final bytes = base64Url.decode(
    value.padRight((value.length + 3) ~/ 4 * 4, '='),
  );
  return (
    slug: (entry['selector']! as Map<String, Object?>)['slug']! as String,
    bytes: bytes,
    draft: MeasurementPublicationDraftV1.fromCanonicalBytes(bytes),
  );
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void main() {
  test('every generated draft in the example index binds', () {
    expect(_indexedDrafts, isNotEmpty);

    var largest = 0;
    for (final (:slug, :bytes, :draft) in _indexedDrafts) {
      expect(
        bytes.length,
        lessThanOrEqualTo(kMaximumMeasurementPublicationCandidateDraftBytes),
        reason: '$slug carries a draft the index cannot admit',
      );
      // Decoding through the schema proves the bound admits the real value
      // rather than only comparing its length.
      expect(
        _sameBytes(draft.canonicalBytes, bytes),
        isTrue,
        reason: '$slug does not re-encode to its own bytes',
      );
      if (bytes.length > largest) largest = bytes.length;
    }

    expect(
      largest,
      533530,
      reason: 'the largest generated draft in the example app has moved',
    );
  });

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

      expect(_indexedDrafts, isNotEmpty);

      const refresh =
          'Refresh it from the example app\'s generated Measurement '
          'publication index, as the note on '
          'exampleMeasurementIndexFixturePath describes.';

      for (final (:slug, bytes: _, :draft) in _indexedDrafts) {
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
