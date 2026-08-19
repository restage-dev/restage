import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart'
    show AssetBundle, ByteData, CachingAssetBundle;
import 'package:restage/restage.dart';
import 'package:restage/src/surface_screen/surface_screen_manifest.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

final class ScreenFixture<E> {
  ScreenFixture._({
    required this.ref,
    required this.schema,
    required this.capabilities,
    required this.blob,
    required this.contentHash,
    required this.bundle,
  });

  final SurfaceScreenRef<E> ref;
  final SurfaceScreenEventSchemaV1 schema;
  final CapabilityManifest capabilities;
  final Uint8List blob;
  final String contentHash;
  final AssetBundle bundle;

  ResolvedSurfaceScreen bundled() => ResolvedSurfaceScreen.bundled(
        surface: ref.surface,
        slug: ref.slug,
        contractVersion: ref.contractVersion,
        sourceKind: ref.sourceKind,
        payloadKind: ref.payloadKind,
        capabilities: capabilities,
        contractFingerprint: ref.contractFingerprint,
        eventContractHash: ref.eventContract.hash,
        blob: blob,
        contentHash: contentHash,
      );

  ResolvedSurfaceScreen hosted({
    Uint8List? hostedBlob,
    int publishedRevision = 7,
    SurfaceExperimentAssignmentV1? assignment,
  }) {
    final blob = hostedBlob ?? this.blob;
    return ResolvedSurfaceScreen.hosted(
      surface: ref.surface,
      slug: ref.slug,
      contractVersion: ref.contractVersion,
      publishedRevision: publishedRevision,
      sourceKind: ref.sourceKind,
      payloadKind: ref.payloadKind,
      capabilities: capabilities,
      contractFingerprint: ref.contractFingerprint,
      eventContractHash: ref.eventContract.hash,
      blob: blob,
      contentHash: _payloadHash(blob, capabilities),
      assignment: assignment,
      cacheHit: false,
    );
  }

  SurfaceScreenDeliveryResponseV1 delivery({
    Uint8List? hostedBlob,
    int publishedRevision = 7,
    int? contractVersion,
    SurfaceExperimentAssignmentV1? assignment,
  }) {
    final blob = hostedBlob ?? this.blob;
    final payload = BlobSurfacePayload(
      minClient: capabilities.builtInFloor,
      blob: blob,
      requiredLibraries: capabilities.requiredLibraries,
    );
    final document = SurfaceDocument(
      surfaceType: ref.surface,
      surfaceSlug: ref.slug,
      version: publishedRevision,
      minClient: capabilities.builtInFloor,
      requiredLibraries: capabilities.requiredLibraries,
      payload: payload,
      publishedAt: DateTime.utc(2026, 8, 11),
    );
    return SurfaceScreenDeliveryResponseV1(
      document: document,
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      contractVersion: contractVersion ?? ref.contractVersion,
      publishedRevision: publishedRevision,
      contractFingerprint: ref.contractFingerprint,
      eventContractHash: ref.eventContract.hash,
      assignment: assignment,
    );
  }
}

ScreenFixture<String> stringScreenFixture({
  Surface surface = Surface.general,
  String slug = 'notice',
  int contractVersion = 1,
  String text = 'Bundled screen',
  String emittedEvent = 'tap',
  SurfaceScreenEventSchemaV1? schema,
  GeneratedSurfaceScreenEventDecoder<String>? decoder,
  CapabilityManifest? capabilities,
  Uint8List? blob,
}) {
  final effectiveCapabilities = capabilities ??
      CapabilityManifest(builtInFloor: 1, requiredLibraries: const []);
  final effectiveSchema = schema ??
      SurfaceScreenEventSchemaV1(events: <SurfaceScreenEventV1>[
        SurfaceScreenEventV1(
          id: emittedEvent,
          arguments: const SurfaceScreenEventNoArgumentsV1(),
        ),
      ]);
  final eventHash = SurfaceScreenEventContractHashV1.hash(effectiveSchema);
  final fingerprint = SurfaceScreenContractFingerprintV1.hash(
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    capabilities: effectiveCapabilities,
    eventContractHash: eventHash,
  );
  final ref = SurfaceScreenRef<String>.generated(
    slug: slug,
    contractVersion: contractVersion,
    capabilities: effectiveCapabilities,
    surface: surface,
    contractFingerprint: fingerprint,
    eventContract: SurfaceScreenEventContract<String>.generated(
      hash: eventHash,
      decodeValidated: decoder ?? (name, _) => name,
    ),
  );
  final screenBlob = blob ?? rfwScreenBlob(text: text, event: emittedEvent);
  final contentHash = _payloadHash(screenBlob, effectiveCapabilities);
  return ScreenFixture<String>._(
    ref: ref,
    schema: effectiveSchema,
    capabilities: effectiveCapabilities,
    blob: screenBlob,
    contentHash: contentHash,
    bundle: manifestBundleFor(
      ref: ref,
      schema: effectiveSchema,
      blob: screenBlob,
    ),
  );
}

