import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';

const _sourceAsset = 'apps_examples|lib/features/measured.dart';
const _catalogAsset = 'apps_examples|lib/src/widget_catalog/catalog.json';
const _policyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
});
const _bundledPolicyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
  'bundled_runtime': true,
});

const _source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/measured.restage.g.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.measurement'),
  capabilityVersion: 1,
)
const measurementLibrary = 0;

@RestageWidget(
  name: 'InlineAction',
  library: WidgetLibrary.custom('acme.measurement'),
  category: WidgetCategory.input,
  description: 'Inline action.',
)
final class InlineAction extends StatelessWidget {
  const InlineAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        child: const Text('Inline'),
      );
}

@RestageWidget(
  name: 'OpaqueAction',
  library: WidgetLibrary.custom('acme.measurement'),
  category: WidgetCategory.input,
  description: 'App-backed action.',
)
final class OpaqueAction extends StatelessWidget {
  const OpaqueAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ActionPainter());
}

final class _ActionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');
  static const inspect = SurfaceEvent<void>('inspect');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Ordinary'),
          ),
          InlineAction(onPressed: surfaceEvent(activate)),
          OpaqueAction(onPressed: surfaceEvent(activate)),
          FilledButton(
            key: UniqueKey(),
            onPressed: surfaceEvent(activate),
            child: const Text('Repeated A'),
          ),
          FilledButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Repeated B'),
          ),
          GestureDetector(
            onTap: surfaceEvent(activate),
            onDoubleTap: surfaceEvent(inspect),
            child: const Text('Multi-slot'),
          ),
        ],
      );
}
''';

void main() {
  test(
    'default tracked builder emits ordinary, inline, opaque, repeated, and '
    'multi-slot routes before final hashes',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final catalogBuild = await testBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        const {_sourceAsset: _source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(catalogBuild.succeeded, isTrue);
      final catalog = readerWriter.testing.readString(
        AssetId.parse(_catalogAsset),
      );

      final compilerSources = <String, String>{
        _sourceAsset: _source,
        _catalogAsset: catalog,
      };
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
        compilerSources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final compilerOutput =
          RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      expect(compilerOutput.valid, isTrue);
      expect(compilerOutput.publications, hasLength(1));
      final publication = compilerOutput.publications.single;
      expect(publication.routePlan.routes, hasLength(7));
      expect(
        publication.routePlan.routes
            .map((route) => route.generatedReferenceId.value)
            .toSet(),
        hasLength(7),
      );

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      expect(handoff.valid, isTrue);
      final manifestEntry = handoff.manifest!.publications.single;
      final blobArtifact = manifestEntry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      );
      final blob = handoff.artifacts[blobArtifact.path]!;
      expect(CapabilitySidecar.hashBlob(blob), blobArtifact.contentHash);
      final carriers = _eventHandlers(
        fmt.decodeLibraryBlob(Uint8List.fromList(blob)),
      )
          .map(
            (handler) => handler.eventArguments[kMeasurementRouteArgumentKeyV1],
          )
          .whereType<String>()
          .toList();
      expect(carriers, hasLength(7));
      expect(carriers.toSet(), hasLength(7));
      expect(
        carriers.toSet(),
        {
          for (final route in publication.routePlan.routes) route.carrier,
        },
      );
      for (final bytes in [
        ...handoff.artifacts.values,
        ...handoff.borrowedArtifacts.values,
        ...handoff.ownedOutputs.values,
      ]) {
        final text = utf8.decode(bytes, allowMalformed: true);
        expect(text, isNot(contains(kMeasurementRouteReferenceMarkerKeyV1)));
        expect(text, isNot(contains(kMeasurementRouteReferenceMarkerPrefixV1)));
      }
      expect(
        publication.draft.artifacts
            .singleWhere(
              (artifact) => artifact.artifactKind.value == 'rfw.blob',
            )
            .contentHash
            .hex,
        blobArtifact.contentHash.substring('sha256:'.length),
      );
      expect(
        compilerOutput.ledgerNodes
            .map((node) => node.codeIdentityId.value)
            .every((identity) => !identity.contains('lib/features')),
        isTrue,
      );

      final generatedPart = utf8.decode(
        handoff.ownedOutputs.values.singleWhere(
          (bytes) => utf8.decode(bytes).contains('SurfaceScreenBundleLocator'),
        ),
      );
      final sidecarArtifact = manifestEntry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.capabilitySidecar,
      );
      final sidecar = handoff.artifacts[sidecarArtifact.path]!;
      expect(generatedPart, contains(blobArtifact.contentHash));
      expect(generatedPart, contains(sidecarArtifact.contentHash));
      expect(generatedPart, contains('byteLength: ${blob.length}'));
      expect(generatedPart, contains('byteLength: ${sidecar.length}'));
      expect(
        generatedPart,
        contains('generatedWithMeasurementPublicationDraftDigest'),
        reason: 'the delivered generated ScreenSource receives only the final '
            'compiler-owned draft closure carrier',
      );
      expect(
        generatedPart,
        contains(publication.draft.canonicalDigest.hex),
        reason:
            'the carrier is derived after final manifest payload and artifact '
            'bytes have been closed',
      );

      final outputsResult = await testBuilder(
        RestageOutputsBuilder(
          const BuilderOptions({'bundled_runtime': true}),
        ),
        compilerSources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        outputsResult.succeeded,
        isTrue,
        reason: outputsResult.errors.join('\n'),
      );
      final measurementIndexBytes = readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'lib/generated/restage.measurement.index.json',
        ),
      );
      expect(
        measurementIndexBytes,
        orderedEquals(compilerOutput.outputIndexBytes('apps_examples')),
      );
      final measurementIndex = jsonDecode(utf8.decode(measurementIndexBytes))
          as Map<String, Object?>;
      expect(
        measurementIndex.keys.toSet(),
        {'entries', 'kind', 'package', 'schemaVersion'},
      );
      expect(
        measurementIndex['kind'],
        'restageMeasurementPublicationIndex',
      );
      final measurementIndexEntry =
          (measurementIndex['entries']! as List<Object?>).single
              as Map<String, Object?>;
      expect(
        measurementIndexEntry.keys.toSet(),
        {
          'draftBase64',
          'draftDigest',
          'routePlanDigest',
          'selector',
          'surfaceId',
        },
      );
      expect(
        _allJsonKeys(measurementIndex).intersection(const {
          'target',
          'surfaceRevisionId',
          'finalRevisionId',
          'publicationRowId',
        }),
        isEmpty,
      );
    },
  );

  test(
    'default tracked builder leaves Measurement disabled without policy while '
    'emitting no carrier or transient marker',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final catalogBuild = await testBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        const {_sourceAsset: _source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(catalogBuild.succeeded, isTrue);
      final catalog = readerWriter.testing.readString(
        AssetId.parse(_catalogAsset),
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        {_sourceAsset: _source, _catalogAsset: catalog},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final compilerOutput =
          RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      expect(compilerOutput.valid, isTrue);
      expect(compilerOutput.policy, isNull);
      expect(compilerOutput.publications, isEmpty);
      expect(compilerOutput.ledgerNodes, isEmpty);

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      for (final bytes in {
        ...handoff.artifacts,
        ...handoff.borrowedArtifacts,
        ...handoff.ownedOutputs,
      }.values) {
        final text = utf8.decode(bytes, allowMalformed: true);
        expect(text, isNot(contains('__restage_measurement_')));
        expect(
          text,
          isNot(contains('generatedWithMeasurementPublicationDraftDigest')),
        );
      }
    },
  );

  test(
    'finalized generated source carriers rebuild byte-identically and track '
    'the exact final draft closure',
    () async {
      final first = await _compileMeasuredScreenSource(_source);
      final rebuilt = await _compileMeasuredScreenSource(_source);
      final changed = await _compileMeasuredScreenSource(
        _source.replaceFirst("Text('Ordinary')", "Text('Ordinary changed')"),
      );

      expect(first.output.valid, isTrue);
      expect(rebuilt.output.valid, isTrue);
      expect(changed.output.valid, isTrue);
      expect(first.output.canonicalBytes, rebuilt.output.canonicalBytes);
      expect(first.handoffJson, rebuilt.handoffJson);

      final firstPublication = first.output.publications.single;
      final changedPublication = changed.output.publications.single;
      expect(
        changedPublication.draft.canonicalDigest,
        isNot(firstPublication.draft.canonicalDigest),
      );
      expect(
        _generatedCarrierPart(first.handoff),
        contains(firstPublication.draft.canonicalDigest.hex),
      );
      expect(
        _generatedCarrierPart(changed.handoff),
        contains(changedPublication.draft.canonicalDigest.hex),
      );
      expect(changed.handoffJson, isNot(first.handoffJson));
    },
  );

  test(
    'paywall standalone and flow forms each receive their publication carrier '
    'exactly once',
    () async {
      const paywall = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/premium.restage.g.dart';

@Paywall(id: 'premium')
final class PremiumPaywall extends StatelessWidget {
  const PremiumPaywall({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: paywallPurchase(slot: 'primary'),
        child: const Text('Upgrade'),
      );
}
''';
      const intro = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/intro.restage.g.dart';

