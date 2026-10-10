import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });
  tearDown(Restage.debugReset);

  test('const binding retains the definition tear-off and explicit name', () {
    const binding = PlacementMountBinding(
      definition: _paywallDefinition,
      name: 'home_card',
    );
    expect(binding.definition, same(_paywallDefinition));
    expect(binding.name, 'home_card');
    expect(
        binding.definition().key,
        PlacementKeyV1.generatedDefault(
          surfaceType: DeliverySurfaceTypeId('paywall'),
          slug: 'shared',
        ));
    expect(const PlacementMountBinding(definition: _paywallDefinition).name,
        isNull);
    expect(
        (const RestagePaywall(id: 'shared') as RestagePlacementMount)
            .placementBinding,
        isNull);
  });

  test('binding declarations compare providers and names without evaluating',
      () {
    GeneratedPlacementDefinition unread() =>
        throw StateError('Comparing bindings must not read the provider.');
    GeneratedPlacementDefinition otherUnread() =>
        throw StateError('Comparing bindings must not read the provider.');
    final first = RestageFlowGraph.generatedPlacementBinding(
        definition: unread, name: 'home_card');
    final equivalent = RestageFlowGraph.generatedPlacementBinding(
        definition: unread, name: 'home_card');
    expect(first, isNot(same(equivalent)));
    expect(first.sameDeclarationAs(equivalent), isTrue);
    expect(
        first.sameDeclarationAs(RestageFlowGraph.generatedPlacementBinding(
            definition: unread, name: 'other_card')),
        isFalse);
    expect(
        first.sameDeclarationAs(RestageFlowGraph.generatedPlacementBinding(
            definition: otherUnread, name: 'home_card')),
        isFalse);
    expect(first.sameDeclarationAs(null), isFalse);
  });

  test('explicit binding equality retains exact mount and host authority', () {
    final host = _singleHost();
    final mount = PlacementMountRequestV1(
        key: PlacementKeyV1.named(slug: 'home_card'),
        hostContractHash: host.contentHash);
    final first =
        PlacementMountBinding.request(mount: mount, hostContract: host);
    expect(
        first.sameDeclarationAs(
            PlacementMountBinding.request(mount: mount, hostContract: host)),
        isTrue);
    expect(
        first.sameDeclarationAs(PlacementMountBinding.request(
            mount: PlacementMountRequestV1(
                key: PlacementKeyV1.named(slug: 'other_card'),
                hostContractHash: host.contentHash),
            hostContract: host)),
        isFalse);
    final changedHost = SurfaceHostContractV1(
        hosting: SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.single,
            presentation: SurfacePresentationV1.presented),
        providedContext: host.providedContext,
        handledEvents: host.handledEvents);
    expect(
        first.sameDeclarationAs(PlacementMountBinding.request(
            mount: mount, hostContract: changedHost)),
        isFalse);
  });

  test('default key namespaces equal slugs by category', () {
    final paywall = _paywallDefinition();
    final screen = _screenDefinition();
    expect(paywall.key.slug, screen.key.slug);
    expect(paywall.key, isNot(screen.key));
    expect(paywall.defaultSurfaceLocator.family.isGeneral, isTrue);
    expect(screen.defaultSurfaceLocator.family.contractVersion, 3);
    expect(
        screen.hostContract.hosting.contentKind, SurfaceContentKindV1.single);
    expect(
        screen.hostContract.hosting.presentation, SurfacePresentationV1.inline);
    expect(
      SurfaceHostContractV1.fromJson(screen.hostContract.toJson()).contentHash,
      screen.hostContract.contentHash,
    );
    final binding = RestageScreen.generatedPlacementBinding(
      definition: () => screen,
      name: 'screen_slot',
    );
    final host = RestageScreen(
      screen: screen.defaultSurface as SurfaceScreenRef<Never>,
      unavailable: const SurfaceScreenUnavailablePolicy.hide(),
      placementBinding: binding,
    );
    expect((host as RestagePlacementMount).placementBinding, same(binding));
  });

  for (final general in [false, true]) {
    test('flow definition retains its exact decoder ($general)', () {
      final ref = general
          ? const SurfaceFlowRef<Map<String, Object?>>(
              id: 'journey',
              version: 1,
              minClient: 1,
              surface: Surface.general,
              deliveryMode: FlowDeliveryMode.general,
              decodeResult: _decodeGeneral,
            )
          : const SurfaceFlowRef<void>(
              id: 'journey',
              version: 1,
              minClient: 1,
              surface: Surface.onboarding,
              decodeResult: _decodeVoid,
            );
      final surface = general ? Surface.general : Surface.onboarding;
      final definition = RestageFlowGraph.generatedPlacementDefinition(
        defaultSurface: ref,
        defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
          surfaceType: DeliverySurfaceTypeId(surface.wireName),
          slug: 'journey',
          family: const DeliveryFamilySelectorV1.general(),
        ).toJson(),
        hostContractJson: SurfaceHostContractV1(
          hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline,
          ),
          providedContext: const SurfaceScreenHostDataSchema.empty(),
          handledEvents: SurfaceScreenEventSchema(events: const []),
          flowBoundary: FlowHostBoundaryV1(
            deliveryMode:
                general ? FlowDeliveryMode.general : FlowDeliveryMode.typed,
            hostSeedableState: const {},
            actions: const {},
            signals: const {},
            outbound: FlowHostOutboundShapeV1(),
          ),
        ).toJson(),
        vocabulary: SurfaceVocabulary.none,
      );
      expect(definition.defaultSurface, same(ref));
      expect(
          definition.hostContract.flowBoundary!.deliveryMode, ref.deliveryMode);
      expect(definition.defaultSurfaceLocator.family.isGeneral, isTrue);
      final binding = RestageFlowGraph.generatedPlacementBinding(
        definition: () => definition,
        name: 'journey_slot',
      );
      final host = RestageFlowGraph(
        flow: ref,
        unavailable: const FlowUnavailablePolicy.hide(),
        placementBinding: binding,
      );
      expect((host as RestagePlacementMount).placementBinding, same(binding));
    });
  }

  test('definition refuses a renamed key or different locator and family', () {
    final valid = _paywallDefinition();
    GeneratedPlacementDefinition copy({
      DeliverySurfaceLocatorV1? locator,
      PlacementKeyV1? key,
    }) =>
        GeneratedPlacementDefinition(
          defaultSurface: valid.defaultSurface,
          defaultSurfaceLocator: locator ?? valid.defaultSurfaceLocator,
          key: key ?? valid.key,
          hostContract: valid.hostContract,
          vocabulary: valid.vocabulary,
        );
    expect(() => copy(key: PlacementKeyV1.named(slug: 'shared')),
        throwsArgumentError);
    for (final locator in [
      DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('paywall'),
        slug: 'other',
        family: const DeliveryFamilySelectorV1.general(),
      ),
      DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('general'),
        slug: 'shared',
        family: const DeliveryFamilySelectorV1.general(),
      ),
      DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('paywall'),
        slug: 'shared',
        family: DeliveryFamilySelectorV1.screenContract(contractVersion: 3),
      ),
    ]) {
      expect(() => copy(locator: locator), throwsArgumentError);
    }
  });

  test('authoring presentation metadata stays optional and const', () {
    expect(const Screen().presentation, SurfacePresentationRequirement.infer);
    expect(const Paywall().presentation, SurfacePresentationRequirement.infer);
    expect(const FlowGraph(surface: Surface.general).presentation,
        SurfacePresentationRequirement.infer);
    expect(
        const Screen(presentation: SurfacePresentationRequirement.inline)
            .presentation,
        SurfacePresentationRequirement.inline);
    expect(
        const Paywall(presentation: SurfacePresentationRequirement.presented)
            .presentation,
        SurfacePresentationRequirement.presented);
    expect(
        const FlowGraph(
                surface: Surface.general,
                presentation: SurfacePresentationRequirement.presented)
            .presentation,
        SurfacePresentationRequirement.presented);
  });

  testWidgets(
      'old placementId reaches a custom resolver unchanged beside binding',
      (tester) async {
    final resolver = _RecordingResolver();
    final binding = RestagePaywall.generatedPlacementBinding(
      definition: _paywallDefinition,
      name: 'new_slot',
    );
    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'shared',
        // The retained argument remains callable and keeps its resolver meaning.
        // ignore: deprecated_member_use
        placementId: 'legacy-slot',
        placementBinding: binding,
        resolver: resolver,
      ),
    ));
    await tester.pumpAndSettle();
    expect(resolver.ids, ['shared']);
    expect(resolver.placements, ['legacy-slot']);
    expect(find.text('Original resolver content'), findsOneWidget);
    expect(
        tester
            .widget<RestagePaywall>(find.byType(RestagePaywall))
            .placementBinding,
        same(binding));
    expect(tester.widget<RestagePaywall>(find.byType(RestagePaywall)),
        isA<RestagePlacementMount>());
  });
}

