// Exact wire vectors deliberately remain single literal strings for review.
// ignore_for_file: lines_longer_than_80_chars, use_raw_strings

import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('SurfaceScreenEventSchema', () {
    test('matches the frozen empty and ordered canonical vectors', () {
      final empty = SurfaceScreenEventSchema(events: const []);
      expect(
        SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(empty),
        '{"schemaVersion":1,"events":[]}',
      );
      expect(
        SurfaceScreenEventContractHash.hash(empty),
        'sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5',
      );

      final schema = SurfaceScreenEventSchema(
        events: <SurfaceScreenEvent>[
          SurfaceScreenEvent(
            id: 'submit',
            arguments: SurfaceScreenEventObjectArguments(
              const SurfaceScreenEventMapShapeV1(
                SurfaceScreenEventScalarShapeV1(
                  SurfaceScreenEventScalarKind.jsonValue,
                ),
              ),
            ),
          ),
          SurfaceScreenEvent(
            id: 'évent',
            arguments: const SurfaceScreenEventValueArguments(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKind.integer,
              ),
            ),
          ),
          SurfaceScreenEvent(
            id: 'dismiss\n',
            arguments: const SurfaceScreenEventNoArguments(),
          ),
        ],
      );
      expect(
        SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(schema),
        '{"schemaVersion":1,"events":[{"id":"dismiss\\n","arguments":{"encoding":"none"}},{"id":"submit","arguments":{"encoding":"object","shape":{"kind":"map","values":{"kind":"jsonValue"}}}},{"id":"évent","arguments":{"encoding":"value","shape":{"kind":"int"}}}]}',
      );
      expect(
        SurfaceScreenEventContractHash.hash(schema),
        'sha256:e8e6e96e91b1fa3ebab975bf91b75ddb201b88da6d5d3bb2baab4437546be450',
      );
    });

    test('rejects unknown, duplicate, unsupported, and invalid event values',
        () {
      expect(
        () => SurfaceScreenEventSchemaV1Codec.decodeJson(
          '{"schemaVersion":1,"events":[],"future":true}',
        ),
        throwsFormatException,
      );
      expect(
        () => SurfaceScreenEventSchemaV1Codec.decodeJson(
          '{"schemaVersion":1,"events":[{"id":"same","arguments":{"encoding":"none"}},{"id":"same","arguments":{"encoding":"none"}}]}',
        ),
        throwsFormatException,
      );
      expect(
        () => SurfaceScreenEventArguments.fromJson(
          <String, Object?>{
            'encoding': 'object',
            'shape': <String, Object?>{'kind': 'string'},
          },
          path: r'$.arguments',
        ),
        throwsFormatException,
      );

      final schema = SurfaceScreenEventSchema(
        events: <SurfaceScreenEvent>[
          SurfaceScreenEvent(
            id: 'count',
            arguments: const SurfaceScreenEventValueArguments(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKind.integer,
              ),
            ),
          ),
        ],
      );
      expect(
        () => schema.validateEvent('missing', const <String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => schema
            .validateEvent('count', const <String, Object?>{'value': 1.0}),
        throwsFormatException,
      );
    });
  });

  group('SurfaceScreenContractFingerprint', () {
    test('matches the frozen empty and Unicode canonical vectors', () {
      const zeroHash =
          'sha256:0000000000000000000000000000000000000000000000000000000000000000';
      final emptyCapabilities = CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const <LibraryRequirement>[],
      );
      expect(
        SurfaceScreenContractFingerprint.encodeCanonicalJson(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: emptyCapabilities,
          eventContractHash: zeroHash,
        ),
        '{"schemaVersion":1,"sourceKind":"screen","payloadKind":"blob","capabilities":{"builtInFloor":1,"requiredLibraries":[]},"eventContractHash":"$zeroHash"}',
      );
      expect(
        SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: emptyCapabilities,
          eventContractHash: zeroHash,
        ),
        'sha256:005037b32bb08a0a055114c6af93c430b99ee4508806aedb1b163fdcd69dbb7b',
      );

      const oneHash =
          'sha256:1111111111111111111111111111111111111111111111111111111111111111';
      final capabilities = CapabilityManifest(
        builtInFloor: 7,
        requiredLibraries: const <LibraryRequirement>[
          LibraryRequirement(namespace: 'é.core', minVersion: 3),
          LibraryRequirement(namespace: 'z/quote"slash\\', minVersion: 2),
          LibraryRequirement(namespace: 'a\u001fedge', minVersion: 1),
        ],
      );
      expect(
        SurfaceScreenContractFingerprint.encodeCanonicalJson(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: capabilities,
          eventContractHash: oneHash,
        ),
        '{"schemaVersion":1,"sourceKind":"screen","payloadKind":"blob","capabilities":{"builtInFloor":7,"requiredLibraries":[{"namespace":"a\\u001fedge","minVersion":1},{"namespace":"z/quote\\"slash\\\\","minVersion":2},{"namespace":"é.core","minVersion":3}]},"eventContractHash":"$oneHash"}',
      );
      expect(
        SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: capabilities,
          eventContractHash: oneHash,
        ),
        'sha256:18d0b8a332b67fb830a934913e410d0906904347e30a9dfba1036156bc8a5b60',
      );
    });

    test('rejects duplicate library requirements before hashing', () {
      final duplicateCapabilities = CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const <LibraryRequirement>[
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 1),
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ],
      );
      expect(
        () => SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: duplicateCapabilities,
          eventContractHash:
              'sha256:0000000000000000000000000000000000000000000000000000000000000000',
        ),
        throwsFormatException,
      );
    });
  });

  group('Surface publication contracts', () {
    test('freezes the manifest and upload wire vectors', () {
      final fixture = _screenFixture();
      final manifestJson =
          SurfacePublicationManifestV1Codec.encodeCanonicalJson(
        fixture.manifest,
      );
      final uploadJson =
          SurfacePublicationUploadRequestV1Codec.encodeCanonicalJson(
        fixture.upload,
      );

      expect(manifestJson, _screenManifestGolden);
      expect(uploadJson, _screenUploadGolden);
      expect(
        SurfacePublicationManifestV1Codec.decodeJson(manifestJson)
            .publications
            .single
            .publication
            .surface,
        Surface.general,
      );
      expect(
        SurfacePublicationUploadRequestV1Codec.decodeJson(uploadJson)
            .publication
            .contractVersion,
        7,
      );
    });

    test('records authoring source paths and keeps their order strict', () {
      final fixture = _screenFixture();
      final entry = fixture.manifest.publications.single;

      // Absent sources stay absent on the wire, so an entry generated before
      // path resolution existed round-trips byte-identically.
      expect(entry.sources, isEmpty);
      expect(entry.toJson().containsKey('sources'), isFalse);

      final withSources = SurfacePublicationManifestEntry(
        artifacts: entry.artifacts,
        publication: entry.publication,
        sources: const <String>[
          'lib/screens/feature_announcement.dart',
          'lib/screens/shared_header.dart',
        ],
      );
      final manifest = SurfacePublicationManifest(
        publications: <SurfacePublicationManifestEntry>[withSources],
      );
      final encoded =
          SurfacePublicationManifestV1Codec.encodeCanonicalJson(manifest);
      expect(
        encoded,
        contains(
          '"sources":["lib/screens/feature_announcement.dart",'
          '"lib/screens/shared_header.dart"]',
        ),
      );
      expect(
        SurfacePublicationManifestV1Codec.decodeJson(encoded)
            .publications
            .single
            .sources,
        withSources.sources,
      );
      expect(
        manifest.validateArtifactClosure(fixture.files),
        hasLength(1),
      );

      SurfacePublicationManifestEntry withRawSources(List<String> sources) =>
          SurfacePublicationManifestEntry(
            artifacts: entry.artifacts,
            publication: entry.publication,
            sources: sources,
          );

      // Unsorted, duplicated, absolute, traversing, non-Dart, and empty
      // values are all rejected rather than normalized, so the canonical
      // bytes cannot depend on who assembled the manifest.
      for (final rejected in <List<String>>[
        <String>['lib/b.dart', 'lib/a.dart'],
        <String>['lib/a.dart', 'lib/a.dart'],
        <String>['/lib/a.dart'],
        <String>['lib/../a.dart'],
        <String>['lib/a.txt'],
        <String>[''],
      ]) {
        expect(
          () => withRawSources(rejected),
          throwsFormatException,
          reason: 'sources $rejected must be rejected',
        );
      }

      // A decode failure names the entry it came from, not a bare
      // "entry.sources[0]" that could belong to any of them.
      expect(
        () => SurfacePublicationManifestV1Codec.decodeJson(
          encoded.replaceFirst(
            '"lib/screens/feature_announcement.dart",',
            '"lib/screens/zzz.dart",',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(r'$.publications[0].sources'),
          ),
        ),
      );

      expect(
        () => SurfacePublicationManifestEntry.fromJson(
          <String, Object?>{
            'artifacts': <Object?>[
              for (final artifact in entry.artifacts) artifact.toJson(),
            ],
            'publication': entry.publication.toJson(),
            'sources': <Object?>[42],
          },
          path: r'$',
        ),
        throwsFormatException,
      );
    });

    test('verifies declared artifacts, sidecars, and assembled payload bytes',
        () {
      final fixture = _screenFixture();
      final closures = fixture.manifest.validateArtifactClosure(fixture.files);
      closures.single.validateAssembledPayload(fixture.payload.canonicalBytes);

      final stale = Map<String, List<int>>.from(fixture.files)
        ..[fixture.sidecarPath] = utf8.encode('{"blobSha256":"sha256:0"}');
      expect(
        () => fixture.manifest.validateArtifactClosure(stale),
        throwsFormatException,
      );
      expect(
        () => SurfacePublicationUploadRequest(
          publication: fixture.publication,
          payload: const <int>[1, 2, 3],
        ),
        throwsFormatException,
      );
    });

    test(
        'accepts payload-relative flow paths while keeping IDs and hashes strict',
        () {
      final fixture = _flowFixture();
      final entry = fixture.manifest.publications.single;
      final flowArtifact =
          fixture.payload.flowDocument.screenArtifacts['start']!;
      final blobArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      );
      final sidecarArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.capabilitySidecar,
      );

      expect(flowArtifact.path, 'start.rfw');
      expect(
        blobArtifact.path,
        'assets/restage/generated/welcome/start.rfw',
      );
      expect(flowArtifact.path, isNot(blobArtifact.path));
      fixture.manifest
          .validateArtifactClosure(fixture.files)
          .single
          .validateAssembledPayload(fixture.payload.canonicalBytes);

      final wrongIdManifest = SurfacePublicationManifest(
        publications: <SurfacePublicationManifestEntry>[
          SurfacePublicationManifestEntry(
            artifacts: <SurfacePublicationArtifact>[
              for (final artifact in entry.artifacts)
                artifact.role == SurfacePublicationArtifactRole.flowDocument
                    ? artifact
                    : SurfacePublicationArtifact(
                        contentHash: artifact.contentHash,
                        id: 'unexpected',
                        path: artifact.path,
                        role: artifact.role,
                      ),
            ],
            publication: entry.publication,
          ),
        ],
      );
      expect(
        () => wrongIdManifest.validateArtifactClosure(fixture.files),
        throwsFormatException,
      );

      final changedBlob = Uint8List.fromList(const <int>[7, 8, 6]);
      final changedSidecarBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            CapabilitySidecar(
              blobSha256: CapabilitySidecar.hashBlob(changedBlob),
              manifest: CapabilityManifest(
                builtInFloor: fixture.payload.flowDocument.minClient,
                requiredLibraries: fixture.payload.requiredLibraries,
              ),
            ).toJson(),
          ),
        ),
      );
      final wrongHashManifest = SurfacePublicationManifest(
        publications: <SurfacePublicationManifestEntry>[
          SurfacePublicationManifestEntry(
            artifacts: <SurfacePublicationArtifact>[
              for (final artifact in entry.artifacts)
                if (artifact.path == blobArtifact.path)
                  SurfacePublicationArtifact(
                    contentHash: CapabilitySidecar.hashBlob(changedBlob),
                    id: artifact.id,
                    path: artifact.path,
                    role: artifact.role,
                  )
                else if (artifact.path == sidecarArtifact.path)
                  SurfacePublicationArtifact(
                    contentHash:
                        CapabilitySidecar.hashBlob(changedSidecarBytes),
                    id: artifact.id,
                    path: artifact.path,
                    role: artifact.role,
                  )
                else
                  artifact,
            ],
            publication: entry.publication,
          ),
        ],
      );
      final wrongHashFiles = Map<String, List<int>>.from(fixture.files)
        ..[blobArtifact.path] = changedBlob
        ..[sidecarArtifact.path] = changedSidecarBytes;
      expect(
        () => wrongHashManifest.validateArtifactClosure(wrongHashFiles),
        throwsFormatException,
      );

      final underDeclaredSidecarBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            CapabilitySidecar(
              blobSha256: CapabilitySidecar.hashBlob(
                fixture.payload.screenBlobs['start']!,
              ),
              manifest: CapabilityManifest(
                builtInFloor: 1,
                requiredLibraries: const <LibraryRequirement>[],
              ),
            ).toJson(),
          ),
        ),
      );
      final underDeclaredArtifacts = <SurfacePublicationArtifact>[
        for (final artifact in entry.artifacts)
          artifact.role == SurfacePublicationArtifactRole.capabilitySidecar
              ? SurfacePublicationArtifact(
                  contentHash: CapabilitySidecar.hashBlob(
                    underDeclaredSidecarBytes,
                  ),
                  id: artifact.id,
                  path: artifact.path,
                  role: artifact.role,
                )
              : artifact,
      ];
      final underDeclaredManifest = SurfacePublicationManifest(
        publications: <SurfacePublicationManifestEntry>[
          SurfacePublicationManifestEntry(
            artifacts: underDeclaredArtifacts,
            publication: entry.publication,
          ),
        ],
      );
      final underDeclaredFiles = Map<String, List<int>>.from(fixture.files);
      final underDeclaredPath = entry.artifacts
          .singleWhere(
            (artifact) =>
                artifact.role ==
                SurfacePublicationArtifactRole.capabilitySidecar,
          )
          .path;
      underDeclaredFiles[underDeclaredPath] = underDeclaredSidecarBytes;
      expect(
        () => underDeclaredManifest
            .validateArtifactClosure(underDeclaredFiles)
            .single
            .validateAssembledPayload(fixture.payload.canonicalBytes),
        throwsFormatException,
      );
    });

    test('allows a flow and standalone publication to share source artifacts',
        () {
      final fixture = _flowFixture();
      final flowEntry = fixture.manifest.publications.single;
      final sharedArtifacts = flowEntry.artifacts
          .where(
            (artifact) =>
                artifact.role != SurfacePublicationArtifactRole.flowDocument,
          )
          .toList(growable: false);
      final sharedBlob = sharedArtifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      );
      final sharedSidecar = sharedArtifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.capabilitySidecar,
      );
      final capabilities = CapabilityManifest(
        builtInFloor: fixture.payload.flowDocument.minClient,
        requiredLibraries: fixture.payload.requiredLibraries,
      );
      final eventContract = SurfaceScreenEventSchema(events: const []);
      final eventContractHash =
          SurfaceScreenEventContractHash.hash(eventContract);
      final contractFingerprint = SurfaceScreenContractFingerprint.hash(
        sourceKind: SurfaceSourceKind.screen,
        payloadKind: SurfacePayloadKind.blob,
        capabilities: capabilities,
        eventContractHash: eventContractHash,
      );
      final standalonePayload = BlobSurfacePayload(
        minClient: fixture.payload.flowDocument.minClient,
        blob: fixture.payload.screenBlobs['start']!,
        requiredLibraries: fixture.payload.requiredLibraries,
      );
      SurfacePublication publicationForSlug(String slug) => SurfacePublication(
            surface: Surface.general,
            slug: slug,
            sourceKind: SurfaceSourceKind.screen,
            payloadKind: SurfacePayloadKind.blob,
            payloadContentHash: standalonePayload.contentHash,
            contractVersion: 1,
            capabilities: capabilities,
            eventContract: eventContract,
            eventContractHash: eventContractHash,
            contractFingerprint: contractFingerprint,
          );
      final standalonePublication = publicationForSlug('start');
      final standaloneEntry = SurfacePublicationManifestEntry(
        artifacts: sharedArtifacts,
        publication: standalonePublication,
      );
      final manifest = SurfacePublicationManifest(
        publications: <SurfacePublicationManifestEntry>[
          flowEntry,
          standaloneEntry,
        ],
      );

      final closures = manifest.validateArtifactClosure(fixture.files);
      expect(closures, hasLength(2));
      closures[0].validateAssembledPayload(fixture.payload.canonicalBytes);
      closures[1].validateAssembledPayload(standalonePayload.canonicalBytes);

      expect(
        () => SurfacePublicationManifestEntry(
          artifacts: <SurfacePublicationArtifact>[
            sharedBlob,
            SurfacePublicationArtifact(
              contentHash: sharedSidecar.contentHash,
              id: sharedSidecar.id,
              path: sharedBlob.path,
              role: sharedSidecar.role,
            ),
          ],
          publication: standalonePublication,
        ),
        throwsFormatException,
      );
      expect(
        () => SurfacePublicationManifest(
          publications: <SurfacePublicationManifestEntry>[
            flowEntry,
            flowEntry,
          ],
        ),
        throwsFormatException,
      );

      const conflictingHash =
          'sha256:0000000000000000000000000000000000000000000000000000000000000000';
      final conflictingEntries = <({
        String name,
        SurfacePublicationManifestEntry entry,
      })>[
        (
          name: 'hash',
          entry: SurfacePublicationManifestEntry(
            artifacts: <SurfacePublicationArtifact>[
              for (final artifact in sharedArtifacts)
                artifact.role == SurfacePublicationArtifactRole.screenBlob
                    ? SurfacePublicationArtifact(
                        contentHash: conflictingHash,
                        id: artifact.id,
                        path: artifact.path,
                        role: artifact.role,
                      )
                    : artifact,
            ],
            publication: standalonePublication,
          ),
        ),
        (
          name: 'role',
          entry: SurfacePublicationManifestEntry(
            artifacts: <SurfacePublicationArtifact>[
              SurfacePublicationArtifact(
                contentHash: sharedBlob.contentHash,
                id: sharedBlob.id,
                path: sharedBlob.path,
                role: SurfacePublicationArtifactRole.capabilitySidecar,
              ),
              SurfacePublicationArtifact(
                contentHash: sharedSidecar.contentHash,
                id: sharedSidecar.id,
                path: sharedSidecar.path,
                role: SurfacePublicationArtifactRole.screenBlob,
              ),
            ],
            publication: standalonePublication,
          ),
        ),
        (
          name: 'id',
          entry: SurfacePublicationManifestEntry(
            artifacts: <SurfacePublicationArtifact>[
              for (final artifact in sharedArtifacts)
                SurfacePublicationArtifact(
                  contentHash: artifact.contentHash,
                  id: 'alternate',
                  path: artifact.path,
                  role: artifact.role,
                ),
            ],
            publication: publicationForSlug('alternate'),
          ),
        ),
      ];
      for (final conflict in conflictingEntries) {
        expect(
          () => SurfacePublicationManifest(
            publications: <SurfacePublicationManifestEntry>[
              flowEntry,
              conflict.entry,
            ],
          ),
          throwsFormatException,
          reason: 'conflicting shared artifact ${conflict.name}',
        );
      }
    });

    test('rejects incomplete, orphaned, and duplicate artifact closures', () {
      final fixture = _flowFixture();
      final entry = fixture.manifest.publications.single;
      final flowArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.flowDocument,
      );
      final blobArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      );
      final sidecarArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.capabilitySidecar,
      );
      final invalidClosures = <({
        String name,
        List<SurfacePublicationArtifact> artifacts,
      })>[
        (
          name: 'missing blob/orphaned sidecar',
          artifacts: <SurfacePublicationArtifact>[
            flowArtifact,
            sidecarArtifact,
          ],
        ),
        (
          name: 'missing sidecar/orphaned blob',
          artifacts: <SurfacePublicationArtifact>[
            flowArtifact,
            blobArtifact,
          ],
        ),
        (
          name: 'missing flow document',
          artifacts: <SurfacePublicationArtifact>[
            blobArtifact,
            sidecarArtifact,
          ],
        ),
        (
          name: 'duplicate flow document',
          artifacts: <SurfacePublicationArtifact>[
            ...entry.artifacts,
            SurfacePublicationArtifact(
              contentHash: flowArtifact.contentHash,
              path: 'assets/restage/generated/welcome/flow-copy.json',
              role: SurfacePublicationArtifactRole.flowDocument,
            ),
          ],
        ),
        (
          name: 'duplicate blob id',
          artifacts: <SurfacePublicationArtifact>[
            ...entry.artifacts,
            SurfacePublicationArtifact(
              contentHash: blobArtifact.contentHash,
              id: blobArtifact.id,
              path: 'assets/restage/generated/welcome/start-copy.rfw',
              role: SurfacePublicationArtifactRole.screenBlob,
            ),
          ],
        ),
        (
          name: 'duplicate sidecar id',
          artifacts: <SurfacePublicationArtifact>[
            ...entry.artifacts,
            SurfacePublicationArtifact(
              contentHash: sidecarArtifact.contentHash,
              id: sidecarArtifact.id,
              path:
                  'assets/restage/generated/welcome/start-copy.capability.json',
              role: SurfacePublicationArtifactRole.capabilitySidecar,
            ),
          ],
        ),
      ];

      for (final invalid in invalidClosures) {
        expect(
          () => SurfacePublicationManifestEntry(
            artifacts: invalid.artifacts,
            publication: entry.publication,
          ),
          throwsFormatException,
          reason: invalid.name,
        );
      }
    });

    test('validates paywall blob and paywall-flow adapter closures', () {
      final screenFixture = _screenFixture();
      final paywallBlobPublication = SurfacePublication(
        surface: Surface.paywall,
        slug: screenFixture.publication.slug,
        sourceKind: SurfaceSourceKind.paywall,
        payloadKind: SurfacePayloadKind.blob,
        payloadContentHash: screenFixture.payload.contentHash,
      );
      final paywallBlobManifest = SurfacePublicationManifest(
        publications: <SurfacePublicationManifestEntry>[
          SurfacePublicationManifestEntry(
            artifacts: screenFixture.manifest.publications.single.artifacts,
            publication: paywallBlobPublication,
          ),
        ],
      );
      paywallBlobManifest
          .validateArtifactClosure(screenFixture.files)
          .single
          .validateAssembledPayload(screenFixture.payload.canonicalBytes);

      final flowFixture = _flowFixture();
      final paywallFlowPublication = SurfacePublication(
        surface: Surface.paywall,
        slug: flowFixture.payload.flowDocument.flow,
        sourceKind: SurfaceSourceKind.paywall,
        payloadKind: SurfacePayloadKind.flow,
        payloadContentHash: flowFixture.payload.contentHash,
        deliveryMode: flowFixture.payload.flowDocument.deliveryMode,
      );
      final paywallFlowManifest = SurfacePublicationManifest(
        publications: <SurfacePublicationManifestEntry>[
          SurfacePublicationManifestEntry(
            artifacts: flowFixture.manifest.publications.single.artifacts,
            publication: paywallFlowPublication,
          ),
        ],
      );
      paywallFlowManifest
          .validateArtifactClosure(flowFixture.files)
          .single
          .validateAssembledPayload(flowFixture.payload.canonicalBytes);
    });

    test('rejects unknown wire discriminators and unsafe artifact paths', () {
      final fixture = _screenFixture();
      final publicationJson = fixture.publication.toJson();
      for (final unknown in const <({String field, String value})>[
        (field: 'surface', value: 'future'),
        (field: 'sourceKind', value: 'futureSource'),
        (field: 'payloadKind', value: 'futurePayload'),
      ]) {
        final malformed = Map<String, Object?>.from(publicationJson)
          ..[unknown.field] = unknown.value;
        expect(
          () => SurfacePublication.fromJson(
            malformed,
            path: r'$.publication',
          ),
          throwsFormatException,
          reason: 'unknown ${unknown.field}',
        );
      }

      final artifactJson = Map<String, Object?>.from(
        fixture.manifest.publications.single.artifacts.first.toJson(),
      )..['role'] = 'futureRole';
      expect(
        () => SurfacePublicationArtifact.fromJson(
          artifactJson,
          path: r'$.artifact',
        ),
        throwsFormatException,
      );

      const contentHash =
          'sha256:0000000000000000000000000000000000000000000000000000000000000000';
      expect(
        SurfacePublicationArtifact(
          contentHash: contentHash,
          id: 'screen',
          path: 'assets/restage/generated/welcome/start.rfw',
          role: SurfacePublicationArtifactRole.screenBlob,
        ).path,
        'assets/restage/generated/welcome/start.rfw',
      );
      for (final path in const <String>[
        '/outside.rfw',
        r'assets\outside.rfw',
        'assets/../outside.rfw',
        'assets/./outside.rfw',
        'assets//outside.rfw',
        'assets/restage/',
        'C:/outside.rfw',
        'file:/outside.rfw',
        'https://example.com/outside.rfw',
        'custom:outside.rfw',
      ]) {
        expect(
          () => SurfacePublicationArtifact(
            contentHash: contentHash,
            id: 'screen',
            path: path,
            role: SurfacePublicationArtifactRole.screenBlob,
          ),
          throwsFormatException,
          reason: path,
        );
      }
    });

    test('rejects unknown, null, and partial publication fields', () {
      final fixture = _screenFixture();
      final json = fixture.manifest.toJson();
      final entry = (json['publications']! as List<Object?>).single!
          as Map<String, Object?>;
      final publication = Map<String, Object?>.from(
        entry['publication']! as Map<String, Object?>,
      );
      publication['unknown'] = true;
      expect(
        () => SurfacePublication.fromJson(publication, path: r'$.publication'),
        throwsFormatException,
      );
      expect(
        () => SurfacePublicationArtifact(
          contentHash:
              'sha256:0000000000000000000000000000000000000000000000000000000000000000',
          id: 'screen',
          path: '../outside.rfw',
          role: SurfacePublicationArtifactRole.screenBlob,
        ),
        throwsFormatException,
      );
      publication
        ..remove('unknown')
        ..['contractFingerprint'] = null;
      expect(
        () => SurfacePublication.fromJson(publication, path: r'$.publication'),
        throwsFormatException,
      );
      publication
        ..remove('contractFingerprint')
        ..remove('eventContractHash');
      expect(
        () => SurfacePublication.fromJson(publication, path: r'$.publication'),
        throwsFormatException,
      );
    });
  });

  group('Surface screen delivery contracts', () {
    test('normalizes only advisory request keys and freezes the request vector',
        () {
      final normalized = SurfaceScreenDeliveryRequest.fromJson(
        <String, Object?>{
          'schemaVersion': 1,
          'surface': 'general',
          'slug': 'feature_announcement',
          'contractVersion': 7,
          'assignmentKey': ' actor ',
          'meteringKey': 'not-a-uuid',
        },
      );
      expect(normalized.assignmentKey, isNull);
      expect(normalized.meteringKey, isNull);

      final request = SurfaceScreenDeliveryRequest(
        surface: Surface.general,
        slug: 'feature_announcement',
        contractVersion: 7,
        assignmentKey: 'actor',
        meteringKey: 'D9428888-122B-4B0B-8B7F-3E23441121E8',
      );
      expect(
        SurfaceScreenDeliveryRequestV1Codec.encodeCanonicalJson(request),
        '{"schemaVersion":1,"surface":"general","slug":"feature_announcement","contractVersion":7,"assignmentKey":"actor","meteringKey":"D9428888-122B-4B0B-8B7F-3E23441121E8"}',
      );
      expect(
        () => SurfaceScreenDeliveryRequestV1Codec.decode(<String, Object?>{
          ...request.toJson(),
          'unknown': true,
        }),
        throwsFormatException,
      );
    });

    test('freezes complete responses and rejects partial present metadata', () {
      // The response type is no longer a wire type — it is what a reader
      // ASSEMBLES once it has fetched the content a descriptor names. So this
      // covers the two halves separately: the constructor's correlation rules,
      // which are unchanged and are the whole reason the type survived the wire
      // change, and the descriptor codec that now carries the wire.
      final fixture = _screenFixture();
      SurfaceDocument documentWithSlug(String slug) => SurfaceDocument(
            surfaceType: fixture.document.surfaceType,
            surfaceSlug: slug,
            version: fixture.document.version,
            minClient: fixture.document.minClient,
            requiredLibraries: fixture.document.requiredLibraries,
            payload: fixture.document.payload,
            publishedAt: fixture.document.publishedAt,
          );
      SurfaceScreenDeliveryResponse responseForDocument(
        SurfaceDocument document,
      ) =>
          SurfaceScreenDeliveryResponse(
            document: document,
            sourceKind: SurfaceSourceKind.screen,
            payloadKind: SurfacePayloadKind.blob,
            contractVersion: 7,
            publishedRevision: document.version,
            contractFingerprint: fixture.contractFingerprint,
            eventContractHash: fixture.eventContractHash,
          );
      expect(
        responseForDocument(documentWithSlug('écran_欢迎')).document.surfaceSlug,
        'écran_欢迎',
      );
      for (final slug in <String>[
        '',
        ' ',
        ' feature_announcement',
        'feature_announcement ',
        'feature\u0000announcement',
        String.fromCharCode(0xD800),
      ]) {
        expect(
          () => responseForDocument(documentWithSlug(slug)),
          throwsFormatException,
          reason: 'malformed document surfaceSlug',
        );
      }
      expect(
        () => SurfaceScreenDeliveryResponse(
          document: fixture.document,
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          contractVersion: 7,
          publishedRevision: 11,
          contractFingerprint: fixture.contractFingerprint,
          eventContractHash: fixture.eventContractHash,
        ),
        throwsFormatException,
        reason: 'publishedRevision must equal the document version',
      );

      final descriptor = SurfaceScreenDeliveryDescriptor(
        artifact: _screenArtifactDescriptor(fixture),
        sourceKind: SurfaceSourceKind.screen,
        contractVersion: 7,
        publishedRevision: 12,
        contractFingerprint: fixture.contractFingerprint,
        eventContractHash: fixture.eventContractHash,
        assignment: SurfaceExperimentAssignment(
          experimentId: 'exp_1',
          variantId: 'treatment',
          experimentEpoch: 3,
        ),
      );
      final descriptorJson =
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
        descriptor,
      );
      expect(descriptorJson, _screenDescriptorGolden);
      expect(
        SurfaceScreenDeliveryDescriptorV1Codec.decodeJson(descriptorJson)
            .assignment!
            .variantId,
        'treatment',
      );

      // The completion is the correlation: the fingerprint is recomputed
      // against the document assembled from fetched content, so a descriptor
      // whose fingerprint does not describe that content cannot complete.
      expect(
        descriptor.completeWith(fixture.document).publishedRevision,
        12,
      );

      final descriptorMap = descriptor.toJson();
      for (final field in const <String>[
        'schemaVersion',
        'artifact',
        'sourceKind',
        'contractVersion',
        'publishedRevision',
        'contractFingerprint',
        'eventContractHash',
      ]) {
        final missing = Map<String, Object?>.from(descriptorMap)..remove(field);
        final nulled = Map<String, Object?>.from(descriptorMap)..[field] = null;
        expect(
          () => SurfaceScreenDeliveryDescriptorV1Codec.decode(missing),
          throwsFormatException,
          reason: 'missing descriptor $field',
        );
        expect(
          () => SurfaceScreenDeliveryDescriptorV1Codec.decode(nulled),
          throwsFormatException,
          reason: 'null descriptor $field',
        );
      }
      for (final field in const <String>[
        'contractFingerprint',
        'eventContractHash',
      ]) {
        final malformed = Map<String, Object?>.from(descriptorMap)
          ..[field] = 'sha256:0';
        expect(
          () => SurfaceScreenDeliveryDescriptorV1Codec.decode(malformed),
          throwsFormatException,
          reason: 'malformed descriptor $field',
        );
      }
      expect(
        () => SurfaceScreenDeliveryDescriptorV1Codec.decode(<String, Object?>{
          ...descriptorMap,
          'unknown': true,
        }),
        throwsFormatException,
      );

      final partialAssignment = Map<String, Object?>.from(descriptorMap)
        ..['assignment'] = <String, Object?>{
          'experimentId': 'exp_1',
        };
      expect(
        () => SurfaceScreenDeliveryDescriptorV1Codec.decode(partialAssignment),
        throwsFormatException,
      );
      expect(
        () => SurfaceScreenDeliveryDescriptorV1Codec.decode(null),
        throwsFormatException,
      );
      expect(
        () => SurfaceScreenDeliveryDescriptorV1Codec.decode(<String, Object?>{
          ...descriptorMap,
          'assignment': null,
        }),
        throwsFormatException,
      );
      final withoutAssignment = Map<String, Object?>.from(descriptorMap)
        ..remove('assignment');
      expect(
        SurfaceScreenDeliveryDescriptorV1Codec.decode(withoutAssignment)
            .assignment,
        isNull,
      );

      // This wire delivers exactly one shape, so an artifact that makes no
      // shape claim — legitimate on the shape-agnostic route — is a missing
      // field here rather than a deliberate silence.
      final artifactMap = Map<String, Object?>.from(
        descriptorMap['artifact']! as Map<String, Object?>,
      )..remove('payloadKind');
      expect(
        () => SurfaceScreenDeliveryDescriptorV1Codec.decode(<String, Object?>{
          ...descriptorMap,
          'artifact': artifactMap,
        }),
        throwsFormatException,
      );
    });
  });
}

