import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('publication_manifest_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('loads the canonical generated publication metadata pair', () async {
    final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');

    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    expect(loaded.projectRoot.path, tempDir.absolute.path);
    final selected = loaded.select(slug: 'checkout').publication;
    expect(selected.surface, entry.publication.surface);
    expect(selected.slug, entry.publication.slug);
    expect(selected.sourceKind, entry.publication.sourceKind);
    expect(selected.payloadKind, entry.publication.payloadKind);
    expect(
      loaded.manifestFile.path,
      p.join(tempDir.path, surfacePublicationManifestRelativePath),
    );
  });

  test('invalid marker wins over a present manifest', () async {
    await seedGeneratedPaywall(tempDir);
    final marker = File(
      p.join(tempDir.path, surfacePublicationInvalidRelativePath),
    );
    await marker.parent.create(recursive: true);
    await marker.writeAsString('generated output failed');

    await expectLater(
      SurfacePublicationManifestLoader().load(projectRoot: tempDir),
      throwsA(
        isA<PublicationManifestException>().having(
          (error) => error.message,
          'message',
          contains('Generated publication output is invalid'),
        ),
      ),
    );
  });

  test(
    'missing generated metadata fails closed without directory fallback',
    () async {
      final artifact = File(
        p.join(tempDir.path, 'assets/paywalls/checkout.rfw'),
      );
      await artifact.parent.create(recursive: true);
      await artifact.writeAsBytes(const <int>[1, 2, 3]);

      await expectLater(
        SurfacePublicationManifestLoader().load(projectRoot: tempDir),
        throwsA(
          isA<PublicationManifestException>().having(
            (error) => error.message,
            'message',
            contains('No generated publication output index'),
          ),
        ),
      );
    },
  );

  test('rejects a noncanonical manifest as stale generated output', () async {
    await seedGeneratedPaywall(tempDir);
    final manifestFile = File(
      p.join(tempDir.path, surfacePublicationManifestRelativePath),
    );
    final reformatted = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(await manifestFile.readAsString()));
    await manifestFile.writeAsString(reformatted);
    // Re-stamp the fingerprint so the index still vouches for these exact
    // bytes; the manifest's own canonical form is what must fail here.
    await mutateGeneratedIndex(
      tempDir,
      (index) => index['generationFingerprint'] = CapabilitySidecar.hashBlob(
        utf8.encode(reformatted),
      ),
    );

    await expectLater(
      SurfacePublicationManifestLoader().load(projectRoot: tempDir),
      throwsA(
        isA<PublicationManifestException>().having(
          (error) => error.message,
          'message',
          contains('not canonical'),
        ),
      ),
    );
  });

  test('--type is validation-only and rejects a generated mismatch', () async {
    await seedGeneratedPaywall(tempDir, slug: 'checkout');
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    expect(
      () => loaded.select(slug: 'checkout', type: Surface.onboarding),
      throwsA(
        isA<PublicationManifestException>().having(
          (error) => error.message,
          'message',
          contains('generated manifest is authoritative'),
        ),
      ),
    );
  });

  test(
    'source kind selects the generated lineage without category inference',
    () async {
      await seedGeneratedPaywall(tempDir, slug: 'checkout');
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );

      final selected = loaded
          .select(
            slug: 'checkout',
            type: Surface.paywall,
            sourceKind: SurfaceSourceKind.paywall,
          )
          .publication;
      expect(selected.sourceKind, SurfaceSourceKind.paywall);

      expect(
        () => loaded.select(
          slug: 'checkout',
          type: Surface.paywall,
          sourceKind: SurfaceSourceKind.screen,
          contractVersion: 7,
        ),
        throwsA(
          isA<PublicationManifestException>().having(
            (error) => error.message,
            'message',
            contains('requested generated source identity'),
          ),
        ),
      );
    },
  );
}