GeneratedPlacementDefinition _paywallDefinition() =>
    RestagePaywall.generatedPlacementDefinition(
      id: 'shared',
      defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('paywall'),
        slug: 'shared',
        family: const DeliveryFamilySelectorV1.general(),
      ).toJson(),
      hostContractJson: _singleHost().toJson(),
      vocabulary: SurfaceVocabulary.none,
    );

GeneratedPlacementDefinition _screenDefinition() {
  final events = SurfaceScreenEventSchema(events: const []);
  final ref = SurfaceScreenRef<Never>.generated(
    provenance: SurfaceScreenRuntimeProvenance.generated(
      surface: Surface.general,
      slug: 'shared',
      contractVersion: 3,
      capabilities: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      ),
      eventSchemaJson:
          SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(events),
    ),
    eventContract: SurfaceScreenEventContract<Never>.none(
      hash: SurfaceScreenEventContractHash.hash(events),
    ),
  );
  return RestageScreen.generatedPlacementDefinition(
    defaultSurface: ref,
    defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
      surfaceType: DeliverySurfaceTypeId('general'),
      slug: 'shared',
      family: DeliveryFamilySelectorV1.screenContract(contractVersion: 3),
    ).toJson(),
    hostContractJson: _singleHost().toJson(),
    vocabulary: SurfaceVocabulary.none,
  );
}

SurfaceHostContractV1 _singleHost() => SurfaceHostContractV1(
      hosting: const SurfaceHostingV1(
        contentKind: SurfaceContentKindV1.single,
        presentation: SurfacePresentationV1.inline,
      ),
      providedContext: const SurfaceScreenHostDataSchema.empty(),
      handledEvents: SurfaceScreenEventSchema(events: const []),
    );

Map<String, Object?> _decodeGeneral(Map<String, Object?> result) => result;
void _decodeVoid(Map<String, Object?> result) {}

final class _RecordingResolver implements VariantResolver {
  final ids = <String>[];
  final placements = <String?>[];

  @override
  Future<ResolvedVariant> resolve(String id,
      {String? placementId, Locale? locale}) async {
    ids.add(id);
    placements.add(placementId);
    return ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
import restage.core;
widget Paywall = Text(text: "Original resolver content");
'''))),
      paywallId: id,
      surfaceVersion: 'original',
    );
  }
}
