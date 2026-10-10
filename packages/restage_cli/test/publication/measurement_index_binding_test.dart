import 'dart:convert';
import 'dart:io';

import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

/// Padded nodes enough to carry one draft past the admitted byte limit.
const int _oversizedPaddingNodes = 14000;

Matcher _refusedWith(Matcher message) => throwsA(
  isA<PublicationAssemblyException>().having(
    (error) => error.message,
    'message',
    message,
  ),
);

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('index_binding_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<AssembledSurfacePublication> push(String slug) async {
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: root,
    );
    return SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: loaded.manifest.publications.singleWhere(
        (entry) => entry.publication.slug == slug,
      ),
    );
  }

  test(
    'an oversized draft for another surface does not block a push',
    () async {
      final pushed = await seedMeasurementPaywall(root);
      final other = await seedMeasurementPaywall(
        root,
        slug: 'measured_other',
        paddingNodes: _oversizedPaddingNodes,
      );
      expect(
        other.draft.canonicalBytes.length,
        greaterThan(kMaximumMeasurementPublicationCandidateDraftBytes),
        reason: 'the other surface must carry a draft the index cannot admit',
      );
      await writeGeneratedOutput(root, [pushed.entry, other.entry]);
      await writeMeasurementPublicationIndexEntries(root, [
        (entry: pushed.entry, draft: pushed.draft, draftBase64: null),
        (entry: other.entry, draft: other.draft, draftBase64: null),
      ]);

      final assembled = await push('measured_upgrade');
      expect(
        assembled
            .measurementUpload
            ?.proof
            .measurementPublicationDraft
            .canonicalDigest,
        pushed.draft.canonicalDigest,
      );
    },
  );

  test('an oversized draft for the pushed surface names its size', () async {
    final pushed = await seedMeasurementPaywall(
      root,
      paddingNodes: _oversizedPaddingNodes,
    );
    final size = pushed.draft.canonicalBytes.length;
    expect(
      size,
      greaterThan(kMaximumMeasurementPublicationCandidateDraftBytes),
      reason: 'the pushed surface must carry a draft the index cannot admit',
    );

    await expectLater(
      push('measured_upgrade'),
      _refusedWith(
        allOf(
          contains('$size bytes decoded'),
          contains(
            'against a limit of '
            '$kMaximumMeasurementPublicationCandidateDraftBytes',
          ),
        ),
      ),
    );
  });

  test('a padded draft value is still refused', () async {
    final pushed = await seedMeasurementPaywall(root);
    final padded = base64Url.encode(pushed.draft.canonicalBytes);
    expect(
      padded,
      contains('='),
      reason: 'the fixture must carry a padded encoding',
    );
    await writeMeasurementPublicationIndexEntries(root, [
      (entry: pushed.entry, draft: pushed.draft, draftBase64: padded),
    ]);

    await expectLater(
      push('measured_upgrade'),
      _refusedWith(contains('must use unpadded base64url')),
    );
  });

  test('an over-limit value that decodes to no whole byte is refused', () async {
    final pushed = await seedMeasurementPaywall(
      root,
      paddingNodes: _oversizedPaddingNodes,
    );
    // Trimmed to the nearest shorter length that encodes no whole byte, so the
    // value is still past the limit and cannot decode.
    final encoded = base64Url
        .encode(pushed.draft.canonicalBytes)
        .replaceAll('=', '');
    final truncated = encoded.substring(
      0,
      encoded.length - ((encoded.length - 1) % 4),
    );
    expect(truncated.length % 4, 1);
    await writeMeasurementPublicationIndexEntries(root, [
      (entry: pushed.entry, draft: pushed.draft, draftBase64: truncated),
    ]);

    await expectLater(
      push('measured_upgrade'),
      _refusedWith(
        allOf(
          contains('must use unpadded base64url'),
          isNot(contains('bytes decoded')),
        ),
      ),
    );
  });

  test('a repeated selector is refused from another surface', () async {
    final plain = await seedGeneratedPaywall(root, slug: 'plain_upgrade');
    final measured = await seedMeasurementPaywall(root);
    await writeGeneratedOutput(root, [plain, measured.entry]);
    await writeMeasurementPublicationIndexEntries(root, [
      (entry: measured.entry, draft: measured.draft, draftBase64: null),
      (entry: measured.entry, draft: measured.draft, draftBase64: null),
    ]);

    await expectLater(
      push('plain_upgrade'),
      _refusedWith(contains('repeats a publication selector')),
    );
  });
}
