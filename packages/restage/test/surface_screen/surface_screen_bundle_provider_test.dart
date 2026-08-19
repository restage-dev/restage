import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'surface_screen_test_support.dart';

/// The fail-closed matrix for bundled fallback.
///
/// Every case here drives the real bundle codec rather than a stand-in, so a
/// container that a repackaging step altered is rejected by the same rules
/// that produced it.
void main() {
  setUp(resetSurfaceScreenTestState);

  test('serves a screen from a valid packaged bundle', () async {
    final fixture = stringScreenFixture();
    final resolver = AssetSurfaceScreenResolver(
      bundleProvider: AssetSurfaceScreenBundleProvider(
        assetBundle: fixture.assetBundle(),
      ),
    );

    final resolved = await resolver.resolve(fixture.ref);

    expect(resolved.origin, SurfaceScreenOrigin.bundled);
    expect(resolved.slug, fixture.ref.slug);
    expect(resolved.blob, fixture.blob);
    expect(resolved.contentHash, fixture.contentHash);
    expect(resolved.bundledEntryHash, fixture.blobSha256);
    expect(resolved.publishedRevision, isNull);

    // The host's own validation accepts the same result.
    fixture.ref.provenance.validateResolved(resolved);
  });

  test('refuses when the application packages no bundles at all', () async {
    final fixture = stringScreenFixture(packagesBundle: false);
    const resolver = AssetSurfaceScreenResolver();

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsUnavailable(SurfaceScreenUnavailableReason.missing),
    );
  });

  test('refuses when provenance names a bundle the application omitted',
      () async {
    final fixture = stringScreenFixture();
    final resolver = AssetSurfaceScreenResolver(
      bundleProvider: AssetSurfaceScreenBundleProvider(
        assetBundle: TestAssetBundle(const <String, Uint8List>{}),
      ),
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsUnavailable(SurfaceScreenUnavailableReason.missing),
    );
  });

  test('refuses a bundle the codec rejects as a container', () async {
    final fixture = stringScreenFixture();
    final corrupt = Uint8List.fromList(fixture.bundleBytes())
      ..[8] = 0xFF
      ..[9] = 0xFF;
    final resolver = AssetSurfaceScreenResolver(
      bundleProvider: AssetSurfaceScreenBundleProvider(
        assetBundle: fixture.assetBundle(bytes: corrupt),
      ),
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsUnavailable(SurfaceScreenUnavailableReason.invalidPayload),
    );
  });

  test('refuses a truncated bundle', () async {
    final fixture = stringScreenFixture();
    final full = fixture.bundleBytes();
    final resolver = AssetSurfaceScreenResolver(
      bundleProvider: AssetSurfaceScreenBundleProvider(
        assetBundle: fixture.assetBundle(
          bytes: Uint8List.sublistView(full, 0, full.length - 8),
        ),
      ),
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsUnavailable(SurfaceScreenUnavailableReason.invalidPayload),
    );
  });

  test('refuses a well-formed bundle carrying different screen bytes',
      () async {
    final fixture = stringScreenFixture();
    // A bundle that is internally consistent — the codec accepts it — but
    // whose screen blob is not the one provenance pins.
    final substituted = fixture.bundleBytes(
      blobOverride: rfwScreenBlob(text: 'Substituted screen', event: 'tap'),
    );
    final resolver = AssetSurfaceScreenResolver(
      bundleProvider: AssetSurfaceScreenBundleProvider(
        assetBundle: fixture.assetBundle(bytes: substituted),
      ),
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsUnavailable(SurfaceScreenUnavailableReason.contractMismatch),
    );
  });

  test('refuses a valid bundle built for a different library', () async {
    final fixture = stringScreenFixture();
    final foreign = RestageBundleCodec.encode(
      RestageBundle(
        packageName: 'other_app',
        authoredLibraryPath: kFixtureAuthoredLibrary,
        entries: <RestageBundleEntry>[
          RestageBundleEntry(
            logicalPath: fixture.locator.screenBlob.logicalPath,
            role: RestageBundleEntryRoleV1.screenBlob,
            bytes: fixture.blob,
          ),
          RestageBundleEntry(
            logicalPath: fixture.locator.capabilitySidecar.logicalPath,
            role: RestageBundleEntryRoleV1.capabilitySidecar,
            bytes: fixture.sidecarBytes,
          ),
        ],
      ),
    );
    final resolver = AssetSurfaceScreenResolver(
      bundleProvider: AssetSurfaceScreenBundleProvider(
        assetBundle: fixture.assetBundle(bytes: foreign),
      ),
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsUnavailable(SurfaceScreenUnavailableReason.contractMismatch),
    );
  });

  test('refuses a bundle whose capability sidecar disagrees with the contract',
      () async {
    final fixture = stringScreenFixture();
    // Correct blob hash, but a capability floor the generated contract does
    // not carry — a sidecar swapped in from a different build.
    final wrongSidecar = Uint8List.fromList(
      utf8.encode(
        jsonEncode(
          CapabilitySidecar(
            blobSha256: fixture.blobSha256,
            manifest: CapabilityManifest(
              builtInFloor: 99,
              requiredLibraries: const [],
            ),
          ).toJson(),
        ),
      ),
    );
    final resolver = AssetSurfaceScreenResolver(
      bundleProvider: AssetSurfaceScreenBundleProvider(
        assetBundle: fixture.assetBundle(
          bytes: RestageBundleCodec.encode(
            RestageBundle(
              packageName: kFixturePackageName,
              authoredLibraryPath: kFixtureAuthoredLibrary,
              entries: <RestageBundleEntry>[
                RestageBundleEntry(
                  logicalPath: fixture.locator.screenBlob.logicalPath,
                  role: RestageBundleEntryRoleV1.screenBlob,
                  bytes: fixture.blob,
                ),
                RestageBundleEntry(
                  logicalPath: fixture.locator.capabilitySidecar.logicalPath,
                  role: RestageBundleEntryRoleV1.capabilitySidecar,
                  bytes: wrongSidecar,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsUnavailable(SurfaceScreenUnavailableReason.contractMismatch),
    );
  });
}

Matcher throwsUnavailable(SurfaceScreenUnavailableReason reason) => throwsA(
      isA<SurfaceScreenUnavailableError>()
          .having((error) => error.reason, 'reason', reason),
    );
