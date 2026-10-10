import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  final blob = Uint8List.fromList(const <int>[1, 2, 3]);
  final font = Uint8List.fromList(const <int>[0, 1, 0, 0, 9]);
  const seeds = <String, Object>{'note': 'hi', 'count': 2, 'on': true};

  ({SurfacePublicationManifest manifest, Map<String, List<int>> files}) fixture(
      BlobSurfacePayload payload) {
    final sidecar = Uint8List.fromList(
      utf8.encode(
        jsonEncode(
          CapabilitySidecar(
            blobSha256: CapabilitySidecar.hashBlob(blob),
            manifest: CapabilityManifest(
              builtInFloor: payload.minClient,
              requiredLibraries: const <LibraryRequirement>[],
            ),
          ).toJson(),
        ),
      ),
    );
    final seedBytes = encodeLocalSeedsArtifact({'Paywall': seeds});
    final files = <String, List<int>>{
      'assets/paywalls/pro.rfw': blob,
      'assets/paywalls/pro.capability.json': sidecar,
      'assets/paywalls/pro.local.json': seedBytes,
      'assets/paywalls/pro.fonts/MaterialIcons.otf': font,
    };
    SurfacePublicationArtifact artifact(
      String path,
      SurfacePublicationArtifactRole role,
      String id,
    ) =>
        SurfacePublicationArtifact(
          contentHash: CapabilitySidecar.hashBlob(files[path]!),
          path: path,
          role: role,
          id: id,
        );
    final manifest = SurfacePublicationManifest(
      publications: <SurfacePublicationManifestEntry>[
        SurfacePublicationManifestEntry(
          artifacts: <SurfacePublicationArtifact>[
            artifact(
              'assets/paywalls/pro.capability.json',
              SurfacePublicationArtifactRole.capabilitySidecar,
              'pro',
            ),
            artifact(
              'assets/paywalls/pro.fonts/MaterialIcons.otf',
              SurfacePublicationArtifactRole.iconFont,
              iconFontArtifactId('MaterialIcons', null),
            ),
            artifact(
              'assets/paywalls/pro.local.json',
              SurfacePublicationArtifactRole.localSeeds,
              'pro',
            ),
            artifact(
              'assets/paywalls/pro.rfw',
              SurfacePublicationArtifactRole.screenBlob,
              'pro',
            ),
          ],
          publication: SurfacePublication(
            surface: Surface.paywall,
            slug: 'pro',
            sourceKind: SurfaceSourceKind.paywall,
            payloadKind: SurfacePayloadKind.blob,
            payloadContentHash: payload.contentHash,
          ),
        ),
      ],
    );
    return (manifest: manifest, files: files);
  }

  BlobSurfacePayload payload({
    List<DeliveredIconFont>? iconFonts,
    Map<String, Map<String, Object>>? localSeeds,
  }) =>
      BlobSurfacePayload(
        minClient: kSurfaceFeatureClientFloor,
        blob: blob,
        iconFonts: iconFonts ??
            [DeliveredIconFont(family: 'MaterialIcons', bytes: font)],
        localSeeds: localSeeds ?? const {'Paywall': seeds},
      );

  test('declared icon fonts and seeds must match the assembled payload', () {
    final assembled = payload();
    final built = fixture(assembled);
    final closure = built.manifest.validateArtifactClosure(built.files).single;

    expect(closure.iconFonts.single.family, 'MaterialIcons');
    expect(closure.localSeeds, {'Paywall': seeds});
    closure.validateAssembledPayload(assembled.canonicalBytes);
  });

  test('a payload missing a declared section is refused', () {
    final withoutSeeds = payload(localSeeds: const {});
    final built = fixture(withoutSeeds);
    final closure = built.manifest.validateArtifactClosure(built.files).single;

    expect(
      () => closure.validateAssembledPayload(withoutSeeds.canonicalBytes),
      throwsFormatException,
    );
  });

  test('icon font ids carry the owning package', () {
    expect(iconFontArtifactId('Glyphs', 'brand_icons'), 'Glyphs@brand_icons');
    final font = decodeIconFontArtifact('Glyphs@brand_icons', const [1]);
    expect(font.family, 'Glyphs');
    expect(font.fontPackage, 'brand_icons');
    expect(() => iconFontArtifactId('A@B', null), throwsFormatException);
  });

  test('a seeds artifact round-trips every root', () {
    final bytes = encodeLocalSeedsArtifact({
      'b': {'z': 1, 'a': true},
      'a': seeds,
    });

    expect(decodeLocalSeedsArtifact(bytes), {
      'a': seeds,
      'b': {'a': true, 'z': 1},
    });
    expect(
      utf8.decode(bytes),
      startsWith('{"a":{"count":2,"note":"hi","on":true},"b":{"a":true'),
    );
  });

  test('a seeds artifact must carry the publication slug', () {
    final built = fixture(payload());
    final entry = built.manifest.publications.single;
    expect(
      () => SurfacePublicationManifestEntry(
        artifacts: [
          for (final artifact in entry.artifacts)
            if (artifact.role == SurfacePublicationArtifactRole.localSeeds)
              SurfacePublicationArtifact(
                contentHash: artifact.contentHash,
                path: artifact.path,
                role: artifact.role,
                id: 'Paywall',
              )
            else
              artifact,
        ],
        publication: entry.publication,
      ),
      throwsFormatException,
    );
  });
}
