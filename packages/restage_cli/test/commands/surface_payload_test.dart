import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:restage_cli/src/commands/surface_payload.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_payload_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('assembleSurfacePayloadBytes (real first_run fixture)', () {
    test(
      'assembles canonical bytes that round-trip via SurfacePayload.decode',
      () async {
        final flowPath = await seedSurfaceFlow(tempDir);

        final bytes = await assembleSurfacePayloadBytes(flowPath);

        // The canonical frame the backend re-decodes at publish time.
        final decoded = SurfacePayload.decode(bytes);
        expect(decoded, isA<FlowSurfacePayload>());
        final flow = decoded as FlowSurfacePayload;
        expect(
          flow.screenBlobs.keys.toSet(),
          flow.flowDocument.screenArtifacts.keys.toSet(),
        );
        expect(flow.flowDocument.flow, 'first_run');

        // Divergence guard: the production assembler must emit exactly the
        // canonical bytes the delivery round-trip consumes — i.e. the same
        // bytes a direct `FlowSurfacePayload(...)` build produces. This locks
        // the CLI's output to the bytes the backend serve round-trip pins.
        final src = locateOnboardingFixtures();
        final document = FlowDocumentCodec.decodeJson(
          File('${src.path}/flows/first_run.flow.json').readAsStringSync(),
        );
        final reference = FlowSurfacePayload(
          flowDocument: document,
          screenBlobs: <String, Uint8List>{
            for (final entry in document.screenArtifacts.entries)
              entry.key: File(
                '${src.path}/screens/${entry.value.path}',
              ).readAsBytesSync(),
          },
        ).canonicalBytes;
        expect(bytes, orderedEquals(reference));
      },
    );

    test('throws SurfacePayloadException naming the path when the flow '
        'is missing', () async {
      final missing = p.join(
        tempDir.path,
        'assets',
        'onboarding',
        'flows',
        'nope.flow.json',
      );

      expect(
        () => assembleSurfacePayloadBytes(missing),
        throwsA(
          isA<SurfacePayloadException>().having(
            (e) => e.message,
            'message',
            allOf(contains('nope.flow.json'), contains('build_runner')),
          ),
        ),
      );
    });

    test('throws when a referenced screen blob is missing', () async {
      final flowPath = await seedSurfaceFlow(tempDir);
      // Delete one referenced blob.
      final screensDir = p.join(
        tempDir.path,
        'assets',
        'onboarding',
        'screens',
      );
      await File(p.join(screensDir, 'welcome.rfw')).delete();

      expect(
        () => assembleSurfacePayloadBytes(flowPath),
        throwsA(
          isA<SurfacePayloadException>().having(
            (e) => e.message,
            'message',
            allOf(contains('welcome.rfw'), contains('build_runner')),
          ),
        ),
      );
    });

    test(
      'throws a stale-blob error when a blob no longer matches its hash',
      () async {
        final flowPath = await seedSurfaceFlow(tempDir);
        // Corrupt a blob so its SHA-256 diverges from the flow document.
        final screensDir = p.join(
          tempDir.path,
          'assets',
          'onboarding',
          'screens',
        );
        await File(
          p.join(screensDir, 'value.rfw'),
        ).writeAsBytes(<int>[0, 1, 2, 3, 4, 5]);

        expect(
          () => assembleSurfacePayloadBytes(flowPath),
          throwsA(
            isA<SurfacePayloadException>().having(
              (e) => e.message,
              'message',
              allOf(contains('stale'), contains('build_runner')),
            ),
          ),
        );
      },
    );

    test(
      'unions required libraries across the flow screens into the payload',
      () async {
        final flowPath = await seedSurfaceFlow(tempDir);
        final screensDir = p.join(
          tempDir.path,
          'assets',
          'onboarding',
          'screens',
        );
        // Override two screens' sidecars with custom requirements (the blob
        // hash is recomputed from the real blob so the tie still holds): a
        // namespace shared across both at DIFFERENT versions (the max wins) +
        // a screen-unique namespace. The other screens stay baseline (empty).
        await seedCapabilitySidecar(
          p.join(screensDir, 'welcome.rfw'),
          requiredLibraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
            LibraryRequirement(namespace: 'acme.charts', minVersion: 1),
          ],
        );
        await seedCapabilitySidecar(
          p.join(screensDir, 'value.rfw'),
          requiredLibraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 5),
          ],
        );

        final bytes = await assembleSurfacePayloadBytes(flowPath);
        final decoded = SurfacePayload.decode(bytes) as FlowSurfacePayload;
        // The flow envelope requires every custom library any screen needs, at
        // the highest version any screen requires, canonical by namespace.
        expect(decoded.requiredLibraries, const [
          LibraryRequirement(namespace: 'acme.charts', minVersion: 1),
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 5),
        ]);
      },
    );

    test(
      'a stale screen sidecar (hash mismatch) fails the flow publish closed',
      () async {
        final flowPath = await seedSurfaceFlow(tempDir);
        final screensDir = p.join(
          tempDir.path,
          'assets',
          'onboarding',
          'screens',
        );
        // A screen sidecar whose recorded hash does not match its blob — the
        // analogue of the paywall stale-sidecar case, on the flow path.
        await seedCapabilitySidecar(
          p.join(screensDir, 'welcome.rfw'),
          blobSha256Override: 'sha256:${'0' * 64}',
        );
        expect(
          () => assembleSurfacePayloadBytes(flowPath),
          throwsA(
            isA<SurfacePayloadException>().having(
              (e) => e.message,
              'message',
              allOf(contains('stale'), contains('welcome')),
            ),
          ),
        );
      },
    );

    test('a malformed flow (traversal artifact path) is rejected as malformed '
        'before any blob read — not mislabelled stale', () async {
      final flowPath = await seedSurfaceFlow(tempDir);
      // Rewrite one screen artifact path to a directory-traversal value.
      // The document still parses, but its path rules reject the traversal;
      // validation must fire before the assembler reads any blob, so the
      // read never escapes the screens directory.
      final raw = await File(flowPath).readAsString();
      expect(raw, contains('"path":"welcome.rfw"'));
      await File(flowPath).writeAsString(
        raw.replaceFirst('"path":"welcome.rfw"', '"path":"../../escape.rfw"'),
      );

      expect(
        () => assembleSurfacePayloadBytes(flowPath),
        throwsA(
          isA<SurfacePayloadException>()
              .having((e) => e.message, 'message', contains('malformed'))
              .having((e) => e.message, 'not stale', isNot(contains('stale')))
              .having(
                (e) => e.message,
                'not a blob read',
                isNot(contains('escape.rfw')),
              ),
        ),
      );
    });
  });

  group('unionRequiredLibraries', () {
    test('empty input → empty', () {
      expect(unionRequiredLibraries(const []), isEmpty);
      expect(
        unionRequiredLibraries(const [<LibraryRequirement>[], []]),
        isEmpty,
      );
    });

    test('takes the max minVersion per namespace, canonical by namespace', () {
      final result = unionRequiredLibraries(const [
        [
          LibraryRequirement(namespace: 'zeta', minVersion: 2),
          LibraryRequirement(namespace: 'acme', minVersion: 3),
        ],
        [LibraryRequirement(namespace: 'zeta', minVersion: 7)],
      ]);
      expect(result, const [
        LibraryRequirement(namespace: 'acme', minVersion: 3),
        LibraryRequirement(namespace: 'zeta', minVersion: 7),
      ]);
    });
  });

  group('publishCapabilityWarning', () {
    test(
      'returns null for a baseline-only surface (nothing to warn about)',
      () {
        final manifest = CapabilityManifest(
          builtInFloor: kBaselineCatalogVersion,
          requiredLibraries: const [],
        );
        expect(publishCapabilityWarning(manifest), isNull);
      },
    );

    test('names the built-in catalog version when above baseline', () {
      final manifest = CapabilityManifest(
        builtInFloor: 5,
        requiredLibraries: const [],
      );
      final warning = publishCapabilityWarning(manifest);
      expect(warning, isNotNull);
      expect(warning, contains('catalog'));
      expect(warning, contains('5'));
    });

    test('names each required custom library', () {
      final manifest = CapabilityManifest(
        builtInFloor: kBaselineCatalogVersion,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ],
      );
      final warning = publishCapabilityWarning(manifest);
      expect(warning, isNotNull);
      expect(warning, contains('acme.widgets'));
      expect(warning, contains('2'));
    });

    test('names both the catalog version and the custom libraries', () {
      final manifest = CapabilityManifest(
        builtInFloor: 7,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
        ],
      );
      final warning = publishCapabilityWarning(manifest)!;
      expect(warning, contains('7'));
      expect(warning, contains('acme.widgets'));
    });
  });

  group('assembleBlobSurfacePayloadBytes (single .rfw blob)', () {
    String sidecarOf(String rfwPath) => p.join(
      p.dirname(rfwPath),
      '${p.basenameWithoutExtension(rfwPath)}.capability.json',
    );

    Future<void> writeManifest(
      String rfwPath,
      int builtInFloor, {
      List<LibraryRequirement> requiredLibraries = const [],
      String? blobSha256Override,
    }) async {
      final blob = await File(rfwPath).readAsBytes();
      await File(sidecarOf(rfwPath)).writeAsString(
        jsonEncode(
          CapabilitySidecar(
            blobSha256: blobSha256Override ?? CapabilitySidecar.hashBlob(blob),
            manifest: CapabilityManifest(
              builtInFloor: builtInFloor,
              requiredLibraries: requiredLibraries,
            ),
          ).toJson(),
        ),
      );
    }

    test(
      'assembles canonical bytes that round-trip via SurfacePayload.decode, '
      'stamping the derived floor read from the capability sidecar',
      () async {
        final rfwPath = p.join(tempDir.path, 'serene.rfw');
        final rfwBytes = Uint8List.fromList(
          List<int>.generate(64, (i) => (i * 7) % 256),
        );
        await File(rfwPath).writeAsBytes(rfwBytes);
        await writeManifest(rfwPath, 3);

        final bytes = await assembleBlobSurfacePayloadBytes(rfwPath);

        // The canonical frame the backend re-decodes at publish time.
        final decoded = SurfacePayload.decode(bytes);
        expect(decoded, isA<BlobSurfacePayload>());
        final blob = decoded as BlobSurfacePayload;
        expect(blob.minClient, 3);
        expect(blob.blob, orderedEquals(rfwBytes));

        // Divergence guard: the production assembler must emit exactly the
        // canonical bytes a direct BlobSurfacePayload(...) build produces — the
        // same bytes the backend serve round-trip pins.
        final reference = BlobSurfacePayload(
          minClient: 3,
          blob: rfwBytes,
        ).canonicalBytes;
        expect(bytes, orderedEquals(reference));
      },
    );

    test(
      'stamps the derived floor and required libraries from the sidecar',
      () async {
        final rfwPath = p.join(tempDir.path, 'serene.rfw');
        await File(rfwPath).writeAsBytes(Uint8List.fromList(const [1, 2, 3]));
        await writeManifest(
          rfwPath,
          5,
          requiredLibraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          ],
        );

        final bytes = await assembleBlobSurfacePayloadBytes(rfwPath);
        final decoded = SurfacePayload.decode(bytes) as BlobSurfacePayload;
        expect(decoded.minClient, 5);
        expect(decoded.requiredLibraries, const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ]);
      },
    );

    test('throws SurfacePayloadException naming the path when the .rfw is '
        'missing', () async {
      final missing = p.join(tempDir.path, 'assets', 'paywalls', 'nope.rfw');

      expect(
        () => assembleBlobSurfacePayloadBytes(missing),
        throwsA(
          isA<SurfacePayloadException>().having(
            (e) => e.message,
            'message',
            contains('nope.rfw'),
          ),
        ),
      );
    });

    test('throws SurfacePayloadException when the sidecar is stale relative to '
        'the blob (content-hash mismatch)', () async {
      final rfwPath = p.join(tempDir.path, 'serene.rfw');
      await File(rfwPath).writeAsBytes(Uint8List.fromList(const [1, 2, 3]));
      // A sidecar whose recorded hash does not match the blob — the blob
      // changed after the sidecar was written, or the sidecar is from a
      // different build. Without the hash tie this would silently under-stamp.
      await writeManifest(rfwPath, 3, blobSha256Override: 'sha256:${'0' * 64}');
      expect(
        () => assembleBlobSurfacePayloadBytes(rfwPath),
        throwsA(
          isA<SurfacePayloadException>().having(
            (e) => e.message,
            'message',
            allOf(contains('stale'), contains('serene.rfw')),
          ),
        ),
      );
    });

    test(
      'throws SurfacePayloadException when the capability sidecar is missing',
      () async {
        final rfwPath = p.join(tempDir.path, 'serene.rfw');
        await File(rfwPath).writeAsBytes(Uint8List.fromList(const [1, 2, 3]));
        // No sidecar written — the manifest is a required build artifact.
        expect(
          () => assembleBlobSurfacePayloadBytes(rfwPath),
          throwsA(
            isA<SurfacePayloadException>().having(
              (e) => e.message,
              'message',
              contains('capability'),
            ),
          ),
        );
      },
    );
  });
}
