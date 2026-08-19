import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler.dart';
import 'package:restage_codegen/src/surface_publication/paywall_artifact_adapter.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('package surface compiler', () {
    test('recognizes only the exact roster-owned generated part', () async {
      const sourceId = 'apps_examples|lib/surfaces/categorized_screens.dart';
      const source = '''
part 'restage.generated/categorized_screens.restage.g.dart';
part 'restage.generated/lookalike.restage.g.dart';

final authoredCollisionRef = Object();
''';
      const ownGeneratedPart = '''
part of '../categorized_screens.dart';

final ownGeneratedRef = Object();
''';
      const foreignGeneratedPart = '''
part of '../categorized_screens.dart';

final foreignGeneratedRef = Object();
''';

      await resolveSources(
        {
          sourceId: source,
          'apps_examples|lib/surfaces/restage.generated/categorized_screens.restage.g.dart':
              ownGeneratedPart,
          'apps_examples|lib/surfaces/restage.generated/lookalike.restage.g.dart':
              foreignGeneratedPart,
        },
        (resolver) async {
          final library = await resolver.libraryFor(AssetId.parse(sourceId));
          final sourceDeclaration = RestageSourceDeclaration.frozen(
            kind: RestageRosterSourceKind.screen,
            libraryIdentity: library.identifier,
            libraryPath: 'lib/surfaces/categorized_screens.dart',
            declarationIdentity: '${library.identifier}#categorizedScreens',
            sourcePath: 'lib/surfaces/categorized_screens.dart',
            explicitId: 'categorized_screens',
            span: const RestageSourceSpan(
              path: 'lib/surfaces/categorized_screens.dart',
              startLine: 1,
              startColumn: 1,
              endLine: 1,
              endColumn: 1,
            ),
            identityClaims: const [],
            outputs: const [
              RestageOutputClaim(
                path:
                    'lib/surfaces/restage.generated/categorized_screens.restage.g.dart',
                role: 'screen-descriptor',
                builder: 'test',
              ),
            ],
            isCanonical: true,
          );

          final names = topLevelNamesForGeneratedSymbolCollision(
            library,
            sourceDeclaration,
          );
          expect(names, isNot(contains('ownGeneratedRef')));
          expect(names, contains('authoredCollisionRef'));
          expect(names, contains('foreignGeneratedRef'));
        },
        resolverFor: sourceId,
        rootPackage: 'apps_examples',
        readAllSourcesFromFilesystem: true,
      );
    });

    test(
      'assembles general publications, neutral reuse, and an embedded paywall',
      () async {
        final scenario = await _loadScenario();
        final result = compilePackageSurfacePublications(scenario.input);

        expect(result.issues, isEmpty);
        expect(result.bundle, isNotNull);
        final bundle = result.bundle!;

        expect(
          bundle.manifest.publications
              .map((entry) => entry.publication.surface.wireName)
              .toList(),
          orderedEquals(['general', 'general', 'general', 'paywall']),
        );
        expect(
          bundle.manifest.publications
              .map((entry) => entry.publication.slug)
              .toList(),
          orderedEquals([
            'announcement',
            'follow_up',
            'general_flow',
            'premium',
          ]),
        );

        final standalone = bundle.manifest.publications.singleWhere(
          (entry) => entry.publication.slug == 'announcement',
        );
        expect(standalone.publication.surface, Surface.general);
        expect(standalone.publication.sourceKind, SurfaceSourceKind.screen);
        expect(
          standalone.publication.eventContract,
          isNotNull,
          reason: 'standalone contracts retain their complete event schema',
        );
        expect(standalone.publication.eventContractHash, isNotNull);

        final generalFlow = bundle.manifest.publications.singleWhere(
          (entry) => entry.publication.slug == 'general_flow',
        );
        final flowArtifacts = generalFlow.artifacts;
        expect(
          flowArtifacts
              .where(
                (artifact) =>
                    artifact.role ==
                    SurfacePublicationArtifactRoleV1.screenBlob,
              )
              .map((artifact) => artifact.id)
              .toList(),
          orderedEquals(['paywall_premium', 'welcome']),
        );
        expect(
          flowArtifacts
              .where(
                (artifact) =>
                    artifact.role ==
                    SurfacePublicationArtifactRoleV1.capabilitySidecar,
              )
              .map((artifact) => artifact.id)
              .toList(),
          orderedEquals(['paywall_premium', 'welcome']),
        );

        final followUp = bundle.manifest.publications.singleWhere(
          (entry) => entry.publication.slug == 'follow_up',
        );
        final welcomeBlob = flowArtifacts.singleWhere(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRoleV1.screenBlob &&
              artifact.id == 'welcome',
        );
        expect(
          followUp.artifacts.any(
            (artifact) =>
                artifact.role == SurfacePublicationArtifactRoleV1.screenBlob &&
                artifact.path == welcomeBlob.path &&
                artifact.contentHash == welcomeBlob.contentHash,
          ),
          isTrue,
          reason:
              'the same neutral screen closure can serve more than one flow',
        );

        expect(
          bundle.outputFiles.keys,
          containsAll([
            'assets/restage/generated/general/announcement/screen.rfw',
            'assets/restage/generated/general/general_flow/flow.json',
            'assets/restage/generated/paywall/premium/screen.capability.json',
          ]),
        );
        expect(
          bundle.manifestFiles.keys,
          containsAll([
            'assets/restage/generated/general/announcement/screen.rfw',
            'assets/restage/generated/general/general_flow/flow.json',
            'assets/restage/generated/paywall/premium/screen.capability.json',
          ]),
        );
        expect(
          bundle.manifestFiles.keys,
          isNot(
            contains(
              'assets/restage/generated/general/announcement/screen.rfwtxt',
            ),
          ),
          reason: 'the owner handoff contains only the strict delivery closure',
        );
        expect(
          () => bundle.manifest.validateArtifactClosure(bundle.manifestFiles),
          returnsNormally,
        );
        expect(
          SurfacePublicationManifestV1Codec.encodeCanonicalJson(
            SurfacePublicationManifestV1Codec.decodeJson(bundle.manifestJson),
          ),
          bundle.manifestJson,
          reason: 'the strict manifest assembler round-trips canonical bytes',
        );
        // One authored library shares one generated neutral part across
        // every one of its declarations.
        expect(
          bundle.generatedParts.keys,
          contains('lib/restage.generated/authoring.restage.g.dart'),
        );
        expect(
          bundle
              .generatedParts['lib/restage.generated/authoring.restage.g.dart'],
          allOf(
            startsWith("part of '../authoring.dart';"),
            contains('SurfaceScreenRef<AnnouncementEvent>'),
            isNot(contains('NeutralFlowScreenRef.generated')),
            contains('const generalFlowRef ='),
            contains('SurfaceFlowRef<GeneralFlowResult>'),
            contains('final class GeneralFlowSeed implements FlowSeed'),
          ),
        );

        await _assertGeneratedPartsAnalyze(
          scenario.source,
          bundle.generatedParts,
        );
      },
    );

    test('is deterministic when aggregate inputs arrive in a different order',
        () async {
      final scenario = await _loadScenario();
      final first = compilePackageSurfacePublications(scenario.input);
      final reversed = compilePackageSurfacePublications(
        PackageSurfaceCompilationInput(
          roster: scenario.input.roster,
          flows: scenario.input.flows.reversed,
          renderedSources: scenario.input.renderedSources.reversed,
          standaloneScreens: scenario.input.standaloneScreens.reversed,
        ),
      );

      expect(first.issues, isEmpty);
      expect(reversed.issues, isEmpty);
      expect(first.bundle!.manifestJson, reversed.bundle!.manifestJson);
      expect(first.bundle!.generatedParts, reversed.bundle!.generatedParts);
      expect(
        _encodeFiles(first.bundle!.outputFiles),
        _encodeFiles(reversed.bundle!.outputFiles),
      );
    });

    test('resolves child flow closure by surface and id, never slug alone',
        () async {
      final scenario = await _loadScenario();
      final baseFlow = scenario.input.flows.singleWhere(
        (flow) => flow.id == 'general_flow',
      );
      final source = scenario.input.roster.declarations.singleWhere(
        (candidate) =>
            candidate.kind == RestageRosterSourceKind.flow &&
            candidate.effectiveId == baseFlow.id,
      );
      const generalIdentity = NormalizedFlowIdentity(
        surface: Surface.general,
        id: 'child',
      );
      const messageIdentity = NormalizedFlowIdentity(
        surface: Surface.message,
        id: 'child',
      );
      final generalChild = FlowDocumentCodec.encodeCanonicalJson(
        const FlowDocument(
          flow: 'child',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          initial: 'general_done',
          screenArtifacts: {},
          states: {'general_done': EndFlowState(result: {})},
        ),
      );
      final messageChild = FlowDocumentCodec.encodeCanonicalJson(
        const FlowDocument(
          flow: 'child',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          initial: 'message_done',
          screenArtifacts: {},
          states: {'message_done': EndFlowState(result: {})},
        ),
      );
      final flow = NormalizedFlowSource(
        id: baseFlow.id,
        hasExplicitId: true,
        version: 1,
        minClient: 1,
        surface: Surface.general,
        delivery: FlowDeliveryMode.typed,
        declaration: baseFlow.declaration,
        isCanonical: true,
        graph: NormalizedFlowGraph(
          flow: baseFlow.id,
          version: 1,
          minClient: 1,
          delivery: FlowDeliveryMode.typed,
          initial: 'child_state',
          states: {
            'child_state': SubFlowState(
              flow: 'child',
              version: 1,
              schemaVersion: 1,
              minClient: 1,
              contentHash: FlowContentHash.compute(const []),
              input: const {},
              onComplete: const [],
              defaultBranch: const FlowBranchTarget(target: 'done'),
            ),
            'done': const EndFlowState(result: {}),
          },
          flowState: const {},
          outbound: const FlowOutboundDeclarations(),
          actions: const {},
          screens: const {},
          childFlows: {
            generalIdentity: const NormalizedChildFlowReference(
              identity: generalIdentity,
              version: 1,
              minClient: 1,
              declarationIdentity: 'package:fixture/general.dart#child',
            ),
            messageIdentity: const NormalizedChildFlowReference(
              identity: messageIdentity,
              version: 1,
              minClient: 1,
              declarationIdentity: 'package:fixture/message.dart#child',
            ),
          },
        ),
      );

      final result = compileCanonicalFlowArtifact(
        flow: flow,
        source: source,
        screenArtifacts: const {},
        childFlowDocuments: {
          generalIdentity: generalChild,
          messageIdentity: messageChild,
        },
      );

      expect(result.issues, isEmpty);
      final document = FlowDocumentCodec.decodeJson(
        utf8.decode(result.compilation!.flowDocumentBytes),
      );
      expect(
        (document.states['child_state']! as SubFlowState).contentHash,
        FlowContentHash.compute(generalChild),
      );
      expect(
        (document.states['child_state']! as SubFlowState).contentHash,
        isNot(FlowContentHash.compute(messageChild)),
      );
    });

    test('rejects a categorized ordinary screen in another flow category',
        () async {
      final scenario = await _loadScenario();
      final result = compilePackageSurfacePublications(
        PackageSurfaceCompilationInput(
          roster: scenario.mismatchedRoster,
          flows: [...scenario.input.flows, scenario.mismatchedFlow],
          renderedSources: scenario.input.renderedSources,
          standaloneScreens: scenario.input.standaloneScreens,
        ),
      );

      expect(result.bundle, isNull);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('cannot be included in flow mismatch_flow'),
      );
    });

    test('consumes the paywall adapter as an embedded flow-screen artifact',
        () async {
      final scenario = await _loadScenario();
      final premium = scenario.input.renderedSources.singleWhere(
        (artifact) => artifact.declaration.name == 'Premium',
      );
      final standaloneBlob = Uint8List.fromList(utf8.encode('standalone'));
      final adapterBlob = Uint8List.fromList(utf8.encode('adapter'));
      final facts = PaywallArtifactAdapter.fromFiles(
        slug: 'premium',
        standaloneBlobPath: 'assets/paywalls/premium.rfw',
        standaloneCapabilityPath: 'assets/paywalls/premium.capability.json',
        adapterBlobPath: 'assets/paywalls/screens/paywall_premium.rfw',
        adapterCapabilityPath:
            'assets/paywalls/screens/paywall_premium.capability.json',
        flowDocumentPath: 'assets/paywalls/premium.flow.json',
        files: {
          'assets/paywalls/premium.rfw': standaloneBlob,
          'assets/paywalls/premium.capability.json': _sidecarBytes(
            standaloneBlob,
          ),
          'assets/paywalls/screens/paywall_premium.rfw': adapterBlob,
          'assets/paywalls/screens/paywall_premium.capability.json':
              _sidecarBytes(adapterBlob),
        },
      );

      final artifact = CompiledSurfaceArtifact.fromPaywallAdapter(
        declaration: premium.declaration,
        facts: facts,
        flowArtifactPath: 'paywall_premium.rfw',
        rfwText: utf8.encode('remote paywall'),
      );

      expect(artifact.flowScreenId, 'paywall_premium');
      expect(artifact.blob, orderedEquals(adapterBlob));
      expect(
        artifact.capabilitySidecar,
        orderedEquals(_sidecarBytes(adapterBlob)),
      );
    });

    test(
        'returns no partial bundle when a roster-owned output family is '
        'incomplete', () async {
      final scenario = await _loadScenario();
      final incomplete = <CompiledSurfaceArtifact>[
        for (final artifact in scenario.input.renderedSources)
          if (artifact.declaration.name == 'Welcome')
            CompiledSurfaceArtifact(
              declaration: artifact.declaration,
              blob: artifact.blob,
              capabilitySidecar: artifact.capabilitySidecar,
              flowArtifactPath: artifact.flowArtifactPath,
            )
          else
            artifact,
      ];
      final result = compilePackageSurfacePublications(
        PackageSurfaceCompilationInput(
          roster: scenario.input.roster,
          flows: scenario.input.flows,
          renderedSources: incomplete,
          standaloneScreens: scenario.input.standaloneScreens,
        ),
      );

      expect(result.bundle, isNull);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('missing its roster-owned screen-text artifact'),
      );
    });
  });
}

