import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart'
    show AssetBundle, ByteData, CachingAssetBundle;
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

import '../support/hosted_artifact_delivery.dart';

/// The package and library a fixture bundle claims to have been built from.
const String kFixturePackageName = 'example_app';
const String kFixtureAuthoredLibrary = 'lib/screens.dart';

final class ScreenFixture<E> {
  ScreenFixture._({
    required this.ref,
    required this.schema,
    required this.capabilities,
    required this.blob,
    required this.contentHash,
    required this.locator,
    required this.sidecarBytes,
  });

  final SurfaceScreenRef<E> ref;
  final SurfaceScreenEventSchema schema;
  final CapabilityManifest capabilities;
  final Uint8List blob;
  final String contentHash;

  /// The locator naming this fixture's screen closure inside [bundleBytes].
  final SurfaceScreenBundleLocator locator;
  final Uint8List sidecarBytes;

  String get blobSha256 => CapabilitySidecar.hashBlob(blob);

  SurfaceScreenRuntimeProvenance get provenance => ref.provenance;

  /// The exact `.rsbundle` bytes [locator] addresses.
  ///
  /// The bundle also carries the screen's inspection text, which no locator
  /// entry names — a real bundle carries more than one screen's closure.
  Uint8List bundleBytes({Uint8List? blobOverride}) => RestageBundleCodec.encode(
        RestageBundle(
          packageName: kFixturePackageName,
          authoredLibraryPath: kFixtureAuthoredLibrary,
          entries: <RestageBundleEntry>[
            RestageBundleEntry(
              logicalPath: locator.screenBlob.logicalPath,
              role: RestageBundleEntryRole.screenBlob,
              bytes: blobOverride ?? blob,
            ),
            RestageBundleEntry(
              logicalPath: locator.capabilitySidecar.logicalPath,
              role: RestageBundleEntryRole.capabilitySidecar,
              bytes: sidecarBytes,
            ),
            RestageBundleEntry(
              logicalPath: 'assets/restage/surface_screens/${ref.slug}.rfwtxt',
              role: RestageBundleEntryRole.rfwText,
              bytes: Uint8List.fromList(utf8.encode('widget Inspection = ();')),
            ),
          ],
        ),
      );

  /// An asset bundle serving [bundleBytes] at the locator's asset key.
  AssetBundle assetBundle({Uint8List? bytes}) => TestAssetBundle(
        <String, Uint8List>{locator.assetKey: bytes ?? bundleBytes()},
      );

  ResolvedSurfaceScreen bundled({Uint8List? blobOverride}) {
    final bytes = blobOverride ?? blob;
    return ResolvedSurfaceScreen.bundled(
      surface: ref.surface,
      slug: ref.slug,
      contractVersion: ref.contractVersion,
      sourceKind: ref.sourceKind,
      payloadKind: ref.payloadKind,
      capabilities: capabilities,
      contractFingerprint: ref.contractFingerprint,
      eventContractHash: ref.eventContract.hash,
      blob: bytes,
      contentHash: _payloadHash(bytes, capabilities),
      bundledEntryHash: CapabilitySidecar.hashBlob(bytes),
    );
  }

