import 'dart:typed_data';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _opaqueProbeLibrary = 'package:apps_examples/_expr_probe.dart';
const _opaqueClassKey = '$_opaqueProbeLibrary#OpaqueAction';

void main() {
  group('opaque custom-widget measurement slots', () {
    test(
      'discovers only catalog-declared slots with exact declaration provenance',
      () async {
        final resolved = await _resolveOpaqueOccurrences(_opaqueWidgetSource());
        final slots = MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
          sourceRoot: resolved.sourceRoot,
          occurrence: resolved.occurrences.first,
          catalog: _opaqueCatalog(),
        );

        expect(
          slots,
          hasLength(1),
          reason: 'the declared scalar label is not an event slot',
        );
        final slot = slots.single;
        expect(slot.sourceRootKind, MeasurementSourceRootKind.paywallSource);
        expect(slot.declarationProvenance.libraryUri, _opaqueProbeLibrary);
        expect(slot.declarationProvenance.className, 'OpaqueAction');
        expect(slot.declarationProvenance.memberName, 'onActivate');
        expect(
          slot.declarationProvenance.sourceSelector.value,
          'onActivate',
        );
        expect(slot.sourceEventIdentity.value, 'onActivate');
        expect(slot.catalogWidgetWireId.value, 'w0001');
        expect(slot.catalogLibraryNamespace, 'example.opaque');
        expect(
          slots.map((candidate) => candidate.sourceEventIdentity.value),
          isNot(contains('onPressed')),
          reason: 'the private Flutter implementation is outside the boundary',
        );
      },
    );

    test('joins a named constructor to its exact catalog identity', () async {
      final resolved = await _resolveOpaqueOccurrences(
        _opaqueWidgetSource(namedConstructor: true),
      );
      final slots = MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
        sourceRoot: resolved.sourceRoot,
        occurrence: resolved.occurrences.first,
        catalog: _opaqueCatalog(flutterType: '$_opaqueClassKey.named'),
      );

      expect(slots, hasLength(1));
      expect(slots.single.sourceEventIdentity.value, 'onActivate');
    });

    test('accepts only exact ScreenSource, PaywallSource, and FlowSource roots',
        () async {
      const expectedKinds = <String, MeasurementSourceRootKind>{
        'ScreenSource': MeasurementSourceRootKind.screenSource,
        'PaywallSource': MeasurementSourceRootKind.paywallSource,
        'FlowSource': MeasurementSourceRootKind.flowSource,
      };

      for (final entry in expectedKinds.entries) {
        final resolved = await _resolveOpaqueOccurrences(
          _opaqueWidgetSource(rootAnnotation: entry.key),
        );
        final slots = MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
          sourceRoot: resolved.sourceRoot,
          occurrence: resolved.occurrences.first,
          catalog: _opaqueCatalog(),
        );

        expect(slots.single.sourceRootKind, entry.value, reason: entry.key);
      }
    });

    test(
        'fails closed for undeclared, lookalike, ambiguous, mismatched, and '
        'unsupported opaque slots', () async {
      Future<void> expectRejected(String source, Catalog catalog) async {
        final resolved = await _resolveOpaqueOccurrences(source);
        expect(
          () => MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
            sourceRoot: resolved.sourceRoot,
            occurrence: resolved.occurrences.first,
            catalog: catalog,
          ),
          throwsArgumentError,
        );
      }

      await expectRejected(
        _opaqueWidgetSource(firstEventName: 'onUnlisted'),
        _opaqueCatalog(),
      );
      await expectRejected(
        _opaqueWidgetSource(localRootLookalike: true),
        _opaqueCatalog(),
      );
      await expectRejected(
        _opaqueWidgetSource(),
        _opaqueCatalog(flutterType: '$_opaqueProbeLibrary#DifferentAction'),
      );
      await expectRejected(
        _opaqueWidgetSource(
          includeDynamicCallback: true,
          firstEventExpression: 'dynamicCallback',
        ),
        _opaqueCatalog(),
      );
      await expectRejected(
        _opaqueWidgetSource(firstEventExpression: "'not a callback'"),
        _opaqueCatalog(),
      );
      await expectRejected(
        _opaqueWidgetSource(),
        _opaqueCatalog(ambiguous: true),
      );
    });

    test('Flutter keys do not affect opaque provenance or compiler output',
        () async {
      final baseline = await _OpaqueCompilerFixture.build();
      final keyed = await _OpaqueCompilerFixture.build(
        source: _opaqueWidgetSource(
          firstKey: 'UniqueKey()',
          secondKey: "const ValueKey('opaque-second')",
        ),
      );

      expect(
        _provenanceKey(keyed.discoveredSlots.first),
        _provenanceKey(baseline.discoveredSlots.first),
      );

      final baselineResult = MeasurementCompilerBoundary.produceBoundaryV1(
        baseline.input,
      );
      final keyedResult = MeasurementCompilerBoundary.produceBoundaryV1(
        keyed.input,
      );
      expect(
        baselineResult.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      expect(
        keyedResult.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      expect(keyedResult.documents, _documentsEqual(baselineResult.documents));
    });

    test('repeated opaque artifact identity produces distinct structural edges',
        () async {
      final fixture = await _OpaqueCompilerFixture.build();
      final result = MeasurementCompilerBoundary.produceBoundaryV1(
        fixture.input,
      );

      expect(
        result.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      final graph = result.exactArtifactGraph!;
      expect(
        graph.artifactIdentities
            .where((identity) => identity.artifactId.value == 'artifact.opaque')
            .toList(),
        hasLength(1),
      );
      final opaqueEdges = graph.occurrenceEdges
          .where((edge) => edge.artifactId.value == 'artifact.opaque')
          .toList();
      expect(opaqueEdges, hasLength(2));
      expect(
        opaqueEdges.map((edge) => edge.edgeToken.value).toSet(),
        {'edge.opaque.first', 'edge.opaque.second'},
      );

      final points = result.completeMeasurementManifest!.points;
      expect(points, hasLength(2));
      expect(
        points.map((point) => point.artifactOccurrenceEdgeToken.value).toSet(),
        {'edge.opaque.first', 'edge.opaque.second'},
      );
      expect(
        points.map((point) => point.sourceEventIdentity!.value).toSet(),
        {'onActivate'},
      );
      expect(
        points.map((point) => point.occurrenceId.hex).toSet(),
        hasLength(2),
      );
      final opaqueManifest = result.localMeasurementManifests.singleWhere(
        (manifest) => manifest.artifactId.value == 'artifact.opaque',
      );
      expect(opaqueManifest.points, hasLength(2));
    });

    test(
        'multiple opaque slots on one node produce distinct occurrences and '
        'generated references', () async {
      final fixture = await _OpaqueCompilerFixture.build(
        repeatedOpaqueArtifact: false,
        multipleSlotsOnFirstNode: true,
      );
      final result = MeasurementCompilerBoundary.produceBoundaryV1(
        fixture.input,
      );

      expect(
        result.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      final points = result.completeMeasurementManifest!.points;
      expect(points, hasLength(2));
      expect(
        points.map((point) => point.canonicalNodeToken.value).toSet(),
        {'node.opaque.first'},
      );
      expect(
        points.map((point) => point.sourceEventIdentity!.value).toSet(),
        {'onActivate', 'onDismiss'},
      );
      expect(
        points.map((point) => point.occurrenceId.hex).toSet(),
        hasLength(2),
      );

      final opaqueManifest = result.localMeasurementManifests.singleWhere(
        (manifest) => manifest.artifactId.value == 'artifact.opaque',
      );
      expect(opaqueManifest.generatedReferences, hasLength(2));
      expect(
        opaqueManifest.generatedReferences
            .map((reference) => reference.referenceId.value)
            .toSet(),
        hasLength(2),
      );
      expect(
        opaqueManifest.generatedReferences
            .map((reference) => reference.sourceEventIdentity.value)
            .toSet(),
        {'onActivate', 'onDismiss'},
      );
    });
  });
}

String _provenanceKey(MeasurementResolvedOpaqueCustomWidgetEvent slot) {
  final provenance = slot.declarationProvenance;
  return '${slot.sourceRootKind.name}\u0000${provenance.libraryUri}\u0000'
      '${provenance.className}\u0000${provenance.memberName}\u0000'
      '${provenance.sourceSelector.value}\u0000'
      '${slot.catalogWidgetWireId.value}'
      '\u0000${slot.catalogLibraryNamespace}';
}

Matcher _documentsEqual(Map<String, Uint8List> expected) => predicate(
      (value) {
        if (value is! Map<String, Uint8List>) return false;
        if (value.length != expected.length ||
            !value.keys.toSet().containsAll(expected.keys)) {
          return false;
        }
        return value.entries.every(
          (entry) => _sameBytes(expected[entry.key]!, entry.value),
        );
      },
      'matches the baseline compiler documents',
    );

bool _sameBytes(List<int> expected, List<int> actual) =>
    expected.length == actual.length &&
    expected.indexed.every((entry) => entry.$2 == actual[entry.$1]);

Catalog _opaqueCatalog({
  Iterable<String> eventNames = const ['onActivate'],
  String flutterType = _opaqueClassKey,
  bool ambiguous = false,
}) {
  final slots = eventNames.toList(growable: false);
  const library = WidgetLibrary.custom('example.opaque');
  WidgetEntry entry({
    required String widgetWireId,
    required int propertyStart,
  }) =>
      WidgetEntry(
        wireId: WireId(widgetWireId),
        name: 'OpaqueAction',
        library: library,
        category: WidgetCategory.action,
        description: 'Opaque action fixture.',
        flutterType: flutterType,
        childrenSlot: ChildrenSlot.none,
        properties: [
          for (var index = 0; index < slots.length; index++)
            PropertyEntry(
              wireId: WireId(
                'p${(propertyStart + index).toString().padLeft(4, '0')}',
              ),
              name: slots[index],
              type: PropertyType.event,
              description: 'Opaque event slot.',
            ),
          PropertyEntry(
            wireId: WireId(
              'p${(propertyStart + slots.length).toString().padLeft(4, '0')}',
            ),
            name: 'label',
            type: PropertyType.string,
            description: 'Opaque scalar property.',
          ),
        ],
      );

  return Catalog(
    schemaVersion: 1,
    generatedAt: '2026-08-11T00:00:00Z',
    libraries: const {},
    widgets: [
      entry(widgetWireId: 'w0001', propertyStart: 1),
      if (ambiguous) entry(widgetWireId: 'w0002', propertyStart: 101),
    ],
  );
}

Future<_ResolvedOpaqueOccurrences> _resolveOpaqueOccurrences(
  String source,
) async {
  final expression = await parseExpressionFromSourceForTest(
    source,
    rootPackage: 'apps_examples',
  );
  final root = expression as InstanceCreationExpression;
  final sourceRoot = root.constructorName.element?.enclosingElement;
  final childArgument = root.argumentList.arguments
      .whereType<NamedExpression>()
      .singleWhere((argument) => argument.name.label.name == 'child');
  final column = childArgument.expression as InstanceCreationExpression;
  final childrenArgument = column.argumentList.arguments
      .whereType<NamedExpression>()
      .singleWhere((argument) => argument.name.label.name == 'children');
  final children = childrenArgument.expression as ListLiteral;
  final occurrences = children.elements
      .whereType<InstanceCreationExpression>()
      .where(
        (occurrence) =>
            occurrence.constructorName.type.name.lexeme == 'OpaqueAction',
      )
      .toList(growable: false);

  if (sourceRoot is! InterfaceElement || occurrences.isEmpty) {
    throw StateError('Opaque fixture did not resolve its root and occurrences');
  }
  return _ResolvedOpaqueOccurrences(
    sourceRoot: sourceRoot,
    occurrences: occurrences,
  );
}

final class _ResolvedOpaqueOccurrences {
  const _ResolvedOpaqueOccurrences({
    required this.sourceRoot,
    required this.occurrences,
  });

  final InterfaceElement sourceRoot;
  final List<InstanceCreationExpression> occurrences;
}

String _opaqueWidgetSource({
  String rootAnnotation = 'PaywallSource',
  bool localRootLookalike = false,
  String firstEventName = 'onActivate',
  String firstEventExpression = '() {}',
  bool firstHasDismiss = false,
  String secondEventName = 'onActivate',
  String secondEventExpression = '() {}',
  bool includeSecond = true,
  bool namedConstructor = false,
  String? firstKey,
  String? secondKey,
  bool includeDynamicCallback = false,
}) {
  final constructorDeclaration =
      namedConstructor ? 'const OpaqueAction.named' : 'const OpaqueAction';
  final constructorCall =
      namedConstructor ? 'OpaqueAction.named' : 'OpaqueAction';
  final restageImport =
      localRootLookalike ? '' : "import 'package:restage/restage.dart';";
  final lookalikeDeclaration = localRootLookalike
      ? '''
class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}
'''
      : '';
  final firstKeyArgument = firstKey == null ? '' : 'key: $firstKey,';
  final secondKeyArgument = secondKey == null ? '' : 'key: $secondKey,';
  final firstDismissArgument = firstHasDismiss ? 'onDismiss: () {},' : '';
  final secondOccurrence = includeSecond
      ? '''
    $constructorCall(
      $secondKeyArgument
      label: 'Secondary',
      $secondEventName: $secondEventExpression,
    ),
'''
      : '';
  final dynamicCallback =
      includeDynamicCallback ? 'dynamic dynamicCallback = () {};' : '';

  return '''
import 'package:flutter/material.dart';
$restageImport
$lookalikeDeclaration
$dynamicCallback
@$rootAnnotation(id: 'opaque-source')
class OpaqueSourceRoot extends StatelessWidget {
  const OpaqueSourceRoot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class OpaqueAction extends StatelessWidget {
  $constructorDeclaration({
    super.key,
    this.label,
    this.onActivate,
    this.onDismiss,
    this.onUnlisted,
  });

  final String? label;
  final VoidCallback? onActivate;
  final VoidCallback? onDismiss;
  final VoidCallback? onUnlisted;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
        child: const Text('Private implementation'),
      );
}

Object x() => OpaqueSourceRoot(
  child: Column(
    children: [
      $constructorCall(
        $firstKeyArgument
        label: 'Primary',
        $firstEventName: $firstEventExpression,
        $firstDismissArgument
      ),
$secondOccurrence    ],
  ),
);
''';
}

final class _OpaqueCompilerFixture {
  const _OpaqueCompilerFixture._({
    required this.input,
    required this.discoveredSlots,
  });

  static Future<_OpaqueCompilerFixture> build({
    String? source,
    bool repeatedOpaqueArtifact = true,
    bool multipleSlotsOnFirstNode = false,
  }) async {
    final resolved = await _resolveOpaqueOccurrences(
      source ??
          _opaqueWidgetSource(
            includeSecond: repeatedOpaqueArtifact,
            firstHasDismiss: multipleSlotsOnFirstNode,
          ),
    );
    final catalog = _opaqueCatalog(
      eventNames: multipleSlotsOnFirstNode
          ? const ['onActivate', 'onDismiss']
          : const ['onActivate'],
    );
    final firstSlots = MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
      sourceRoot: resolved.sourceRoot,
      occurrence: resolved.occurrences.first,
      catalog: catalog,
    );
    final selectedSlots = <MeasurementResolvedOpaqueCustomWidgetEvent>[
      if (multipleSlotsOnFirstNode) ...firstSlots else firstSlots.single,
    ];
    final slotCodes = <CodeIdentityId>[
      for (var index = 0; index < selectedSlots.length; index++)
        CodeIdentityId('code.opaque.first'),
    ];
    if (repeatedOpaqueArtifact) {
      final secondSlots =
          MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
        sourceRoot: resolved.sourceRoot,
        occurrence: resolved.occurrences[1],
        catalog: catalog,
      );
      selectedSlots.add(secondSlots.single);
      slotCodes.add(CodeIdentityId('code.opaque.second'));
    }

    final target = TargetCoordinate(
      organizationId: OrganizationId(301),
      appId: ApplicationId(302),
      environmentTargetId: EnvironmentTargetId(303),
      namedEnvironmentId: NamedEnvironmentId(304),
      runtimePlane: RuntimePlane.sandbox,
    );
    final surfaceId = SurfaceId('surface.opaque');
    final rootArtifact = MeasurementArtifactInput(
      artifactId: ArtifactId('artifact.root'),
      artifactKind: ArtifactKindId('rfw.blob'),
      contentHash: CanonicalDigest('a' * 64),
      occurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.root'),
      localManifestId: MeasurementManifestId('manifest.root'),
    );
    final firstOpaqueArtifact = MeasurementArtifactInput(
      artifactId: ArtifactId('artifact.opaque'),
      artifactKind: ArtifactKindId('rfw.blob'),
      contentHash: CanonicalDigest('b' * 64),
      occurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.opaque.first'),
      parentOccurrenceEdgeToken: rootArtifact.occurrenceEdgeToken,
      localManifestId: MeasurementManifestId('manifest.opaque'),
    );
    final secondOpaqueArtifact = MeasurementArtifactInput(
      artifactId: ArtifactId('artifact.opaque'),
      artifactKind: ArtifactKindId('rfw.blob'),
      contentHash: CanonicalDigest('b' * 64),
      occurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.opaque.second'),
      parentOccurrenceEdgeToken: rootArtifact.occurrenceEdgeToken,
      localManifestId: MeasurementManifestId('manifest.opaque'),
    );

    final rootCode = CodeIdentityId('code.root');
    final ledger = CodeIdentityLedgerV1(
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: target,
        surfaceId: surfaceId,
      ),
      bindings: [
        CodeIdentityBindingV1(
          codeIdentityId: rootCode,
          canonicalNodeTokenId: NodeTokenId('node.root'),
        ),
        CodeIdentityBindingV1(
          codeIdentityId: CodeIdentityId('code.opaque.first'),
          canonicalNodeTokenId: NodeTokenId('node.opaque.first'),
        ),
        if (repeatedOpaqueArtifact)
          CodeIdentityBindingV1(
            codeIdentityId: CodeIdentityId('code.opaque.second'),
            canonicalNodeTokenId: NodeTokenId('node.opaque.second'),
          ),
      ],
    );
    final events = <MeasurementCompilerEventInput>[
      for (var index = 0; index < selectedSlots.length; index++)
        MeasurementCompilerEventInput(
          nodeCodeIdentityId: slotCodes[index],
          resolvedEvent: selectedSlots[index],
          lineageId: PointLineageId('lineage.opaque.$index'),
          generatedReferenceId: GeneratedReferenceId('reference.opaque.$index'),
          dartSymbol: GeneratedDartSymbol('opaqueSlot$index'),
          displayMetadataRef: DisplayMetadataRef('display.opaque.$index'),
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
        ),
    ];
    final input = MeasurementCompilerBoundaryInput(
      target: target,
      surfaceId: surfaceId,
      surfaceRevisionId: SurfaceRevisionId('surface.opaque.v2'),
      revisionOrdinal: 2,
      analyticsSurfaceKey: AnalyticsSurfaceKey('opaque-fixture'),
      deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
      minimumMeasurementClient: 1,
      completeManifestId: MeasurementManifestId('manifest.opaque.complete'),
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.opaque.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId('budget.opaque.v1'),
      artifacts: [
        rootArtifact,
        firstOpaqueArtifact,
        if (repeatedOpaqueArtifact) secondOpaqueArtifact,
      ],
      codeIdentityLedger: ledger,
      nodes: [
        MeasurementCompilerNodeInput(
          codeIdentityId: rootCode,
          artifactOccurrenceEdgeToken: rootArtifact.occurrenceEdgeToken,
        ),
        MeasurementCompilerNodeInput(
          codeIdentityId: CodeIdentityId('code.opaque.first'),
          artifactOccurrenceEdgeToken: firstOpaqueArtifact.occurrenceEdgeToken,
          parentCodeIdentityId: rootCode,
        ),
        if (repeatedOpaqueArtifact)
          MeasurementCompilerNodeInput(
            codeIdentityId: CodeIdentityId('code.opaque.second'),
            artifactOccurrenceEdgeToken:
                secondOpaqueArtifact.occurrenceEdgeToken,
            parentCodeIdentityId: rootCode,
          ),
      ],
      events: events,
      priorActiveLedger: PriorActiveLineageLedgerV1(
        surfaceId: surfaceId,
        surfaceRevisionId: SurfaceRevisionId('surface.opaque.v1'),
        endpoints: const [],
      ),
      lineageTransitions: [
        for (var index = 0; index < events.length; index++)
          MeasurementLineageTransitionDraft(
            transitionId: LineageTransitionId('transition.opaque.$index'),
            operation: LineageOperation.create,
            authority: LineageTransitionAuthority.exactToken,
            next: [
              MeasurementCurrentEndpointClaim(
                codeIdentityId: slotCodes[index],
                lineageId: events[index].lineageId,
                sourceEventIdentity:
                    events[index].resolvedEvent.sourceEventIdentity,
              ),
            ],
          ),
      ],
    );
    return _OpaqueCompilerFixture._(
      input: input,
      discoveredSlots: List.unmodifiable(selectedSlots),
    );
  }

  final MeasurementCompilerBoundaryInput input;
  final List<MeasurementResolvedOpaqueCustomWidgetEvent> discoveredSlots;
}