Future<_Scenario> _loadScenario() async {
  const sourceId = 'apps_examples|lib/authoring.dart';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  readerWriter.testing.writeString(AssetId.parse(sourceId), _source);

  _Scenario? scenario;
  await testBuilder(
    _ScenarioProbeBuilder((library, assetId) {
      scenario = _scenarioFromLibrary(library, assetId);
    }),
    const {sourceId: _source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  return scenario!;
}

_Scenario _scenarioFromLibrary(LibraryElement library, AssetId assetId) {
  final announcement = _class(library, 'Announcement');
  final welcome = _class(library, 'Welcome');
  final premium = _class(library, 'Premium');
  final generalFlow = _variable(library, 'generalFlow');
  final followUp = _variable(library, 'followUp');
  final mismatch = _variable(library, 'mismatch');
  final capabilities = CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  );

  final contractInspection = inspectStandaloneScreenContract(
    ResolvedStandaloneScreenContractInput(
      assetId: assetId,
      screen: announcement,
      surface: Surface.general,
      slug: 'announcement',
      contractVersion: 1,
      capabilities: capabilities,
    ),
  );
  expect(
    contractInspection.issues,
    isEmpty,
    reason: contractInspection.issues.map((issue) => issue.message).join('\n'),
  );

  final declarations = [
    _screenDeclaration(
      library: library,
      declaration: announcement,
      id: 'announcement',
      surface: Surface.general,
    ),
    _screenDeclaration(
      library: library,
      declaration: welcome,
      id: 'welcome',
    ),
    _screenDeclaration(
      library: library,
      declaration: premium,
      id: 'premium',
      surface: Surface.paywall,
      kind: RestageRosterSourceKind.paywall,
    ),
    _flowDeclaration(
      library: library,
      declaration: generalFlow,
      id: 'general_flow',
      surface: Surface.general,
    ),
    _flowDeclaration(
      library: library,
      declaration: followUp,
      id: 'follow_up',
      surface: Surface.general,
    ),
  ];
  final roster = assembleRestageSourceRoster(declarations);
  final mismatchedRoster = assembleRestageSourceRoster([
    ...declarations,
    _flowDeclaration(
      library: library,
      declaration: mismatch,
      id: 'mismatch_flow',
      surface: Surface.onboarding,
    ),
  ]);
  expect(
    roster.issues,
    isEmpty,
    reason: roster.issues.map((issue) => issue.message).join('\n'),
  );

  final announcementRef = _screenReference(
    id: 'announcement',
    element: announcement,
    declaredSurface: Surface.general,
    effectiveSurface: Surface.general,
  );
  final welcomeRef = _screenReference(
    id: 'welcome',
    element: welcome,
    effectiveSurface: Surface.general,
  );
  final premiumRef = _screenReference(
    id: 'paywall_premium',
    element: premium,
    declaredSurface: Surface.paywall,
    effectiveSurface: Surface.paywall,
    isPaywall: true,
  );
  final premiumBlob = Uint8List.fromList(utf8.encode('RFW:premium'));
  final standalonePremiumBlob =
      Uint8List.fromList(utf8.encode('standalone:premium'));
  final premiumFacts = PaywallArtifactAdapter.fromFiles(
    slug: 'premium',
    standaloneBlobPath:
        'assets/restage/generated/paywall/premium/standalone.rfw',
    standaloneCapabilityPath:
        'assets/restage/generated/paywall/premium/standalone.capability.json',
    adapterBlobPath: 'assets/restage/generated/paywall/premium/screen.rfw',
    adapterCapabilityPath:
        'assets/restage/generated/paywall/premium/screen.capability.json',
    flowDocumentPath: 'assets/restage/generated/paywall/premium/flow.json',
    files: {
      'assets/restage/generated/paywall/premium/standalone.rfw':
          standalonePremiumBlob,
      'assets/restage/generated/paywall/premium/standalone.capability.json':
          _sidecarBytes(standalonePremiumBlob),
      'assets/restage/generated/paywall/premium/screen.rfw': premiumBlob,
      'assets/restage/generated/paywall/premium/screen.capability.json':
          _sidecarBytes(premiumBlob),
    },
  );
  final general = _flow(
    declaration: generalFlow,
    id: 'general_flow',
    surface: Surface.general,
    graph: NormalizedFlowGraph(
      flow: 'general_flow',
      version: 1,
      minClient: 1,
      delivery: FlowDeliveryMode.typed,
      initial: 'welcome',
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'continue': GotoFlowTransition('paywall_premium')},
        ),
        'paywall_premium': ScreenFlowState(
          screen: 'paywall_premium',
          on: {'purchase': GotoFlowTransition('done')},
        ),
        'done': EndFlowState(result: {}),
      },
      flowState: const {
        'name': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
          hostSeedable: true,
        ),
      },
      outbound: const FlowOutboundDeclarations(),
      actions: const {},
      screens: {'welcome': welcomeRef, 'paywall_premium': premiumRef},
    ),
  );
  final follow = _flow(
    declaration: followUp,
    id: 'follow_up',
    surface: Surface.general,
    graph: NormalizedFlowGraph(
      flow: 'follow_up',
      version: 1,
      minClient: 1,
      delivery: FlowDeliveryMode.typed,
      initial: 'welcome',
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'dismiss': GotoFlowTransition('done')},
        ),
        'done': EndFlowState(result: {}),
      },
      flowState: const {},
      outbound: const FlowOutboundDeclarations(),
      actions: const {},
      screens: {'welcome': welcomeRef},
    ),
  );
  final mismatched = _flow(
    declaration: mismatch,
    id: 'mismatch_flow',
    surface: Surface.onboarding,
    graph: NormalizedFlowGraph(
      flow: 'mismatch_flow',
      version: 1,
      minClient: 1,
      delivery: FlowDeliveryMode.typed,
      initial: 'announcement',
      states: const {
        'announcement': ScreenFlowState(
          screen: 'announcement',
          on: {'dismiss': GotoFlowTransition('done')},
        ),
        'done': EndFlowState(result: {}),
      },
      flowState: const {},
      outbound: const FlowOutboundDeclarations(),
      actions: const {},
      screens: {'announcement': announcementRef},
    ),
  );

  return _Scenario(
    source: _source,
    input: PackageSurfaceCompilationInput(
      roster: roster,
      flows: [general, follow],
      renderedSources: [
        _artifact(announcement, id: 'announcement'),
        _artifact(welcome, id: 'welcome'),
        _artifact(
          premium,
          id: 'premium',
          flowScreenId: 'paywall_premium',
          paywallFacts: premiumFacts,
        ),
      ],
      standaloneScreens: [contractInspection.contract!],
    ),
    mismatchedFlow: mismatched,
    mismatchedRoster: mismatchedRoster,
  );
}