@Screen(id: 'intro')
final class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Intro');
}
''';
      const flow = '''
import 'package:restage/restage.dart';

import '../features/intro.dart';
import '../paywalls/premium.dart';

part 'restage.generated/offer.restage.g.dart';

@FlowGraph(id: 'offer', surface: Surface.onboarding)
const offer = FlowDefinition(
  start: IntroScreen,
  transitions: [
    Transition(IntroScreen.next, to: PremiumPaywall),
    Transition.complete(PaywallEvents.purchase, from: PremiumPaywall),
  ],
);
''';
      final sources = <String, String>{
        'apps_examples|lib/paywalls/premium.dart': paywall,
        'apps_examples|lib/features/intro.dart': intro,
        'apps_examples|lib/journeys/offer.dart': flow,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(_policyOptions),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final measurement = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      final paywallPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.paywall,
      );
      final flowPublication = measurement.publications.singleWhere(
        (publication) => publication.selector.slug == 'offer',
      );
      expect(paywallPublication.routePlan.routes, hasLength(1));
      expect(flowPublication.routePlan.routes, hasLength(1));
      expect(
        paywallPublication.routePlan.routes.single.generatedReferenceId,
        flowPublication.routePlan.routes.single.generatedReferenceId,
        reason: 'one source event keeps one compiler-ledger reference',
      );
      expect(
        paywallPublication.routePlan.routes.single.carrier,
        isNot(flowPublication.routePlan.routes.single.carrier),
        reason:
            'each publication artifact occurrence has its own complete carrier',
      );

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      final emittedCarriers = <String>[];
      for (final entry in {
        ...handoff.artifacts,
        ...handoff.borrowedArtifacts,
        ...handoff.ownedOutputs,
      }.entries.where((entry) => entry.key.endsWith('.rfw'))) {
        for (final handler in _eventHandlers(
          fmt.decodeLibraryBlob(Uint8List.fromList(entry.value)),
        )) {
          final carrier =
              handler.eventArguments[kMeasurementRouteArgumentKeyV1];
          if (carrier is String) emittedCarriers.add(carrier);
          expect(
            handler.eventArguments,
            isNot(contains(kMeasurementRouteReferenceMarkerKeyV1)),
          );
        }
      }
      expect(
        emittedCarriers,
        unorderedEquals([
          paywallPublication.routePlan.routes.single.carrier,
          flowPublication.routePlan.routes.single.carrier,
        ]),
      );
    },
  );

  test(
    'legacy FlowSource closes over recompiled ScreenSource artifacts and '
    'their final hashes',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onboardingEvent(finish),
        child: const Text('Finish'),
      );
}
''';
      const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'restage.generated/welcome_flow.restage.g.dart';

