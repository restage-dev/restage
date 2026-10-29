import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/placement_mount_resolver.dart'
    show placementDeferredFacts;
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    root = await Directory.systemTemp.createTemp('contract_read_ahead');
    sharedSurfaceArtifactStore = createSurfaceArtifactStore(
        directory: () async => root.path, readsOffIsolate: true);
  });
  tearDown(() async {
    Restage.debugReset();
    sharedSurfaceArtifactStore = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a declared host contract is decoded by the read ahead, not configure',
      () async {
    final definition = RestagePaywall.generatedPlacementDefinition(
      id: 'shared',
      defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('paywall'),
        slug: 'shared',
        family: const DeliveryFamilySelectorV1.general(),
      ).toJson(),
      hostContractJson: SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
          contentKind: SurfaceContentKindV1.single,
          presentation: SurfacePresentationV1.inline,
        ),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []),
      ).toJson(),
      vocabulary: SurfaceVocabulary.none,
    );
    Restage.declareSurfaces([definition]);
    Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
        analyticsEnabled: false,
        measurementEnabled: false,
        deliveryReceiptsEnabled: false);
    expect(definition.undecodedHostContract, isNotNull);
    final ahead = await Restage.placementRegistry!.readAhead();
    expect(definition.undecodedHostContract, isNull);
    expect(definition.hostContract, same(ahead.contracts.single));
    expect(Restage.placementDiscovery!.buildContract.contractsByHash,
        contains(definition.hostContract.contentHash));
  });

  test('the first capture reuses the build contract the read ahead built',
      () async {
    // Its widgets are installed before the read ahead judges the build.
    final definition = _paywall(
        vocabulary: SurfaceVocabulary(
            widgets: RestageWidgetLibraries.fromVocabulary(
                core: {'SeedProbe': (_, __) => const SizedBox()})));
    Restage.declareSurfaces([definition]);
    _configure();
    final ahead = await Restage.placementRegistry!.readAhead();
    final seed = ahead.build!;
    expect(currentInstalledCapability(), same(seed.installed));
    // The startup path configures the declared mounts once read ahead.
    await pumpEventQueue();
    final mount = PlacementMountBinding(definition: () => definition).capture();
    final context = await withSurfaceDeliveryObservations(
        cell: SurfaceDeliveryObservationCell(
            readKnownSurfaceDeliveryObservations),
        resolve: () => Restage.placementRegistry!.capture(
            mounts: [mount.mount],
            sendAssignmentKey: false,
            deferFacts: placementDeferredFacts));
    expect(context!.request.buildContract, same(seed.contract));
  });

  test('a relaunch warms up with the build contract the read ahead built',
      () async {
    final first = _paywall();
    Restage.declareSurfaces([first]);
    _configure();
    await Restage.placementRegistry!.readAhead();
    final declared = PlacementMountBinding(definition: () => first).capture();
    await Restage.placementRegistry!.decisions
        .remember(declared.mount, declared.host, () => true);
    // A new process over the same storage remembers the mount.
    Restage.debugReset();
    final definition = _paywall();
    Restage.declareSurfaces([definition]);
    _configure();
    final seed = (await Restage.placementRegistry!.readAhead()).build!;
    expect(seed.mounts, hasLength(1));
    await pumpEventQueue();
    final context = await withSurfaceDeliveryObservations(
        cell: SurfaceDeliveryObservationCell(
            readKnownSurfaceDeliveryObservations),
        resolve: () => Restage.placementRegistry!.capture(
            mounts: [seed.mounts.keys.single],
            sendAssignmentKey: false,
            deferFacts: placementDeferredFacts));
    expect(context!.request.buildContract, same(seed.contract));
  });

  test('a declared screen schema is decoded by the read ahead, not configure',
      () async {
    final (definition, provenance) = _screen();
    Restage.declareSurfaces([definition]);
    _configure();
    expect(provenance.undecodedContract, isNotNull);
    final ahead = await Restage.placementRegistry!.readAhead();
    expect(provenance.undecodedContract, isNull);
    expect(provenance.eventSchema,
        same(ahead.screenContracts.single!.eventSchema));
    expect(provenance.eventContractHash,
        SurfaceScreenEventContractHash.hash(_events));
  });

  test('a generated reference whose event hash disagrees fails on first use',
      () async {
    final (definition, provenance) = _screen(eventHash: 'sha256:${'0' * 64}');
    expect(provenance.undecodedContract, isNotNull);
    Restage.declareSurfaces([definition]);
    _configure();
    await Restage.placementRegistry!.readAhead();
    expect(provenance.undecodedContract, isNull);
    expect(() => provenance.eventSchema, throwsArgumentError);
    expect(
        () =>
            (definition.defaultSurface as SurfaceScreenRef).contractFingerprint,
        throwsArgumentError);
  });

  test('a screen schema the read ahead cannot decode fails on first use',
      () async {
    final (definition, provenance) =
        _screen(eventSchemaJson: '{"schemaVersion":1}');
    Restage.declareSurfaces([definition]);
    _configure();
    final ahead = await Restage.placementRegistry!.readAhead();
    expect(ahead.screenContracts.single, isNull);
    expect(provenance.undecodedContract, isNotNull);
    expect(() => provenance.eventContractHash, throwsA(anything));
  });
}