ScreenFixture<Never> neverScreenFixture({
  Surface surface = Surface.general,
  String slug = 'event_free',
  int contractVersion = 1,
  String text = 'Event-free screen',
  String emittedEvent = 'unexpected',
}) {
  final capabilities =
      CapabilityManifest(builtInFloor: 1, requiredLibraries: const []);
  final schema =
      SurfaceScreenEventSchemaV1(events: const <SurfaceScreenEventV1>[]);
  final eventHash = SurfaceScreenEventContractHashV1.hash(schema);
  final fingerprint = SurfaceScreenContractFingerprintV1.hash(
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    capabilities: capabilities,
    eventContractHash: eventHash,
  );
  final ref = SurfaceScreenRef<Never>.generated(
    slug: slug,
    contractVersion: contractVersion,
    capabilities: capabilities,
    surface: surface,
    contractFingerprint: fingerprint,
    eventContract: SurfaceScreenEventContract<Never>.none(hash: eventHash),
  );
  final blob = rfwScreenBlob(text: text, event: emittedEvent);
  return ScreenFixture<Never>._(
    ref: ref,
    schema: schema,
    capabilities: capabilities,
    blob: blob,
    contentHash: _payloadHash(blob, capabilities),
    bundle: manifestBundleFor(ref: ref, schema: schema, blob: blob),
  );
}

AssetBundle manifestBundleFor<E>({
  required SurfaceScreenRef<E> ref,
  required SurfaceScreenEventSchemaV1 schema,
  required Uint8List blob,
}) {
  final payload = BlobSurfacePayload(
    minClient: ref.capabilities.builtInFloor,
    blob: blob,
    requiredLibraries: ref.capabilities.requiredLibraries,
  );
  final blobPath = 'assets/restage/surface_screens/${ref.slug}.rfw';
  final sidecarPath =
      'assets/restage/surface_screens/${ref.slug}.capabilities.json';
  final sidecarBytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: ref.capabilities,
        ).toJson(),
      ),
    ),
  );
  final publication = SurfacePublicationV1(
    surface: ref.surface,
    slug: ref.slug,
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    payloadContentHash: payload.contentHash,
    contractVersion: ref.contractVersion,
    capabilities: ref.capabilities,
    eventContract: schema,
    eventContractHash: ref.eventContract.hash,
    contractFingerprint: ref.contractFingerprint,
  );
  final entry = SurfacePublicationManifestEntryV1(
    publication: publication,
    artifacts: <SurfacePublicationArtifactV1>[
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(blob),
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: ref.slug,
      ),
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: ref.slug,
      ),
    ],
  );
  final manifest = SurfacePublicationManifestV1(
    publications: <SurfacePublicationManifestEntryV1>[entry],
  );
  return TestAssetBundle(<String, Uint8List>{
    kSurfaceScreenPublicationManifestAsset: Uint8List.fromList(
      utf8.encode(
          SurfacePublicationManifestV1Codec.encodeCanonicalJson(manifest)),
    ),
    blobPath: blob,
    sidecarPath: sidecarBytes,
  });
}

AssetBundle paywallSourceManifestBundle<E>({
  required SurfaceScreenRef<E> reference,
  required Uint8List blob,
}) {
  final payload = BlobSurfacePayload(
    minClient: reference.capabilities.builtInFloor,
    blob: blob,
    requiredLibraries: reference.capabilities.requiredLibraries,
  );
  final blobPath = 'assets/restage/surface_screens/${reference.slug}.rfw';
  final sidecarPath =
      'assets/restage/surface_screens/${reference.slug}.capabilities.json';
  final sidecarBytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: reference.capabilities,
        ).toJson(),
      ),
    ),
  );
  final entry = SurfacePublicationManifestEntryV1(
    publication: SurfacePublicationV1(
      surface: Surface.paywall,
      slug: reference.slug,
      sourceKind: SurfaceSourceKind.paywall,
      payloadKind: SurfacePayloadKind.blob,
      payloadContentHash: payload.contentHash,
    ),
    artifacts: <SurfacePublicationArtifactV1>[
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(blob),
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: reference.slug,
      ),
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: reference.slug,
      ),
    ],
  );
  return TestAssetBundle(<String, Uint8List>{
    kSurfaceScreenPublicationManifestAsset: Uint8List.fromList(
      utf8.encode(
        SurfacePublicationManifestV1Codec.encodeCanonicalJson(
          SurfacePublicationManifestV1(
            publications: <SurfacePublicationManifestEntryV1>[entry],
          ),
        ),
      ),
    ),
    blobPath: blob,
    sidecarPath: sidecarBytes,
  });
}

Uint8List rfwScreenBlob({required String text, required String event}) {
  final source = '''
import restage.core;

widget OnboardingScreen = GestureDetector(
  onTap: event "$event" { },
  child: Text(text: "$text")
);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List rfwSourceBlob(String source) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

void installManifestBundle(AssetBundle bundle) {
  SurfaceScreenManifestRegistry.debugAssetBundle = bundle;
}

void resetSurfaceScreenTestState() {
  Restage.debugReset();
  SurfaceScreenManifestRegistry.debugReset();
}

final class FixedScreenResolver implements SurfaceScreenResolver {
  FixedScreenResolver(this._result);

  final ResolvedSurfaceScreen _result;
  var calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    calls += 1;
    return _result;
  }
}

final class FailingScreenResolver implements SurfaceScreenResolver {
  FailingScreenResolver(this.error);

  final Object error;
  var calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) {
    calls += 1;
    return Future<ResolvedSurfaceScreen>.error(error);
  }
}

final class FixedBundledScreenResolver implements BundledSurfaceScreenResolver {
  FixedBundledScreenResolver(this._result);

  final ResolvedSurfaceScreen _result;
  var calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    calls += 1;
    return _result;
  }
}

final class TestAssetBundle extends CachingAssetBundle {
  TestAssetBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

String _payloadHash(Uint8List blob, CapabilityManifest capabilities) =>
    BlobSurfacePayload(
      minClient: capabilities.builtInFloor,
      blob: blob,
      requiredLibraries: capabilities.requiredLibraries,
    ).contentHash;