@FlowSource(id: 'welcome_flow', version: 1, minClient: 1)
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
      final sources = <String, String>{
        'apps_examples|lib/onboarding/screens/welcome.dart': screen,
        'apps_examples|lib/onboarding/flows/welcome_flow.dart': flow,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final screenResult = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        screenResult.succeeded,
        isTrue,
        reason: screenResult.errors.join('\n'),
      );
      final flowResult = await testBuilder(
        onboardingFlowBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        flowResult.succeeded,
        isTrue,
        reason: flowResult.errors.join('\n'),
      );
      final compilerResult = await testBuilder(
        const PackageSurfaceCompilerBuilder(_policyOptions),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        compilerResult.succeeded,
        isTrue,
        reason: compilerResult.errors.join('\n'),
      );

      final measurement = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      final screenPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.screen,
      );
      final flowPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.flowGraph,
      );
      expect(screenPublication.routePlan.routes, hasLength(1));
      expect(flowPublication.routePlan.routes, hasLength(1));
      expect(
        screenPublication.routePlan.routes.single.generatedReferenceId,
        flowPublication.routePlan.routes.single.generatedReferenceId,
      );
      expect(
        screenPublication.routePlan.routes.single.carrier,
        isNot(flowPublication.routePlan.routes.single.carrier),
      );

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      expect(
        () => handoff.manifest!.validateArtifactClosure({
          ...handoff.artifacts,
          ...handoff.borrowedArtifacts,
        }),
        returnsNormally,
      );
      final emittedCarriers = <String>[];
      for (final entry in handoff.manifest!.publications) {
        for (final artifact in entry.artifacts.where(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRole.screenBlob,
        )) {
          final blob = handoff.artifacts[artifact.path] ??
              handoff.borrowedArtifacts[artifact.path]!;
          for (final handler in _eventHandlers(
            fmt.decodeLibraryBlob(Uint8List.fromList(blob)),
          )) {
            final carrier =
                handler.eventArguments[kMeasurementRouteArgumentKeyV1];
            if (carrier is String) emittedCarriers.add(carrier);
          }
        }
      }
      expect(
        emittedCarriers,
        unorderedEquals([
          screenPublication.routePlan.routes.single.carrier,
          flowPublication.routePlan.routes.single.carrier,
        ]),
      );
      final generatedParts = [
        for (final entry in handoff.ownedOutputs.entries)
          if (entry.key.endsWith('.g.dart')) utf8.decode(entry.value),
      ];
      expect(generatedParts, hasLength(2));
      expect(
        generatedParts
            .where(
              (part) => part.contains('WelcomeScreenDescriptor'),
            )
            .single,
        allOf(
          contains('generatedWithMeasurementPublicationDraftDigest'),
          contains(screenPublication.draft.canonicalDigest.hex),
        ),
      );
      expect(
        generatedParts
            .where(
              (part) => part.contains('WelcomeFlowDescriptor'),
            )
            .single,
        allOf(
          contains('generatedWithMeasurementPublicationDraftDigest'),
          contains(flowPublication.draft.canonicalDigest.hex),
        ),
      );
    },
  );

  test(
    'ledger rebuild is stable and source movement requires explicit reviewed '
    'relocation',
    () async {
      final first = await _compileLedgerSource(_ledgerSource());
      expect(first.result.succeeded, isTrue);
      final rebuilt = await _compileLedgerSource(
        _ledgerSource(),
        priorOutput: first.output,
      );
      expect(rebuilt.result.succeeded, isTrue);
      expect(
        _activeLedgerIdentityProjection(rebuilt.output),
        _activeLedgerIdentityProjection(first.output),
      );
      final settled = await _compileLedgerSource(
        _ledgerSource(),
        priorOutput: rebuilt.output,
      );
      expect(settled.result.succeeded, isTrue);
      expect(settled.output.canonicalBytes, rebuilt.output.canonicalBytes);

      final moved = await _compileLedgerSource(
        _ledgerSource(wrapped: true),
        priorOutput: first.output,
      );
      expect(
        moved.result.succeeded,
        isFalse,
        reason:
            'first=${first.output.ledgerNodes.map((node) => node.structuralOccurrenceKey).toList()} '
            'moved=${moved.output.ledgerNodes.map((node) => node.structuralOccurrenceKey).toList()} '
            'next=${first.output.nextIdentitySequence}/'
            '${moved.output.nextIdentitySequence}',
      );
      expect(moved.output.valid, isFalse);
      expect(moved.output.proposals, isNotEmpty);
      expect(moved.output.publications, isEmpty);

      final relocations = <MeasurementCompilerLedgerRelocation>[];
      for (final proposal in moved.output.proposals) {
        expect(proposal.candidatePriorStructuralOccurrenceKeys, hasLength(1));
        final priorLocator =
            proposal.candidatePriorStructuralOccurrenceKeys.single;
        final priorNode = first.output.ledgerNodes.singleWhere(
          (node) => node.structuralOccurrenceKey == priorLocator,
        );
        relocations.add(
          MeasurementCompilerLedgerRelocation(
            fromStructuralOccurrenceKey: priorLocator,
            toStructuralOccurrenceKey: proposal.toStructuralOccurrenceKey,
            codeIdentityId: priorNode.codeIdentityId,
          ),
        );
      }
      final reviewedPrior = RestageMeasurementCompilerOutputV1(
        valid: true,
        errors: const [],
        policy: first.output.policy,
        nextIdentitySequence: first.output.nextIdentitySequence,
        ledgerNodes: first.output.ledgerNodes,
        acceptedRelocations: relocations,
        proposals: const [],
        publications: first.output.publications,
      );
      final accepted = await _compileLedgerSource(
        _ledgerSource(wrapped: true),
        priorOutput: reviewedPrior,
      );
      expect(
        accepted.result.succeeded,
        isTrue,
        reason: accepted.result.errors.join('\n'),
      );
      final firstReference = first.output.ledgerNodes
          .expand((node) => node.events)
          .singleWhere((event) => event.active)
          .generatedReferenceId;
      final acceptedReference = accepted.output.ledgerNodes
          .expand((node) => node.events)
          .singleWhere((event) => event.active)
          .generatedReferenceId;
      expect(acceptedReference, firstReference);
      for (final relocation in relocations) {
        expect(
          accepted.output.ledgerNodes
              .singleWhere(
                (node) =>
                    node.structuralOccurrenceKey ==
                    relocation.toStructuralOccurrenceKey,
              )
              .codeIdentityId,
          relocation.codeIdentityId,
        );
      }
    },
  );

  test('ambiguous structural movement proposes candidates and never aliases',
      () async {
    final first = await _compileLedgerSource(
      _ledgerSource(repeated: true),
    );
    expect(first.result.succeeded, isTrue);
    final ambiguous = await _compileLedgerSource(
      _ledgerSource(wrapped: true),
      priorOutput: first.output,
    );
    expect(ambiguous.result.succeeded, isFalse);
    expect(ambiguous.output.valid, isFalse);
    expect(
      ambiguous.output.proposals.any(
        (proposal) =>
            proposal.candidatePriorStructuralOccurrenceKeys.length > 1,
      ),
      isTrue,
    );
  });

  test('tracked builder rejects malformed committed ledger authority',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(_policyOptions),
      {
        'apps_examples|lib/features/ledger.dart': _ledgerSource(),
        'apps_examples|$kRestageMeasurementCompilerLedgerSourcePath': '{}',
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          kRestageMeasurementCompilerOutputPath,
        ),
      ),
    );
    expect(output.valid, isFalse);
    expect(
      output.errors.join('\n'),
      contains('Measurement compiler state is invalid'),
    );
  });
}