({
  SurfacePublicationManifest manifest,
  SurfacePublicationUploadRequest upload,
  SurfacePublication publication,
  BlobSurfacePayload payload,
  SurfaceDocument document,
  Map<String, List<int>> files,
  String sidecarPath,
  String eventContractHash,
  String contractFingerprint,
}) _screenFixture() {
  final capabilities = CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const <LibraryRequirement>[],
  );
  final eventContract = SurfaceScreenEventSchema(events: const []);
  final eventContractHash = SurfaceScreenEventContractHash.hash(eventContract);
  final contractFingerprint = SurfaceScreenContractFingerprint.hash(
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    capabilities: capabilities,
    eventContractHash: eventContractHash,
  );
  final payload = BlobSurfacePayload(
    minClient: 1,
    blob: Uint8List.fromList(const <int>[1, 2, 3]),
  );
  final publication = SurfacePublication(
    surface: Surface.general,
    slug: 'feature_announcement',
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    payloadContentHash: payload.contentHash,
    contractVersion: 7,
    capabilities: capabilities,
    eventContract: eventContract,
    eventContractHash: eventContractHash,
    contractFingerprint: contractFingerprint,
  );
  final sidecarBytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(payload.blob),
          manifest: capabilities,
        ).toJson(),
      ),
    ),
  );
  const blobPath = 'assets/restage/generated/feature_announcement/screen.rfw';
  const sidecarPath =
      'assets/restage/generated/feature_announcement/screen.capability.json';
  final manifest = SurfacePublicationManifest(
    publications: <SurfacePublicationManifestEntry>[
      SurfacePublicationManifestEntry(
        artifacts: <SurfacePublicationArtifact>[
          SurfacePublicationArtifact(
            contentHash: CapabilitySidecar.hashBlob(payload.blob),
            id: publication.slug,
            path: blobPath,
            role: SurfacePublicationArtifactRole.screenBlob,
          ),
          SurfacePublicationArtifact(
            contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
            id: publication.slug,
            path: sidecarPath,
            role: SurfacePublicationArtifactRole.capabilitySidecar,
          ),
        ],
        publication: publication,
      ),
    ],
  );
  final document = SurfaceDocument(
    surfaceType: Surface.general,
    surfaceSlug: publication.slug,
    version: 12,
    minClient: payload.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026, 8, 11),
  );
  return (
    manifest: manifest,
    upload: SurfacePublicationUploadRequest(
      publication: publication,
      payload: payload.canonicalBytes,
    ),
    publication: publication,
    payload: payload,
    document: document,
    files: <String, List<int>>{
      blobPath: payload.blob,
      sidecarPath: sidecarBytes,
    },
    sidecarPath: sidecarPath,
    eventContractHash: eventContractHash,
    contractFingerprint: contractFingerprint,
  );
}