RestageSourceDeclaration _screenDeclaration({
  required LibraryElement library,
  required ClassElement declaration,
  required String id,
  Surface? surface,
  RestageRosterSourceKind kind = RestageRosterSourceKind.screen,
}) {
  final surfacePath = surface?.wireName ?? 'neutral';
  final root = kind == RestageRosterSourceKind.paywall
      ? 'assets/restage/generated/paywall/$id'
      : 'assets/restage/generated/$surfacePath/$id';
  return RestageSourceDeclaration.frozen(
    kind: kind,
    libraryIdentity: library.identifier,
    libraryPath: 'lib/authoring.dart',
    declarationIdentity: _identity(declaration),
    sourcePath: 'lib/authoring.dart',
    explicitId: id,
    span: const RestageSourceSpan(
      path: 'lib/authoring.dart',
      startLine: 1,
      startColumn: 1,
      endLine: 1,
      endColumn: 1,
    ),
    identityClaims: [
      RestageIdentityClaim(
        namespace: 'test/${kind.wireName}/$surfacePath',
        key: id,
      ),
    ],
    outputs: [
      if (kind == RestageRosterSourceKind.screen)
        RestageOutputClaim(
          path: 'lib/restage.generated/authoring.restage.g.dart',
          role: 'screen-descriptor',
          builder: 'test',
          ownershipKey: 'library:${library.identifier}',
        ),
      RestageOutputClaim(
        path: '$root/screen.rfwtxt',
        role: 'screen-text',
        builder: 'test',
        ownershipKey: 'publication:$surfacePath/$id',
      ),
      RestageOutputClaim(
        path: '$root/screen.rfw',
        role: kind == RestageRosterSourceKind.paywall
            ? 'flow-screen-blob'
            : 'screen-blob',
        builder: 'test',
        ownershipKey: 'publication:$surfacePath/$id',
      ),
      RestageOutputClaim(
        path: '$root/screen.capability.json',
        role: kind == RestageRosterSourceKind.paywall
            ? 'flow-screen-capability-sidecar'
            : 'capability-sidecar',
        builder: 'test',
        ownershipKey: 'publication:$surfacePath/$id',
      ),
    ],
    surface: surface,
    isCanonical: true,
  );
}

