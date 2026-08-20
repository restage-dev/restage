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

  test('resolves a Dart source path through the recorded sources', () async {
    final checkout = await seedGeneratedPaywall(
      tempDir,
      slug: 'checkout',
      sources: const <String>['lib/paywalls/checkout.dart'],
    );
    final upsell = await seedGeneratedPaywall(
      tempDir,
      slug: 'upsell',
      sources: const <String>['lib/paywalls/bundle.dart'],
    );
    final crossSell = await seedGeneratedPaywall(
      tempDir,
      slug: 'cross_sell',
      sources: const <String>['lib/paywalls/bundle.dart'],
    );
    // Codegen emits publications sorted by identity; the fixture mirrors
    // that so the returned order is the manifest's, not the seeding order.
    await writeGeneratedOutput(tempDir, [checkout, crossSell, upsell]);

    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    // A package-relative path, an absolute path, and a path that walks
    // through the project root all name the same publication.
    for (final input in <String>[
      'lib/paywalls/checkout.dart',
      './lib/paywalls/checkout.dart',
      p.join(tempDir.path, 'lib', 'paywalls', 'checkout.dart'),
      p.join(tempDir.path, 'lib', '..', 'lib', 'paywalls', 'checkout.dart'),
    ]) {
      expect(
        loaded
            .selectByPath(path: input)
            .map((entry) => entry.publication.slug)
            .toList(),
        <String>['checkout'],
        reason: 'path "$input" must resolve to checkout',
      );
    }

    // A file holding two surfaces returns both, in manifest order, rather
    // than guessing which one the developer meant.
    expect(
      loaded
          .selectByPath(path: 'lib/paywalls/bundle.dart')
          .map((entry) => entry.publication.slug)
          .toList(),
      <String>['cross_sell', 'upsell'],
    );

    // A file the manifest does not attribute any publication to is an
    // error naming the manifest, not an empty success.
    expect(
      () => loaded.selectByPath(path: 'lib/paywalls/unknown.dart'),
      throwsA(
        isA<PublicationManifestException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('lib/paywalls/unknown.dart'),
            contains('build_runner'),
          ),
        ),
      ),
    );

    // A path outside the package cannot address generated output.
    expect(
      () => loaded.selectByPath(path: '/etc/passwd.dart'),
      throwsA(
        isA<PublicationManifestException>().having(
          (error) => error.message,
          'message',
          contains('outside'),
        ),
      ),
    );
  });

  test(
    'a file that produced only another category says so, not "nothing"',
    () async {
      final flow = await seedGeneratedPaywall(
        tempDir,
        slug: 'welcome_flow',
        sources: const <String>['lib/screens/welcome.dart'],
        surface: Surface.general,
      );
      await writeGeneratedOutput(tempDir, [flow]);

      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );

      expect(
        loaded
            .selectByPath(path: 'lib/screens/welcome.dart')
            .map((entry) => entry.publication.slug),
        <String>['welcome_flow'],
      );

      // The file DID compile. Reporting "nothing was compiled from it" and
      // pointing at build_runner would send the developer somewhere that can
      // never change the answer.
      expect(
        () => loaded.selectByPath(
          path: 'lib/screens/welcome.dart',
          type: Surface.paywall,
        ),
        throwsA(
          isA<PublicationManifestException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('is a paywall surface'),
              contains('it produced general'),
              isNot(contains('build_runner')),
            ),
          ),
        ),
      );
    },
  );

  test(
    'a package-relative path resolves from inside the project too',
    () async {
      final entry = await seedGeneratedPaywall(
        tempDir,
        slug: 'checkout',
        sources: const <String>['lib/paywalls/checkout.dart'],
      );
      await writeGeneratedOutput(tempDir, [entry]);
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );

      // Run the resolution with the process cwd genuinely inside the project,
      // which is where a developer actually types this. Resolving purely
      // against the working directory would produce `lib/lib/paywalls/...`.
      final subdirectory = Directory(p.join(tempDir.path, 'lib'))
        ..createSync(recursive: true);
      final previous = Directory.current;
      Directory.current = subdirectory;
      try {
        for (final input in <String>[
          'lib/paywalls/checkout.dart',
          'paywalls/checkout.dart',
        ]) {
          expect(
            loaded
                .selectByPath(path: input)
                .map((entry) => entry.publication.slug),
            <String>['checkout'],
            reason: 'path "$input" typed from <root>/lib must resolve',
          );
        }
      } finally {
        Directory.current = previous;
      }
    },
  );

  test('a manifest without recorded sources says so by name', () async {
    await seedGeneratedPaywall(tempDir, slug: 'checkout');

    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    expect(
      () => loaded.selectByPath(path: 'lib/paywalls/checkout.dart'),
      throwsA(
        isA<PublicationManifestException>().having(
          (error) => error.message,
          'message',
          contains('does not record authoring sources'),
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