void _configure() => Restage.configure(
    apiKey: 'rs_pk_test',
    baseUrl: 'https://example.com',
    analyticsEnabled: false,
    measurementEnabled: false,
    deliveryReceiptsEnabled: false);

final _events = SurfaceScreenEventSchema(events: [
  SurfaceScreenEvent(
      id: 'next', arguments: const SurfaceScreenEventNoArguments()),
]);

(GeneratedPlacementDefinition, SurfaceScreenRuntimeProvenance) _screen(
    {String? eventHash, String? eventSchemaJson}) {
  final host = SurfaceHostContractV1(
    hosting: const SurfaceHostingV1(
      contentKind: SurfaceContentKindV1.single,
      presentation: SurfacePresentationV1.inline,
    ),
    providedContext: const SurfaceScreenHostDataSchema.empty(),
    handledEvents: SurfaceScreenEventSchema(events: const []),
  );
  final provenance = SurfaceScreenRuntimeProvenance.generated(
    surface: Surface.general,
    slug: 'shared',
    contractVersion: 3,
    capabilities:
        CapabilityManifest(builtInFloor: 1, requiredLibraries: const []),
    eventSchemaJson: eventSchemaJson ??
        SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(_events),
  );
  final definition = RestageScreen.generatedPlacementDefinition(
    defaultSurface: SurfaceScreenRef<Never>.generated(
      provenance: provenance,
      eventContract: SurfaceScreenEventContract<Never>.none(
        hash: eventHash ?? SurfaceScreenEventContractHash.hash(_events),
      ),
    ),
    defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
      surfaceType: DeliverySurfaceTypeId('general'),
      slug: 'shared',
      family: DeliveryFamilySelectorV1.screenContract(contractVersion: 3),
    ).toJson(),
    hostContractJson: host.toJson(),
    vocabulary: SurfaceVocabulary.none,
  );
  return (definition, provenance);
}

GeneratedPlacementDefinition _paywall(
        {SurfaceVocabulary vocabulary = SurfaceVocabulary.none}) =>
    RestagePaywall.generatedPlacementDefinition(
      id: 'shared',
      defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('paywall'),
        slug: 'shared',
        family: const DeliveryFamilySelectorV1.general(),
      ).toJson(),
      hostContractJson: SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
          contentKind: SurfaceContentKindV1.single,
          presentation: SurfacePresentationV1.inline,
        ),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []),
      ).toJson(),
      vocabulary: vocabulary,
    );