Map<String, Object?> _activeLedgerIdentityProjection(
  RestageMeasurementCompilerOutputV1 output,
) =>
    {
      for (final node in output.ledgerNodes.where((node) => node.active))
        node.structuralOccurrenceKey: {
          'codeIdentityId': node.codeIdentityId.value,
          'canonicalNodeTokenId': node.canonicalNodeTokenId.value,
          'events': {
            for (final event in node.events.where((event) => event.active))
              event.resolvedEventLocator: {
                'generatedReferenceId': event.generatedReferenceId.value,
                'lineageId': event.lineageId.value,
              },
          },
        },
    };

String _ledgerSource({bool wrapped = false, bool repeated = false}) {
  final button = '''
FilledButton(
  onPressed: surfaceEvent(activate),
  child: const Text('Activate'),
)
''';
  final body = repeated
      ? 'Column(children: [$button, $button])'
      : wrapped
          ? 'Padding(padding: const EdgeInsets.all(8), child: $button)'
          : button;
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/ledger.restage.g.dart';

@Screen(id: 'ledger', surface: Surface.general)
final class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => $body;
}
''';
}

Future<
    ({
      TestBuilderResult result,
      RestageMeasurementCompilerOutputV1 output,
    })> _compileLedgerSource(
  String source, {
  RestageMeasurementCompilerOutputV1? priorOutput,
}) async {
  const asset = 'apps_examples|lib/features/ledger.dart';
  final sources = <String, String>{
    asset: source,
    if (priorOutput != null)
      'apps_examples|$kRestageMeasurementCompilerLedgerSourcePath':
          priorOutput.encodeCanonicalJson(),
  };
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(_policyOptions),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        kRestageMeasurementCompilerOutputPath,
      ),
    ),
  );
  return (result: result, output: output);
}

Future<
    ({
      RestageMeasurementCompilerOutputV1 output,
      RestageSurfacePublicationBundle handoff,
      String handoffJson,
    })> _compileMeasuredScreenSource(String source) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final catalogBuild = await testBuilder(
    const UserCatalogJsonBuilder(BuilderOptions.empty),
    <String, String>{_sourceAsset: source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(
    catalogBuild.succeeded,
    isTrue,
    reason: catalogBuild.errors.join('\n'),
  );
  final catalog = readerWriter.testing.readString(
    AssetId.parse(_catalogAsset),
  );
  final compilation = await testBuilder(
    const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
    <String, String>{_sourceAsset: source, _catalogAsset: catalog},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(
    compilation.succeeded,
    isTrue,
    reason: compilation.errors.join('\n'),
  );
  final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
    ),
  );
  final handoffJson = readerWriter.testing.readString(
    AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
  );
  return (
    output: output,
    handoff: RestageSurfacePublicationBundle.fromJson(
      jsonDecode(handoffJson) as Map<String, Object?>,
    ),
    handoffJson: handoffJson,
  );
}

String _generatedCarrierPart(RestageSurfacePublicationBundle handoff) =>
    utf8.decode(
      handoff.ownedOutputs.entries
          .singleWhere(
            (entry) => entry.key.endsWith('.g.dart'),
          )
          .value,
    );

List<fmt.EventHandler> _eventHandlers(fmt.RemoteWidgetLibrary library) {
  final handlers = <fmt.EventHandler>[];

  void visit(Object? value) {
    switch (value) {
      case fmt.RemoteWidgetLibrary library:
        for (final widget in library.widgets) {
          visit(widget);
        }
      case fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case fmt.EventHandler handler:
        handlers.add(handler);
        visit(handler.eventArguments);
      case fmt.ConstructorCall call:
        visit(call.arguments);
      case fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case fmt.Switch switchNode:
        visit(switchNode.input);
        for (final output in switchNode.outputs.values) {
          visit(output);
        }
      case Map<Object?, Object?> map:
        for (final entry in map.entries) {
          visit(entry.value);
        }
      case List<Object?> list:
        for (final item in list) {
          visit(item);
        }
      default:
        break;
    }
  }

  visit(library);
  return handlers;
}

Set<String> _allJsonKeys(Object? value) => switch (value) {
      Map<String, Object?>() => {
          ...value.keys,
          for (final child in value.values) ..._allJsonKeys(child),
        },
      List<Object?>() => {
          for (final child in value) ..._allJsonKeys(child),
        },
      _ => const {},
    };