RestageSourceDeclaration _flowDeclaration({
  required LibraryElement library,
  required TopLevelVariableElement declaration,
  required String id,
  required Surface surface,
}) =>
    RestageSourceDeclaration.frozen(
      kind: RestageRosterSourceKind.flow,
      libraryIdentity: library.identifier,
      libraryPath: 'lib/authoring.dart',
      declarationIdentity: _identity(declaration),
      sourcePath: 'lib/authoring.dart',
      explicitId: id,
      span: const RestageSourceSpan(
        path: 'lib/authoring.dart',
        startLine: 1,
        startColumn: 1,
        endLine: 1,
        endColumn: 1,
      ),
      identityClaims: [
        RestageIdentityClaim(
          namespace: 'test/flow/${surface.wireName}',
          key: id,
        ),
      ],
      outputs: [
        RestageOutputClaim(
          path: 'lib/restage.generated/authoring.restage.g.dart',
          role: 'flow-descriptor',
          builder: 'test',
          ownershipKey: 'library:${library.identifier}',
        ),
        RestageOutputClaim(
          path: 'assets/restage/generated/${surface.wireName}/$id/flow.json',
          role: 'flow-document',
          builder: 'test',
          ownershipKey: 'publication:${surface.wireName}/$id',
        ),
      ],
      surface: surface,
      delivery: FlowDeliveryMode.typed,
      isCanonical: true,
    );