({
  SurfacePublicationManifest manifest,
  FlowSurfacePayload payload,
  Map<String, List<int>> files,
}) _flowFixture() {
  final blob = Uint8List.fromList(const <int>[9, 8, 7]);
  const capability =
      LibraryRequirement(namespace: 'acme.widgets', minVersion: 2);
  final document = FlowDocument(
    flow: 'welcome',
    version: 1,
    schemaVersion: 1,
    minClient: 1,
    initial: 'start',
    screenArtifacts: <String, ScreenArtifact>{
      'start': ScreenArtifact(
        path: 'start.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.compute(blob),
      ),
    },
    states: const <String, FlowState>{
      'start': ScreenFlowState(
        screen: 'start',
        on: <String, FlowTransition>{'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: <String, Object?>{'completed': true}),
    },
    deliveryMode: FlowDeliveryMode.general,
  );
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: <String, Uint8List>{'start': blob},
    requiredLibraries: const <LibraryRequirement>[capability],
  );
  final sidecarBytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const <LibraryRequirement>[capability],
          ),
        ).toJson(),
      ),
    ),
  );
  const flowPath = 'assets/restage/generated/welcome/flow.json';
  const blobPath = 'assets/restage/generated/welcome/start.rfw';
  const sidecarPath = 'assets/restage/generated/welcome/start.capability.json';
  final flowBytes = Uint8List.fromList(
    utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
  );
  final publication = SurfacePublication(
    surface: Surface.general,
    slug: 'welcome',
    sourceKind: SurfaceSourceKind.flowGraph,
    payloadKind: SurfacePayloadKind.flow,
    payloadContentHash: payload.contentHash,
    deliveryMode: FlowDeliveryMode.general,
  );
  return (
    manifest: SurfacePublicationManifest(
      publications: <SurfacePublicationManifestEntry>[
        SurfacePublicationManifestEntry(
          artifacts: <SurfacePublicationArtifact>[
            SurfacePublicationArtifact(
              contentHash: CapabilitySidecar.hashBlob(flowBytes),
              path: flowPath,
              role: SurfacePublicationArtifactRole.flowDocument,
            ),
            SurfacePublicationArtifact(
              contentHash: CapabilitySidecar.hashBlob(blob),
              id: 'start',
              path: blobPath,
              role: SurfacePublicationArtifactRole.screenBlob,
            ),
            SurfacePublicationArtifact(
              contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
              id: 'start',
              path: sidecarPath,
              role: SurfacePublicationArtifactRole.capabilitySidecar,
            ),
          ],
          publication: publication,
        ),
      ],
    ),
    payload: payload,
    files: <String, List<int>>{
      flowPath: flowBytes,
      blobPath: blob,
      sidecarPath: sidecarBytes,
    },
  );
}