  ResolvedSurfaceScreen hosted({
    Uint8List? hostedBlob,
    int publishedRevision = 7,
    SurfaceExperimentAssignment? assignment,
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

  /// The stub delivery this fixture describes surfaces through — and, just as
  /// importantly, serves their content from. A screen delivery is two exchanges
  /// now, and a fixture that only owned the first would let a test pass while
  /// the half of the wire that carries the pixels was never exercised.
  final HostedArtifactFixture hostedDelivery = HostedArtifactFixture();

  SurfaceScreenDeliveryDescriptor delivery({
    Uint8List? hostedBlob,
    int publishedRevision = 7,
    int? contractVersion,
    SurfaceExperimentAssignment? assignment,
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
    return hostedDelivery.describeScreen(
      document: document,
      contractVersion: contractVersion ?? ref.contractVersion,
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
  SurfaceScreenEventSchema? schema,
  GeneratedSurfaceScreenEventDecoder<String>? decoder,
  CapabilityManifest? capabilities,
  Uint8List? blob,
  bool packagesBundle = true,
}) {
  final effectiveCapabilities = capabilities ??
      CapabilityManifest(builtInFloor: 1, requiredLibraries: const []);
  final effectiveSchema = schema ??
      SurfaceScreenEventSchema(events: <SurfaceScreenEvent>[
        SurfaceScreenEvent(
          id: emittedEvent,
          arguments: const SurfaceScreenEventNoArguments(),
        ),
      ]);
  return _fixtureFor(
    surface: surface,
    slug: slug,
    contractVersion: contractVersion,
    schema: effectiveSchema,
    capabilities: effectiveCapabilities,
    blob: blob ?? rfwScreenBlob(text: text, event: emittedEvent),
    packagesBundle: packagesBundle,
    eventContract: (hash) => SurfaceScreenEventContract<String>.generated(
      hash: hash,
      decodeValidated: decoder ?? (name, _) => name,
    ),
  );
}

ScreenFixture<Never> neverScreenFixture({
  Surface surface = Surface.general,
  String slug = 'event_free',
  int contractVersion = 1,
  String text = 'Event-free screen',
  String emittedEvent = 'unexpected',
}) =>
    _fixtureFor(
      surface: surface,
      slug: slug,
      contractVersion: contractVersion,
      schema: SurfaceScreenEventSchema(events: const <SurfaceScreenEvent>[]),
      capabilities:
          CapabilityManifest(builtInFloor: 1, requiredLibraries: const []),
      blob: rfwScreenBlob(text: text, event: emittedEvent),
      packagesBundle: true,
      eventContract: (hash) =>
          SurfaceScreenEventContract<Never>.none(hash: hash),
    );

/// Builds the generated shape end to end: bundle closure, then provenance
/// describing it, then the reference carrying that provenance.
ScreenFixture<E> _fixtureFor<E>({
  required Surface surface,
  required String slug,
  required int contractVersion,
  required SurfaceScreenEventSchema schema,
  required CapabilityManifest capabilities,
  required Uint8List blob,
  required bool packagesBundle,
  required SurfaceScreenEventContract<E> Function(String hash) eventContract,
}) {
  final sidecarBytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: capabilities,
        ).toJson(),
      ),
    ),
  );
  final locator = SurfaceScreenBundleLocator(
    assetKey: 'assets/restage/bundles/screens.rsbundle',
    packageName: kFixturePackageName,
    authoredLibraryPath: kFixtureAuthoredLibrary,
    entries: <SurfaceScreenBundleEntryReference>[
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/restage/surface_screens/$slug.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: blob.length,
        sha256: CapabilitySidecar.hashBlob(blob),
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/restage/surface_screens/$slug.capabilities.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: sidecarBytes.length,
        sha256: CapabilitySidecar.hashBlob(sidecarBytes),
      ),
    ],
  );
  final provenance = SurfaceScreenRuntimeProvenance(
    surface: surface,
    slug: slug,
    contractVersion: contractVersion,
    capabilities: capabilities,
    eventSchema: schema,
    bundle: packagesBundle ? locator : null,
  );
  return ScreenFixture<E>._(
    ref: SurfaceScreenRef<E>.generated(
      provenance: provenance,
      eventContract: eventContract(provenance.eventContractHash),
    ),
    schema: schema,
    capabilities: capabilities,
    blob: blob,
    contentHash: _payloadHash(blob, capabilities),
    sidecarBytes: sidecarBytes,
    locator: locator,
  );
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

void resetSurfaceScreenTestState() {
  Restage.debugReset();
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

/// A bundled resolver that always refuses, as an application packaging no
/// bundles does.
final class AbsentBundledScreenResolver
    implements BundledSurfaceScreenResolver {
  var calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    calls += 1;
    throw const SurfaceScreenUnavailableError(
      reason: SurfaceScreenUnavailableReason.missing,
      message: 'No packaged bundle is available for this screen.',
    );
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