NormalizedScreenReference _screenReference({
  required String id,
  required ClassElement element,
  required Surface effectiveSurface,
  Surface? declaredSurface,
  bool isPaywall = false,
}) =>
    NormalizedScreenReference(
      id: id,
      element: element,
      declaredSurface: declaredSurface,
      effectiveSurface: effectiveSurface,
      isPaywall: isPaywall,
      version: 1,
      minClient: 1,
    );

NormalizedFlowSource _flow({
  required TopLevelVariableElement declaration,
  required String id,
  required Surface surface,
  required NormalizedFlowGraph graph,
}) =>
    NormalizedFlowSource(
      id: id,
      hasExplicitId: true,
      version: 1,
      minClient: 1,
      surface: surface,
      delivery: FlowDeliveryMode.typed,
      declaration: declaration,
      isCanonical: true,
      graph: graph,
    );

CompiledSurfaceArtifact _artifact(
  ClassElement declaration, {
  required String id,
  String? flowScreenId,
  PaywallArtifactFacts? paywallFacts,
}) {
  final blob = Uint8List.fromList(utf8.encode('RFW:$id'));
  final sidecar = CapabilitySidecar(
    blobSha256: CapabilitySidecar.hashBlob(blob),
    manifest: CapabilityManifest(
      builtInFloor: 1,
      requiredLibraries: const [],
    ),
  );
  return CompiledSurfaceArtifact(
    declaration: declaration,
    blob: blob,
    capabilitySidecar: utf8.encode(jsonEncode(sidecar.toJson())),
    flowArtifactPath: '$id.rfw',
    flowScreenId: flowScreenId,
    paywallFacts: paywallFacts,
    rfwText: utf8.encode('remote widget $id'),
  );
}