const String _screenManifestGolden =
    '{"schemaVersion":1,"publications":[{"artifacts":[{"contentHash":"sha256:039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81","id":"feature_announcement","path":"assets/restage/generated/feature_announcement/screen.rfw","role":"screenBlob"},{"contentHash":"sha256:bb3712909c6331779b86e5634d5bb13dff4cc12fd7c7da28a999114498e6d66c","id":"feature_announcement","path":"assets/restage/generated/feature_announcement/screen.capability.json","role":"capabilitySidecar"}],"publication":{"capabilities":{"builtInFloor":1,"requiredLibraries":[]},"contractFingerprint":"sha256:5876ace20d49d4af1c24e69867f9de9380688586256e67130f83bf99d0e96a9f","eventContract":{"schemaVersion":1,"events":[]},"eventContractHash":"sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5","payloadContentHash":"sha256:7caa614ebcc1800fb0e2aef7f4066c32f6589f6b62d3732901eb1d7d617f923d","payloadKind":"blob","slug":"feature_announcement","sourceKind":"screen","surface":"general","contractVersion":7}}]}';
const String _screenUploadGolden =
    '{"schemaVersion":1,"publication":{"capabilities":{"builtInFloor":1,"requiredLibraries":[]},"contractFingerprint":"sha256:5876ace20d49d4af1c24e69867f9de9380688586256e67130f83bf99d0e96a9f","eventContract":{"schemaVersion":1,"events":[]},"eventContractHash":"sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5","payloadContentHash":"sha256:7caa614ebcc1800fb0e2aef7f4066c32f6589f6b62d3732901eb1d7d617f923d","payloadKind":"blob","slug":"feature_announcement","sourceKind":"screen","surface":"general","contractVersion":7},"payload":"AAAABGJsb2IAAAABAAAAAwECAwAAAAA"}';

