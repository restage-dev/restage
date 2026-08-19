// Exact wire vectors deliberately remain single literal strings for review.
// ignore_for_file: lines_longer_than_80_chars, use_raw_strings

import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('SurfaceScreenEventSchemaV1', () {
    test('matches the frozen empty and ordered canonical vectors', () {
      final empty = SurfaceScreenEventSchemaV1(events: const []);
      expect(
        SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(empty),
        '{"schemaVersion":1,"events":[]}',
      );
      expect(
        SurfaceScreenEventContractHashV1.hash(empty),
        'sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5',
      );

      final schema = SurfaceScreenEventSchemaV1(
        events: <SurfaceScreenEventV1>[
          SurfaceScreenEventV1(
            id: 'submit',
            arguments: SurfaceScreenEventObjectArgumentsV1(
              const SurfaceScreenEventMapShapeV1(
                SurfaceScreenEventScalarShapeV1(
                  SurfaceScreenEventScalarKindV1.jsonValue,
                ),
              ),
            ),
          ),
          SurfaceScreenEventV1(
            id: 'évent',
            arguments: const SurfaceScreenEventValueArgumentsV1(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKindV1.integer,
              ),
            ),
          ),
          SurfaceScreenEventV1(
            id: 'dismiss\n',
            arguments: const SurfaceScreenEventNoArgumentsV1(),
          ),
        ],
      );
      expect(
        SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(schema),
        '{"schemaVersion":1,"events":[{"id":"dismiss\\n","arguments":{"encoding":"none"}},{"id":"submit","arguments":{"encoding":"object","shape":{"kind":"map","values":{"kind":"jsonValue"}}}},{"id":"évent","arguments":{"encoding":"value","shape":{"kind":"int"}}}]}',
      );
      expect(
        SurfaceScreenEventContractHashV1.hash(schema),
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
        () => SurfaceScreenEventArgumentsV1.fromJson(
          <String, Object?>{
            'encoding': 'object',
            'shape': <String, Object?>{'kind': 'string'},
          },
          path: r'$.arguments',
        ),
        throwsFormatException,
      );

      final schema = SurfaceScreenEventSchemaV1(
        events: <SurfaceScreenEventV1>[
          SurfaceScreenEventV1(
            id: 'count',
            arguments: const SurfaceScreenEventValueArgumentsV1(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKindV1.integer,
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

  group('SurfaceScreenContractFingerprintV1', () {
    test('matches the frozen empty and Unicode canonical vectors', () {
      const zeroHash =
          'sha256:0000000000000000000000000000000000000000000000000000000000000000';
      final emptyCapabilities = CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const <LibraryRequirement>[],
      );
      expect(
        SurfaceScreenContractFingerprintV1.encodeCanonicalJson(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: emptyCapabilities,
          eventContractHash: zeroHash,
        ),
        '{"schemaVersion":1,"sourceKind":"screen","payloadKind":"blob","capabilities":{"builtInFloor":1,"requiredLibraries":[]},"eventContractHash":"$zeroHash"}',
      );
      expect(
        SurfaceScreenContractFingerprintV1.hash(
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
        SurfaceScreenContractFingerprintV1.encodeCanonicalJson(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: capabilities,
          eventContractHash: oneHash,
        ),
        '{"schemaVersion":1,"sourceKind":"screen","payloadKind":"blob","capabilities":{"builtInFloor":7,"requiredLibraries":[{"namespace":"a\\u001fedge","minVersion":1},{"namespace":"z/quote\\"slash\\\\","minVersion":2},{"namespace":"é.core","minVersion":3}]},"eventContractHash":"$oneHash"}',
      );
      expect(
        SurfaceScreenContractFingerprintV1.hash(
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
        () => SurfaceScreenContractFingerprintV1.hash(
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
        () => SurfacePublicationUploadRequestV1(
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
            artifact.role == SurfacePublicationArtifactRoleV1.screenBlob,
      );
      final sidecarArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRoleV1.capabilitySidecar,
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

      final wrongIdManifest = SurfacePublicationManifestV1(
        publications: <SurfacePublicationManifestEntryV1>[
          SurfacePublicationManifestEntryV1(
            artifacts: <SurfacePublicationArtifactV1>[
              for (final artifact in entry.artifacts)
                artifact.role == SurfacePublicationArtifactRoleV1.flowDocument
                    ? artifact
                    : SurfacePublicationArtifactV1(
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
      final wrongHashManifest = SurfacePublicationManifestV1(
        publications: <SurfacePublicationManifestEntryV1>[
          SurfacePublicationManifestEntryV1(
            artifacts: <SurfacePublicationArtifactV1>[
              for (final artifact in entry.artifacts)
                if (artifact.path == blobArtifact.path)
                  SurfacePublicationArtifactV1(
                    contentHash: CapabilitySidecar.hashBlob(changedBlob),
                    id: artifact.id,
                    path: artifact.path,
                    role: artifact.role,
                  )
                else if (artifact.path == sidecarArtifact.path)
                  SurfacePublicationArtifactV1(
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
      final underDeclaredArtifacts = <SurfacePublicationArtifactV1>[
        for (final artifact in entry.artifacts)
          artifact.role == SurfacePublicationArtifactRoleV1.capabilitySidecar
              ? SurfacePublicationArtifactV1(
                  contentHash: CapabilitySidecar.hashBlob(
                    underDeclaredSidecarBytes,
                  ),
                  id: artifact.id,
                  path: artifact.path,
                  role: artifact.role,
                )
              : artifact,
      ];
      final underDeclaredManifest = SurfacePublicationManifestV1(
        publications: <SurfacePublicationManifestEntryV1>[
          SurfacePublicationManifestEntryV1(
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
                SurfacePublicationArtifactRoleV1.capabilitySidecar,
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
                artifact.role != SurfacePublicationArtifactRoleV1.flowDocument,
          )
          .toList(growable: false);
      final sharedBlob = sharedArtifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRoleV1.screenBlob,
      );
      final sharedSidecar = sharedArtifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRoleV1.capabilitySidecar,
      );
      final capabilities = CapabilityManifest(
        builtInFloor: fixture.payload.flowDocument.minClient,
        requiredLibraries: fixture.payload.requiredLibraries,
      );
      final eventContract = SurfaceScreenEventSchemaV1(events: const []);
      final eventContractHash =
          SurfaceScreenEventContractHashV1.hash(eventContract);
      final contractFingerprint = SurfaceScreenContractFingerprintV1.hash(
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
      SurfacePublicationV1 publicationForSlug(String slug) =>
          SurfacePublicationV1(
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
      final standaloneEntry = SurfacePublicationManifestEntryV1(
        artifacts: sharedArtifacts,
        publication: standalonePublication,
      );
      final manifest = SurfacePublicationManifestV1(
        publications: <SurfacePublicationManifestEntryV1>[
          flowEntry,
          standaloneEntry,
        ],
      );

      final closures = manifest.validateArtifactClosure(fixture.files);
      expect(closures, hasLength(2));
      closures[0].validateAssembledPayload(fixture.payload.canonicalBytes);
      closures[1].validateAssembledPayload(standalonePayload.canonicalBytes);

      expect(
        () => SurfacePublicationManifestEntryV1(
          artifacts: <SurfacePublicationArtifactV1>[
            sharedBlob,
            SurfacePublicationArtifactV1(
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
        () => SurfacePublicationManifestV1(
          publications: <SurfacePublicationManifestEntryV1>[
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
        SurfacePublicationManifestEntryV1 entry,
      })>[
        (
          name: 'hash',
          entry: SurfacePublicationManifestEntryV1(
            artifacts: <SurfacePublicationArtifactV1>[
              for (final artifact in sharedArtifacts)
                artifact.role == SurfacePublicationArtifactRoleV1.screenBlob
                    ? SurfacePublicationArtifactV1(
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
          entry: SurfacePublicationManifestEntryV1(
            artifacts: <SurfacePublicationArtifactV1>[
              SurfacePublicationArtifactV1(
                contentHash: sharedBlob.contentHash,
                id: sharedBlob.id,
                path: sharedBlob.path,
                role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
              ),
              SurfacePublicationArtifactV1(
                contentHash: sharedSidecar.contentHash,
                id: sharedSidecar.id,
                path: sharedSidecar.path,
                role: SurfacePublicationArtifactRoleV1.screenBlob,
              ),
            ],
            publication: standalonePublication,
          ),
        ),
        (
          name: 'id',
          entry: SurfacePublicationManifestEntryV1(
            artifacts: <SurfacePublicationArtifactV1>[
              for (final artifact in sharedArtifacts)
                SurfacePublicationArtifactV1(
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
          () => SurfacePublicationManifestV1(
            publications: <SurfacePublicationManifestEntryV1>[
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
            artifact.role == SurfacePublicationArtifactRoleV1.flowDocument,
      );
      final blobArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRoleV1.screenBlob,
      );
      final sidecarArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRoleV1.capabilitySidecar,
      );
      final invalidClosures = <({
        String name,
        List<SurfacePublicationArtifactV1> artifacts,
      })>[
        (
          name: 'missing blob/orphaned sidecar',
          artifacts: <SurfacePublicationArtifactV1>[
            flowArtifact,
            sidecarArtifact,
          ],
        ),
        (
          name: 'missing sidecar/orphaned blob',
          artifacts: <SurfacePublicationArtifactV1>[
            flowArtifact,
            blobArtifact,
          ],
        ),
        (
          name: 'missing flow document',
          artifacts: <SurfacePublicationArtifactV1>[
            blobArtifact,
            sidecarArtifact,
          ],
        ),
        (
          name: 'duplicate flow document',
          artifacts: <SurfacePublicationArtifactV1>[
            ...entry.artifacts,
            SurfacePublicationArtifactV1(
              contentHash: flowArtifact.contentHash,
              path: 'assets/restage/generated/welcome/flow-copy.json',
              role: SurfacePublicationArtifactRoleV1.flowDocument,
            ),
          ],
        ),
        (
          name: 'duplicate blob id',
          artifacts: <SurfacePublicationArtifactV1>[
            ...entry.artifacts,
            SurfacePublicationArtifactV1(
              contentHash: blobArtifact.contentHash,
              id: blobArtifact.id,
              path: 'assets/restage/generated/welcome/start-copy.rfw',
              role: SurfacePublicationArtifactRoleV1.screenBlob,
            ),
          ],
        ),
        (
          name: 'duplicate sidecar id',
          artifacts: <SurfacePublicationArtifactV1>[
            ...entry.artifacts,
            SurfacePublicationArtifactV1(
              contentHash: sidecarArtifact.contentHash,
              id: sidecarArtifact.id,
              path:
                  'assets/restage/generated/welcome/start-copy.capability.json',
              role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
            ),
          ],
        ),
      ];

      for (final invalid in invalidClosures) {
        expect(
          () => SurfacePublicationManifestEntryV1(
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
      final paywallBlobPublication = SurfacePublicationV1(
        surface: Surface.paywall,
        slug: screenFixture.publication.slug,
        sourceKind: SurfaceSourceKind.paywall,
        payloadKind: SurfacePayloadKind.blob,
        payloadContentHash: screenFixture.payload.contentHash,
      );
      final paywallBlobManifest = SurfacePublicationManifestV1(
        publications: <SurfacePublicationManifestEntryV1>[
          SurfacePublicationManifestEntryV1(
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
      final paywallFlowPublication = SurfacePublicationV1(
        surface: Surface.paywall,
        slug: flowFixture.payload.flowDocument.flow,
        sourceKind: SurfaceSourceKind.paywall,
        payloadKind: SurfacePayloadKind.flow,
        payloadContentHash: flowFixture.payload.contentHash,
        deliveryMode: flowFixture.payload.flowDocument.deliveryMode,
      );
      final paywallFlowManifest = SurfacePublicationManifestV1(
        publications: <SurfacePublicationManifestEntryV1>[
          SurfacePublicationManifestEntryV1(
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
          () => SurfacePublicationV1.fromJson(
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
        () => SurfacePublicationArtifactV1.fromJson(
          artifactJson,
          path: r'$.artifact',
        ),
        throwsFormatException,
      );

      const contentHash =
          'sha256:0000000000000000000000000000000000000000000000000000000000000000';
      expect(
        SurfacePublicationArtifactV1(
          contentHash: contentHash,
          id: 'screen',
          path: 'assets/restage/generated/welcome/start.rfw',
          role: SurfacePublicationArtifactRoleV1.screenBlob,
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
          () => SurfacePublicationArtifactV1(
            contentHash: contentHash,
            id: 'screen',
            path: path,
            role: SurfacePublicationArtifactRoleV1.screenBlob,
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
        () =>
            SurfacePublicationV1.fromJson(publication, path: r'$.publication'),
        throwsFormatException,
      );
      expect(
        () => SurfacePublicationArtifactV1(
          contentHash:
              'sha256:0000000000000000000000000000000000000000000000000000000000000000',
          id: 'screen',
          path: '../outside.rfw',
          role: SurfacePublicationArtifactRoleV1.screenBlob,
        ),
        throwsFormatException,
      );
      publication
        ..remove('unknown')
        ..['contractFingerprint'] = null;
      expect(
        () =>
            SurfacePublicationV1.fromJson(publication, path: r'$.publication'),
        throwsFormatException,
      );
      publication
        ..remove('contractFingerprint')
        ..remove('eventContractHash');
      expect(
        () =>
            SurfacePublicationV1.fromJson(publication, path: r'$.publication'),
        throwsFormatException,
      );
    });
  });

  group('Surface screen delivery contracts', () {
    test('normalizes only advisory request keys and freezes the request vector',
        () {
      final normalized = SurfaceScreenDeliveryRequestV1.fromJson(
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

      final request = SurfaceScreenDeliveryRequestV1(
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
      SurfaceScreenDeliveryResponseV1 responseForDocument(
        SurfaceDocument document,
      ) =>
          SurfaceScreenDeliveryResponseV1(
            document: document,
            sourceKind: SurfaceSourceKind.screen,
            payloadKind: SurfacePayloadKind.blob,
            contractVersion: 7,
            publishedRevision: document.version,
            contractFingerprint: fixture.contractFingerprint,
            eventContractHash: fixture.eventContractHash,
          );
      final response = SurfaceScreenDeliveryResponseV1(
        document: fixture.document,
        sourceKind: SurfaceSourceKind.screen,
        payloadKind: SurfacePayloadKind.blob,
        contractVersion: 7,
        publishedRevision: 12,
        contractFingerprint: fixture.contractFingerprint,
        eventContractHash: fixture.eventContractHash,
        assignment: SurfaceExperimentAssignmentV1(
          experimentId: 'exp_1',
          variantId: 'treatment',
          experimentEpoch: 3,
        ),
      );
      final responseJson =
          SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(
        response,
      );
      expect(responseJson, _screenResponseGolden);
      expect(
        SurfaceScreenDeliveryResponseV1Codec.decodeJson(responseJson)
            .assignment!
            .variantId,
        'treatment',
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
        () => SurfaceScreenDeliveryResponseV1(
          document: fixture.document,
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          contractVersion: 7,
          publishedRevision: 11,
          contractFingerprint: fixture.contractFingerprint,
          eventContractHash: fixture.eventContractHash,
        ),
        throwsFormatException,
      );
      final responseMap = response.toJson();
      for (final field in const <String>[
        'schemaVersion',
        'document',
        'sourceKind',
        'payloadKind',
        'contractVersion',
        'publishedRevision',
        'contractFingerprint',
        'eventContractHash',
      ]) {
        final missing = Map<String, Object?>.from(responseMap)..remove(field);
        final nulled = Map<String, Object?>.from(responseMap)..[field] = null;
        expect(
          () => SurfaceScreenDeliveryResponseV1Codec.decode(missing),
          throwsFormatException,
          reason: 'missing response $field',
        );
        expect(
          () => SurfaceScreenDeliveryResponseV1Codec.decode(nulled),
          throwsFormatException,
          reason: 'null response $field',
        );
      }
      for (final field in const <String>[
        'contractFingerprint',
        'eventContractHash',
      ]) {
        final malformed = Map<String, Object?>.from(responseMap)
          ..[field] = 'sha256:0';
        expect(
          () => SurfaceScreenDeliveryResponseV1Codec.decode(malformed),
          throwsFormatException,
          reason: 'malformed response $field',
        );
      }
      expect(
        () => SurfaceScreenDeliveryResponseV1Codec.decode(<String, Object?>{
          ...responseMap,
          'unknown': true,
        }),
        throwsFormatException,
      );

      final partialAssignment = Map<String, Object?>.from(responseMap)
        ..['assignment'] = <String, Object?>{
          'experimentId': 'exp_1',
        };
      expect(
        () => SurfaceScreenDeliveryResponseV1Codec.decode(partialAssignment),
        throwsFormatException,
      );
      expect(
        () => SurfaceScreenDeliveryResponseV1Codec.decode(null),
        throwsFormatException,
      );
      expect(
        () => SurfaceScreenDeliveryResponseV1Codec.decode(<String, Object?>{
          ...responseMap,
          'assignment': null,
        }),
        throwsFormatException,
      );
      final withoutAssignment = Map<String, Object?>.from(responseMap)
        ..remove('assignment');
      expect(
        SurfaceScreenDeliveryResponseV1Codec.decode(withoutAssignment)
            .assignment,
        isNull,
      );
    });
  });
}

({
  SurfacePublicationManifestV1 manifest,
  SurfacePublicationUploadRequestV1 upload,
  SurfacePublicationV1 publication,
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
  final eventContract = SurfaceScreenEventSchemaV1(events: const []);
  final eventContractHash =
      SurfaceScreenEventContractHashV1.hash(eventContract);
  final contractFingerprint = SurfaceScreenContractFingerprintV1.hash(
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    capabilities: capabilities,
    eventContractHash: eventContractHash,
  );
  final payload = BlobSurfacePayload(
    minClient: 1,
    blob: Uint8List.fromList(const <int>[1, 2, 3]),
  );
  final publication = SurfacePublicationV1(
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
  final manifest = SurfacePublicationManifestV1(
    publications: <SurfacePublicationManifestEntryV1>[
      SurfacePublicationManifestEntryV1(
        artifacts: <SurfacePublicationArtifactV1>[
          SurfacePublicationArtifactV1(
            contentHash: CapabilitySidecar.hashBlob(payload.blob),
            id: publication.slug,
            path: blobPath,
            role: SurfacePublicationArtifactRoleV1.screenBlob,
          ),
          SurfacePublicationArtifactV1(
            contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
            id: publication.slug,
            path: sidecarPath,
            role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
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
    upload: SurfacePublicationUploadRequestV1(
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
  SurfacePublicationManifestV1 manifest,
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
  final publication = SurfacePublicationV1(
    surface: Surface.general,
    slug: 'welcome',
    sourceKind: SurfaceSourceKind.flowGraph,
    payloadKind: SurfacePayloadKind.flow,
    payloadContentHash: payload.contentHash,
    deliveryMode: FlowDeliveryMode.general,
  );
  return (
    manifest: SurfacePublicationManifestV1(
      publications: <SurfacePublicationManifestEntryV1>[
        SurfacePublicationManifestEntryV1(
          artifacts: <SurfacePublicationArtifactV1>[
            SurfacePublicationArtifactV1(
              contentHash: CapabilitySidecar.hashBlob(flowBytes),
              path: flowPath,
              role: SurfacePublicationArtifactRoleV1.flowDocument,
            ),
            SurfacePublicationArtifactV1(
              contentHash: CapabilitySidecar.hashBlob(blob),
              id: 'start',
              path: blobPath,
              role: SurfacePublicationArtifactRoleV1.screenBlob,
            ),
            SurfacePublicationArtifactV1(
              contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
              id: 'start',
              path: sidecarPath,
              role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
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
const String _screenResponseGolden =
    '{"schemaVersion":1,"document":"AAAA_3siY29udGVudEhhc2giOiJzaGEyNTY6N2NhYTYxNGViY2MxODAwZmIwZTJhZWY3ZjQwNjZjMzJmNjU4OWY2YjYyZDM3MzI5MDFlYjFkN2Q2MTdmOTIzZCIsImZvcm1hdFZlcnNpb24iOjIsIm1pbkNsaWVudCI6MSwicHVibGlzaGVkQXRNaWNyb3MiOjE3ODY0MDY0MDAwMDAwMDAsInJlcXVpcmVkTGlicmFyaWVzIjpbXSwic3VyZmFjZVNsdWciOiJmZWF0dXJlX2Fubm91bmNlbWVudCIsInN1cmZhY2VUeXBlIjoiZ2VuZXJhbCIsInZlcnNpb24iOjEyfQAAAARibG9iAAAAAQAAAAMBAgMAAAAA","sourceKind":"screen","payloadKind":"blob","contractVersion":7,"publishedRevision":12,"contractFingerprint":"sha256:5876ace20d49d4af1c24e69867f9de9380688586256e67130f83bf99d0e96a9f","eventContractHash":"sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5","assignment":{"experimentId":"exp_1","variantId":"treatment","experimentEpoch":3}}';