ClassElement _class(LibraryElement library, String name) =>
    library.classes.singleWhere((candidate) => candidate.name == name);

TopLevelVariableElement _variable(LibraryElement library, String name) =>
    library.topLevelVariables
        .singleWhere((candidate) => candidate.name == name);

String _identity(Element element) =>
    '${element.library!.identifier}#${element.name ?? '<unnamed>'}';

Map<String, String> _encodeFiles(Map<String, Uint8List> files) => {
      for (final entry in files.entries) entry.key: base64Encode(entry.value),
    };

List<int> _sidecarBytes(List<int> blob) => utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [],
          ),
        ).toJson(),
      ),
    );

Future<void> _assertGeneratedPartsAnalyze(
  String source,
  Map<String, String> generatedParts,
) async {
  const sourceId = 'apps_examples|lib/authoring.dart';
  await resolveSources(
    {
      sourceId: source,
      for (final entry in generatedParts.entries)
        'apps_examples|${entry.key}': entry.value,
    },
    (resolver) async {
      final library = await resolver.libraryFor(AssetId.parse(sourceId));
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('Generated package source did not resolve.');
      }
      final errors = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error)
              diagnostic.problemMessage.messageText(includeUrl: false),
      ];
      expect(errors, isEmpty, reason: generatedParts.values.join('\n'));
    },
    resolverFor: sourceId,
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
}

const _source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/authoring.restage.g.dart';

@Screen(id: 'announcement', surface: Surface.general)
final class Announcement extends StatelessWidget {
  const Announcement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'welcome')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Paywall(id: 'premium')
final class Premium extends StatelessWidget {
  const Premium({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final generalFlow = Object();
final followUp = Object();
final mismatch = Object();
''';

final class _Scenario {
  const _Scenario({
    required this.source,
    required this.input,
    required this.mismatchedFlow,
    required this.mismatchedRoster,
  });

  final String source;
  final PackageSurfaceCompilationInput input;
  final NormalizedFlowSource mismatchedFlow;
  final RestageSourceRoster mismatchedRoster;
}

final class _ScenarioProbeBuilder implements Builder {
  const _ScenarioProbeBuilder(this.onLibrary);

  final void Function(LibraryElement library, AssetId assetId) onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.package_surface_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path != 'lib/authoring.dart') return;
    onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}