/// The descriptor a screen delivery puts on the wire, frozen.
///
/// Deliberately short. The document it used to inline is gone; what is left is
/// where the content is, what it must hash to, and the contract facts that
/// travel beside it — which is the whole point of the change.
const String _screenDescriptorGolden =
    '{"schemaVersion":1,"artifact":{"artifactPass":"v1.k1.4102444800.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","artifactUrl":"https://artifacts.example/artifacts/orgs/1/artifacts/1/sha256:7caa614ebcc1800fb0e2aef7f4066c32f6589f6b62d3732901eb1d7d617f923d","contentHash":"sha256:7caa614ebcc1800fb0e2aef7f4066c32f6589f6b62d3732901eb1d7d617f923d","descriptorVersion":1,"payloadFormatVersion":1,"payloadKind":"blob","publishedAtMicros":1786406400000000,"surfaceSlug":"feature_announcement","surfaceType":"general","version":12},"sourceKind":"screen","contractVersion":7,"publishedRevision":12,"contractFingerprint":"sha256:5876ace20d49d4af1c24e69867f9de9380688586256e67130f83bf99d0e96a9f","eventContractHash":"sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5","assignment":{"experimentId":"exp_1","variantId":"treatment","experimentEpoch":3}}';

/// The artifact half of the frozen descriptor above, built from the same
/// fixture so the two cannot drift apart.
SurfaceArtifactDescriptor _screenArtifactDescriptor(
  ({
    SurfacePublicationManifest manifest,
    SurfacePublicationUploadRequest upload,
    SurfacePublication publication,
    BlobSurfacePayload payload,
    SurfaceDocument document,
    Map<String, List<int>> files,
    String sidecarPath,
    String eventContractHash,
    String contractFingerprint,
  }) fixture,
) {
  final hash = fixture.payload.contentHash;
  return SurfaceArtifactDescriptor(
    payloadFormatVersion: 1,
    surfaceType: fixture.document.surfaceType,
    surfaceSlug: fixture.document.surfaceSlug,
    version: fixture.document.version,
    publishedAtMicros:
        fixture.document.publishedAt.toUtc().microsecondsSinceEpoch,
    contentHash: hash,
    artifactUrl: 'https://artifacts.example/artifacts/orgs/1/artifacts/1/$hash',
    artifactPass: 'v1.k1.4102444800.${'a' * 64}',
    payloadKind: SurfacePayloadKind.blob.wireName,
  );
}
