import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('MeasurementSourceDiscovery', () {
    test(
        'discovers resolved ordinary Flutter slots in ScreenSource and '
        'PaywallSource roots', () async {
      final screen = await _resolveFixture(
        _ordinarySource(),
      );
      final paywall = await _resolveFixture(
        _ordinarySource(
          annotation: 'PaywallSource',
          className: 'Upgrade',
          sourceId: 'upgrade',
        ),
        assetPath: 'lib/paywalls/upgrade.dart',
      );

      final screenDiscovery = _discover(
        screen,
        authority: MeasurementSourceAuthority.screen,
      );
      final paywallDiscovery = _discover(
        paywall,
        authority: MeasurementSourceAuthority.paywall,
      );

      for (final discovery in [screenDiscovery, paywallDiscovery]) {
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
          reason: discovery.rejectionReason,
        );
        expect(discovery.events, hasLength(2));
        expect(
          discovery.events.map(
            (event) => event.resolvedEvent.declarationProvenance.memberName,
          ),
          everyElement('onPressed'),
        );
        expect(discovery.nodes, hasLength(5));
      }
      expect(
        screenDiscovery.nodes.first.sourceProvenance.authority,
        MeasurementSourceAuthority.screen,
      );
      expect(
        paywallDiscovery.nodes.first.sourceProvenance.authority,
        MeasurementSourceAuthority.paywall,
      );
    });

    test(
        'keys, copy, source layout, and argument traversal order do not '
        'author ordinary event identity', () async {
      final baseline = _discover(
        await _resolveFixture(_ordinarySource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        baseline.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: baseline.rejectionReason,
      );

      final variants = [
        _ordinarySource(key: "const ValueKey('renew')"),
        _ordinarySource(key: 'UniqueKey()'),
        _ordinarySource(copy: 'Start your trial'),
        '\n\n\n${_ordinarySource()}',
        _ordinarySource(eventBeforeChild: false),
      ];

      for (final source in variants) {
        final discovery = _discover(
          await _resolveFixture(source),
          authority: MeasurementSourceAuthority.screen,
        );
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
        );
        expect(_eventKeys(discovery), orderedEquals(_eventKeys(baseline)));
      }
    });

    test(
        'keeps repeated ordinary occurrences distinct through static '
        'occurrence edges', () async {
      final discovery = _discover(
        await _resolveFixture(_ordinarySource(copy: 'Same copy')),
        authority: MeasurementSourceAuthority.screen,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      final eventKeys = _eventKeys(discovery);
      expect(eventKeys, hasLength(2));
      expect(eventKeys.first, isNot(eventKeys.last));
      expect(
        discovery.events.map((event) => event.node.structuralOccurrenceKey),
        containsAll([
          contains('children[0]'),
          contains('children[1]'),
        ]),
      );
    });

    test(
        'keeps each supported callback slot on one canonical node as a '
        'distinct occurrence and generated reference', () async {
      final discovery = _discover(
        await _resolveFixture(_multiSlotSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      expect(discovery.events, hasLength(2));
      expect(
        discovery.events
            .map((event) => event.node.structuralOccurrenceKey)
            .toSet(),
        hasLength(1),
      );
      expect(
        discovery.events
            .map((event) => event.resolvedEvent.sourceEventIdentity.value)
            .toSet(),
        {'onTap', 'onDoubleTap'},
      );

      final codeIdentityId = CodeIdentityId('code.source-discovery.multi');
      final boundaryInput = _boundaryInputFor(
        discovery.events,
        codeIdentityId: codeIdentityId,
      );
      final result = MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: boundaryInput,
          discovery: discovery,
          nodeBindings: [
            MeasurementDiscoveredNodeBinding(
              structuralOccurrenceKey:
                  discovery.nodes.single.structuralOccurrenceKey,
              codeIdentityId: codeIdentityId,
            ),
          ],
        ),
      );

      expect(
        result.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      final manifest = CompleteMeasurementManifestV1.fromCanonicalBytes(
        result.documents['completeMeasurementManifest']!,
      );
      final points = manifest.points;
      expect(points, hasLength(2));
      expect(points.map((point) => point.occurrenceId).toSet(), hasLength(2));
      expect(
        points.map((point) => point.sourceEventIdentity?.value).toSet(),
        {'onTap', 'onDoubleTap'},
      );
      expect(points.map((point) => point.lineageId).toSet(), hasLength(2));
    });

    test(
        'discovers each statically inlined custom-widget body at its exact '
        'call-site occurrence', () async {
      final fixture = await _resolveFixture(_inlinedCustomSource());
      final actionButton = fixture.classNamed('ActionButton');
      final catalog = _catalogForExpressions([
        fixture.rootExpression,
        fixture.buildExpressionFor(actionButton),
      ]);
      final classification = await classifyReferencedCustomWidgets(
        rootExpressions: [fixture.rootExpression],
        catalog: catalog,
        astNodeFor: fixture.astNodeFor,
      );
      final actionButtonKey = _classIdentity(actionButton);
      expect(classification.blueprints, contains(actionButtonKey));

      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: catalog,
        inlinedCustomWidgetBlueprints: classification.blueprints,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      expect(discovery.events, hasLength(2));
      expect(
        discovery.events
            .map((event) => event.node.structuralOccurrenceKey)
            .toSet(),
        hasLength(2),
      );
      expect(
        discovery.events
            .map((event) => event.node.inlinedCustomWidgetIdentities)
            .expand((identities) => identities),
        everyElement(actionButtonKey),
      );
    });

    test(
        'retains resolved outer bindings through nested static custom-widget '
        'inlining', () async {
      final fixture = await _resolveFixture(_nestedInlinedCustomSource());
      final outer = fixture.classNamed('OuterAction');
      final inner = fixture.classNamed('InnerAction');
      final catalog = _catalogForExpressions([
        fixture.rootExpression,
        fixture.buildExpressionFor(outer),
        fixture.buildExpressionFor(inner),
      ]);
      final classification = await classifyReferencedCustomWidgets(
        rootExpressions: [fixture.rootExpression],
        catalog: catalog,
        astNodeFor: fixture.astNodeFor,
      );

      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: catalog,
        inlinedCustomWidgetBlueprints: classification.blueprints,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, hasLength(2));
      expect(
        discovery.events
            .map((event) => event.node.inlinedCustomWidgetIdentities),
        everyElement(
          orderedEquals([
            _classIdentity(outer),
            _classIdentity(inner),
          ]),
        ),
      );
      expect(
        discovery.events
            .map((event) => event.node.structuralOccurrenceKey)
            .toSet(),
        hasLength(2),
      );
    });

    test('follows the existing inlined local and helper element bindings',
        () async {
      final fixture = await _resolveFixture(_inlinedHelperSource());
      final actionButton = fixture.classNamed('ActionButton');
      final catalog = _catalogForAstNodes([
        fixture.rootExpression,
        fixture.methodDeclarationFor(actionButton, 'build'),
        fixture.methodDeclarationFor(actionButton, '_button'),
      ]);
      final classification = await classifyReferencedCustomWidgets(
        rootExpressions: [fixture.rootExpression],
        catalog: catalog,
        astNodeFor: fixture.astNodeFor,
      );

      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: catalog,
        inlinedCustomWidgetBlueprints: classification.blueprints,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, hasLength(1));
      expect(discovery.nodes, hasLength(2));
      expect(
        discovery.events.single.node.structuralOccurrenceKey,
        contains('helper:'),
      );
    });

    test(
        'discovers exact registered opaque catalog slots without traversing '
        'the private implementation', () async {
      final registeredFixture = await _resolveFixture(
        _opaqueCustomSource(className: 'OpaqueAction'),
      );
      final opaqueClass = registeredFixture.classNamed('OpaqueAction');
      final registeredDiscovery = _discover(
        registeredFixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogWithRegisteredOpaqueCustom(
          _catalogFor(registeredFixture.rootExpression),
          opaqueClass,
        ),
      );
      expect(
        registeredDiscovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: registeredDiscovery.rejectionReason,
      );
      expect(
        registeredDiscovery.events
            .map((event) => event.resolvedEvent.sourceEventIdentity.value),
        ['onActivate'],
      );
      expect(registeredDiscovery.nodes, hasLength(1));
      expect(
        registeredDiscovery.events.single.resolvedEvent,
        isA<MeasurementResolvedOpaqueCustomWidgetEvent>(),
      );
      expect(
        registeredDiscovery.events
            .map((event) => event.resolvedEvent.sourceEventIdentity.value),
        isNot(contains('onPressed')),
        reason: 'the opaque widget private body is outside source discovery',
      );

      final codeIdentityId = CodeIdentityId('code.source-discovery.opaque');
      final result = MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: _boundaryInputFor(
            registeredDiscovery.events,
            codeIdentityId: codeIdentityId,
          ),
          discovery: registeredDiscovery,
          nodeBindings: [
            MeasurementDiscoveredNodeBinding(
              structuralOccurrenceKey:
                  registeredDiscovery.nodes.single.structuralOccurrenceKey,
              codeIdentityId: codeIdentityId,
            ),
          ],
        ),
      );
      expect(
        result.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      final manifest = CompleteMeasurementManifestV1.fromCanonicalBytes(
        result.documents['completeMeasurementManifest']!,
      );
      expect(manifest.points, hasLength(1));
      expect(manifest.points.single.sourceEventIdentity?.value, 'onActivate');

      final unregisteredDiscovery = _discover(
        await _resolveFixture(_opaqueCustomSource(className: 'Unregistered')),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        unregisteredDiscovery.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
      expect(unregisteredDiscovery.events, isEmpty);
    });

    test(
        'FlowSource closes already-resolved static screen artifacts without '
        'inventing a widget body in buildFlow', () async {
      final fixture = await _resolveFixture(_flowAndScreenSource());
      final screen = fixture.classNamed('FlowScreen');
      final flow = fixture.classNamed('WelcomeFlow');
      final screenDiscovery = MeasurementSourceDiscovery.discover(
        MeasurementSourceDiscoveryInput(
          authority: MeasurementSourceAuthority.screen,
          sourceClass: screen,
          rootExpression: fixture.buildExpressionFor(screen),
          catalog: _catalogFor(fixture.buildExpressionFor(screen)),
        ),
      );
      final flowClosure = MeasurementSourceDiscovery.closeFlowSourceV1(
        MeasurementFlowSourceClosureInput(
          flowSourceClass: flow,
          staticArtifactDiscoveries: [screenDiscovery],
        ),
      );

      expect(
        flowClosure.disposition,
        MeasurementFlowSourceClosureDisposition.accepted,
      );
      expect(
        flowClosure.events.map(_eventKey),
        orderedEquals(screenDiscovery.events.map(_eventKey)),
      );
    });

    test('fails closed for local source/widget/custom-marker lookalikes',
        () async {
      final fakeSource = _discover(
        await _resolveFixture(_fakeSourceAnnotation()),
        authority: MeasurementSourceAuthority.screen,
      );
      final fakeWidget = _discover(
        await _resolveFixture(_fakeFlutterWidget()),
        authority: MeasurementSourceAuthority.screen,
      );
      final fakeCustom = _discover(
        await _resolveFixture(_fakeCustomWidget()),
        authority: MeasurementSourceAuthority.screen,
      );

      for (final discovery in [fakeSource, fakeWidget, fakeCustom]) {
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.rejected,
        );
        expect(discovery.nodes, isEmpty);
        expect(discovery.events, isEmpty);
      }
    });

    test('fails closed for dynamic and unresolved widget constructs', () async {
      final dynamicDiscovery = _discover(
        await _resolveFixture(_dynamicWidgetSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      final unresolvedDiscovery = _discover(
        await _resolveFixture(_unresolvedWidgetSource()),
        authority: MeasurementSourceAuthority.screen,
      );

      for (final discovery in [dynamicDiscovery, unresolvedDiscovery]) {
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.rejected,
        );
        expect(discovery.events, isEmpty);
      }
    });

    test(
        'validates discovered nodes and slots before delegating to the '
        'unchanged production boundary', () async {
      final discovery = _discover(
        await _resolveFixture(_singleButtonSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      final codeIdentityId = CodeIdentityId('code.source-discovery.button');
      final boundaryInput = _boundaryInputFor(
        [discovery.events.single],
        codeIdentityId: codeIdentityId,
      );

      final direct = MeasurementCompilerBoundary.produceBoundaryV1(
        boundaryInput,
      );
      final bridged = MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: boundaryInput,
          discovery: discovery,
          nodeBindings: [
            MeasurementDiscoveredNodeBinding(
              structuralOccurrenceKey:
                  discovery.nodes.single.structuralOccurrenceKey,
              codeIdentityId: codeIdentityId,
            ),
          ],
        ),
      );

      expect(
        direct.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      expect(
        bridged.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      expect(bridged.productionEntrypoint, direct.productionEntrypoint);
      expect(bridged.documents.keys, orderedEquals(direct.documents.keys));
      for (final key in direct.documents.keys) {
        expect(bridged.documents[key], orderedEquals(direct.documents[key]!));
      }

      final missingBinding =
          MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: boundaryInput,
          discovery: discovery,
          nodeBindings: const [],
        ),
      );
      expect(
        missingBinding.disposition,
        MeasurementCompilerBoundaryDisposition.rejected,
      );
      expect(missingBinding.documents, isEmpty);
    });

    test('prohibited discovered events never receive an emission marker',
        () async {
      final discovery = _discover(
        await _resolveFixture(_singleButtonSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      final discovered = discovery.events.single;
      final codeIdentityId = CodeIdentityId('code.source-prohibited');
      final lineageId = PointLineageId('lineage.source-prohibited');
      final generatedReferenceId = GeneratedReferenceId(
        'reference.source-prohibited',
      );
      final edge = ArtifactOccurrenceEdgeToken('edge.source-prohibited');
      final routePlan = MeasurementPublicationRoutePlanV1(
        surfaceId: SurfaceId('surface.source-prohibited'),
        analyticsSurfaceKey: AnalyticsSurfaceKey('source-prohibited'),
        deliverySurfaceType: DeliverySurfaceTypeId('general'),
        minimumMeasurementClient: 1,
        completeManifestId: MeasurementManifestId(
          'manifest.source-prohibited',
        ),
        privacyPolicyRevisionId: AuthorityRevisionId(
          'privacy.source-prohibited',
        ),
        collectionBudgetRevisionId: AuthorityRevisionId(
          'budget.source-prohibited',
        ),
        artifacts: [
          MeasurementPublicationRouteArtifactV1(
            artifactId: ArtifactId('artifact.source-prohibited'),
            artifactKind: ArtifactKindId('rfw.blob'),
            occurrenceEdgeToken: edge,
            localManifestId: MeasurementManifestId(
              'manifest.source-prohibited.local',
            ),
          ),
        ],
        codeIdentityBindings: [
          CodeIdentityBindingV1(
            codeIdentityId: codeIdentityId,
            canonicalNodeTokenId: NodeTokenId('node.source-prohibited'),
          ),
        ],
        nodes: [
          MeasurementPublicationDraftNodeV1(
            codeIdentityId: codeIdentityId,
            artifactOccurrenceEdgeToken: edge,
          ),
        ],
        events: [
          MeasurementPublicationDraftEventV1(
            nodeCodeIdentityId: codeIdentityId,
            sourceEventIdentity: discovered.resolvedEvent.sourceEventIdentity,
            lineageId: lineageId,
            generatedReferenceId: generatedReferenceId,
            dartSymbol: GeneratedDartSymbol('sourceProhibited'),
            displayMetadataRef: DisplayMetadataRef(
              'display.source-prohibited',
            ),
            normalizedInteractionKind: NormalizedInteractionKind.activate,
            privacyClass: MeasurementPrivacyClass.prohibited,
            semanticValueClass: SemanticValueClass.activityOnly,
            collectionClass: MeasurementCollectionClass.prohibited,
          ),
        ],
        routeSeeds: const [],
        lineageIntents: [
          MeasurementPublicationLineageIntentV1(
            transitionId: LineageTransitionId(
              'transition.source-prohibited',
            ),
            operation: LineageOperation.create,
            authority: LineageTransitionAuthority.exactToken,
            next: [
              MeasurementPublicationCurrentEndpointIntentV1(
                generatedReferenceId: generatedReferenceId,
                lineageId: lineageId,
              ),
            ],
          ),
        ],
      );

      final emission = MeasurementRouteEmissionPlan.fromDiscovery(
        discovery: discovery,
        routePlan: routePlan,
        codeIdentityByStructuralOccurrenceKey: {
          discovered.node.structuralOccurrenceKey: codeIdentityId,
        },
      );

      expect(emission.markerFor(discovered.sourceExpression), isNull);
      expect(routePlan.routes, isEmpty);
    });
  });
}

MeasurementSourceDiscoveryResult _discover(
  _ResolvedFixture fixture, {
  required MeasurementSourceAuthority authority,
  Catalog? catalog,
  Map<String, CustomWidgetBlueprint> inlinedCustomWidgetBlueprints = const {},
}) =>
    MeasurementSourceDiscovery.discover(
      MeasurementSourceDiscoveryInput(
        authority: authority,
        sourceClass: fixture.sourceClass,
        rootExpression: fixture.rootExpression,
        catalog: catalog ?? _catalogFor(fixture.rootExpression),
        inlinedCustomWidgetBlueprints: inlinedCustomWidgetBlueprints,
      ),
    );

List<String> _eventKeys(MeasurementSourceDiscoveryResult discovery) =>
    discovery.events.map(_eventKey).toList();

String _eventKey(MeasurementDiscoveredEvent event) =>
    '${event.node.structuralOccurrenceKey}|'
    '${event.resolvedEvent.resolvedSemanticIdentity}';

Catalog _catalogFor(Expression rootExpression) {
  return _catalogForExpressions([rootExpression]);
}

Catalog _catalogForExpressions(Iterable<Expression> rootExpressions) {
  return _catalogForAstNodes(rootExpressions);
}

Catalog _catalogForAstNodes(Iterable<AstNode> roots) {
  final collector = _FlutterCreationCollector();
  roots.forEach(collector.collect);
  return catalogWith([
    for (final widgetEntry in collector.entries.values)
      entry(
        name: widgetEntry.$1.name!,
        flutterType: widgetEntry.$2,
        properties: _eventPropertiesFor(widgetEntry.$1.name),
      ),
  ]);
}

Catalog _catalogWithRegisteredOpaqueCustom(
  Catalog base,
  ClassElement customClass,
) {
  const opaqueLibrary = WidgetLibrary.custom('fixture.opaque');
  return Catalog(
    schemaVersion: base.schemaVersion,
    generatedAt: base.generatedAt,
    libraries: {
      ...base.libraries,
      opaqueLibrary: const LibraryInfo(version: '0.1.0'),
    },
    widgets: [
      ...base.widgets,
      entry(
        name: customClass.name!,
        flutterType: _classIdentity(customClass),
        library: opaqueLibrary,
        properties: [prop('onActivate', PropertyType.event)],
      ),
    ],
  );
}

List<PropertyEntry> _eventPropertiesFor(String? className) {
  switch (className) {
    case 'ElevatedButton':
      return [prop('onPressed', PropertyType.event)];
    case 'GestureDetector':
      return [
        prop('onTap', PropertyType.event),
        prop('onDoubleTap', PropertyType.event),
      ];
    default:
      return const [];
  }
}

final class _FlutterCreationCollector extends RecursiveAstVisitor<void> {
  final Map<String, (InterfaceElement, String)> entries = {};

  void collect(AstNode node) => node.accept(this);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.type.element;
    if (element is InterfaceElement &&
        element.library.identifier.startsWith('package:flutter/')) {
      final name = element.name;
      if (name != null && name.isNotEmpty) {
        final constructorName = node.constructorName.name?.name;
        final suffix = constructorName == null || constructorName.isEmpty
            ? ''
            : '.$constructorName';
        final flutterType = '${element.library.identifier}#$name$suffix';
        entries[flutterType] = (element, flutterType);
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

Future<_ResolvedFixture> _resolveFixture(
  String source, {
  String assetPath = 'lib/onboarding/screens/probe.dart',
}) async {
  final assetId = AssetId('apps_examples', assetPath);
  late final LibraryElement library;
  late final ResolvedLibraryResult resolved;
  await resolveSources(
    {assetId.toString(): source},
    (resolver) async {
      library = await resolver.libraryFor(assetId);
      final result = await library.session.getResolvedLibraryByElement(library);
      if (result is! ResolvedLibraryResult) {
        throw StateError('Fixture did not resolve.');
      }
      resolved = result;
    },
    resolverFor: assetId.toString(),
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
  return _ResolvedFixture(library: library, resolved: resolved);
}

final class _ResolvedFixture {
  const _ResolvedFixture({required this.library, required this.resolved});

  final LibraryElement library;
  final ResolvedLibraryResult resolved;

  ClassElement get sourceClass => classNamed(
        library.classes.map((element) => element.name).contains('Welcome')
            ? 'Welcome'
            : library.classes.map((element) => element.name).contains('Upgrade')
                ? 'Upgrade'
                : library.classes
                        .map((element) => element.name)
                        .contains('DynamicScreen')
                    ? 'DynamicScreen'
                    : library.classes
                            .map((element) => element.name)
                            .contains('UnresolvedScreen')
                        ? 'UnresolvedScreen'
                        : library.classes
                                .map((element) => element.name)
                                .contains('FakeSource')
                            ? 'FakeSource'
                            : library.classes
                                    .map((element) => element.name)
                                    .contains('FakeWidget')
                                ? 'FakeWidget'
                                : library.classes
                                        .map((element) => element.name)
                                        .contains('FakeCustomScreen')
                                    ? 'FakeCustomScreen'
                                    : library.classes.single.name!,
      );

  Expression get rootExpression => buildExpressionFor(sourceClass);

  ClassElement classNamed(String name) =>
      library.classes.singleWhere((element) => element.name == name);

  Expression buildExpressionFor(ClassElement element) {
    return methodExpressionFor(element, 'build');
  }

  Expression methodExpressionFor(ClassElement element, String methodName) {
    final node = methodDeclarationFor(element, methodName);
    final body = node.body;
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody && body.block.statements.isNotEmpty) {
      final statement = body.block.statements.last;
      if (statement is ReturnStatement && statement.expression != null) {
        return statement.expression!;
      }
    }
    throw StateError('Fixture $methodName() did not return one expression.');
  }

  MethodDeclaration methodDeclarationFor(
    ClassElement element,
    String methodName,
  ) {
    final build = element.methods.firstWhere(
      (method) =>
          method.name == methodName && method.enclosingElement == element,
    );
    final node = resolved.getFragmentDeclaration(build.firstFragment)?.node;
    if (node is! MethodDeclaration) {
      throw StateError('Could not resolve ${element.name}.$methodName.');
    }
    return node;
  }

  Future<AstNode?> astNodeFor(Fragment fragment) async =>
      resolved.getFragmentDeclaration(fragment)?.node;
}

String _classIdentity(ClassElement element) =>
    '${element.library.identifier}#${element.name}';

MeasurementCompilerBoundaryInput _boundaryInputFor(
  Iterable<MeasurementDiscoveredEvent> events, {
  required CodeIdentityId codeIdentityId,
}) {
  final discoveredEvents = events.toList(growable: false);
  String eventSuffix(MeasurementDiscoveredEvent event) =>
      _testIdentifierSuffix(event.resolvedEvent.sourceEventIdentity.value);
  if (discoveredEvents.isEmpty) {
    throw ArgumentError.value(events, 'events', 'must not be empty');
  }
  final target = TargetCoordinate(
    organizationId: OrganizationId(1),
    appId: ApplicationId(2),
    environmentTargetId: EnvironmentTargetId(3),
    namedEnvironmentId: NamedEnvironmentId(4),
    runtimePlane: RuntimePlane.sandbox,
  );
  final surfaceId = SurfaceId('surface.source-discovery');
  final revisionId = SurfaceRevisionId('surface.source-discovery.v2');
  final artifact = MeasurementArtifactInput(
    artifactId: ArtifactId('artifact.source-discovery'),
    artifactKind: ArtifactKindId('rfw.blob'),
    contentHash: CanonicalDigest('a' * 64),
    occurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.source-discovery'),
    localManifestId: MeasurementManifestId('manifest.source-discovery.local'),
  );
  return MeasurementCompilerBoundaryInput(
    target: target,
    surfaceId: surfaceId,
    surfaceRevisionId: revisionId,
    revisionOrdinal: 2,
    analyticsSurfaceKey: AnalyticsSurfaceKey('source-discovery'),
    deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
    minimumMeasurementClient: 1,
    completeManifestId: MeasurementManifestId('manifest.source-discovery'),
    privacyPolicyRevisionId: AuthorityRevisionId('privacy.source-discovery'),
    collectionBudgetRevisionId: AuthorityRevisionId('budget.source-discovery'),
    artifacts: [artifact],
    codeIdentityLedger: CodeIdentityLedgerV1(
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: target,
        surfaceId: surfaceId,
      ),
      bindings: [
        CodeIdentityBindingV1(
          codeIdentityId: codeIdentityId,
          canonicalNodeTokenId: NodeTokenId('node.source-discovery'),
        ),
      ],
    ),
    nodes: [
      MeasurementCompilerNodeInput(
        codeIdentityId: codeIdentityId,
        artifactOccurrenceEdgeToken: artifact.occurrenceEdgeToken,
      ),
    ],
    events: [
      for (final event in discoveredEvents)
        MeasurementCompilerEventInput(
          nodeCodeIdentityId: codeIdentityId,
          resolvedEvent: event.resolvedEvent,
          lineageId: PointLineageId(
            'lineage.source-discovery.'
            '${eventSuffix(event)}',
          ),
          generatedReferenceId: GeneratedReferenceId(
            'reference.source-discovery.'
            '${eventSuffix(event)}',
          ),
          dartSymbol: GeneratedDartSymbol(
            'sourceDiscovery'
            '${event.resolvedEvent.declarationProvenance.memberName}',
          ),
          displayMetadataRef: DisplayMetadataRef(
            'display.source-discovery.'
            '${eventSuffix(event)}',
          ),
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
        ),
    ],
    priorActiveLedger: PriorActiveLineageLedgerV1(
      surfaceId: surfaceId,
      surfaceRevisionId: SurfaceRevisionId('surface.source-discovery.v1'),
      endpoints: const [],
    ),
    lineageTransitions: [
      for (final event in discoveredEvents)
        MeasurementLineageTransitionDraft(
          transitionId: LineageTransitionId(
            'transition.source-discovery.'
            '${eventSuffix(event)}',
          ),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          next: [
            MeasurementCurrentEndpointClaim(
              codeIdentityId: codeIdentityId,
              lineageId: PointLineageId(
                'lineage.source-discovery.'
                '${eventSuffix(event)}',
              ),
              sourceEventIdentity: event.resolvedEvent.sourceEventIdentity,
            ),
          ],
        ),
    ],
  );
}

String _testIdentifierSuffix(String sourceEventIdentity) =>
    sourceEventIdentity.toLowerCase();

String _ordinarySource({
  String annotation = 'ScreenSource',
  String className = 'Welcome',
  String sourceId = 'welcome',
  String? key,
  String copy = 'Subscribe',
  bool eventBeforeChild = true,
}) {
  final firstArgs = eventBeforeChild
      ? '''
          ${key == null ? '' : 'key: $key,'}
          onPressed: () {},
          child: Text('$copy'),
        '''
      : '''
          child: Text('$copy'),
          ${key == null ? '' : 'key: $key,'}
          onPressed: () {},
        ''';
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@$annotation(id: '$sourceId')
final class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ElevatedButton(
            $firstArgs
          ),
          ElevatedButton(
            onPressed: () {},
            child: Text('$copy'),
          ),
        ],
      );
}
''';
}

String _singleButtonSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'single')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
      );
}
''';

String _multiSlotSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'multi_slot')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {},
        onDoubleTap: () {},
      );
}
''';

String _inlinedCustomSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onActivate,
        child: const Text('Activate'),
      );
}

@ScreenSource(id: 'inline')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ActionButton(onActivate: () {}),
          ActionButton(onActivate: () {}),
        ],
      );
}
''';

String _nestedInlinedCustomSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class InnerAction extends StatelessWidget {
  const InnerAction({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onActivate,
        child: const Text('Activate'),
      );
}

@RestageWidget()
final class OuterAction extends StatelessWidget {
  const OuterAction({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => InnerAction(onActivate: onActivate);
}

@ScreenSource(id: 'nested_inline')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          OuterAction(onActivate: () {}),
          OuterAction(onActivate: () {}),
        ],
      );
}
''';

String _inlinedHelperSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final label = const Text('Activate');
    return _button(label);
  }

  Widget _button(Widget child) => ElevatedButton(
        onPressed: onActivate,
        child: child,
      );
}

@ScreenSource(id: 'inline_helper')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => ActionButton(onActivate: () {});
}
''';

String _opaqueCustomSource({required String className}) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class $className extends StatelessWidget {
  const $className({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onActivate,
        child: const Text('Private implementation'),
      );
}

@ScreenSource(id: 'opaque_boundary')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => $className(onActivate: () {});
}
''';

String _flowAndScreenSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'flow_screen')
final class FlowScreen extends StatelessWidget {
  const FlowScreen({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
        child: const Text('Continue'),
      );
}

@FlowSource(id: 'welcome_flow')
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() => throw UnimplementedError();
}
''';

String _fakeSourceAnnotation() => '''
import 'package:flutter/material.dart';

class ScreenSource {
  const ScreenSource({required this.id});
  final String id;
}

@ScreenSource(id: 'fake')
final class FakeSource extends StatelessWidget {
  const FakeSource({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
        child: const Text('Continue'),
      );
}
''';

String _fakeFlutterWidget() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

class ElevatedButton extends Widget {
  const ElevatedButton({this.onPressed});

  final VoidCallback? onPressed;
}

@ScreenSource(id: 'fake_widget')
final class FakeWidget extends StatelessWidget {
  const FakeWidget({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: () {});
}
''';

String _fakeCustomWidget() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart' hide RestageWidget;

class RestageWidget {
  const RestageWidget();
}

@RestageWidget()
final class LocalAction extends StatelessWidget {
  const LocalAction({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
        child: const Text('Activate'),
      );
}

@ScreenSource(id: 'fake_custom')
final class FakeCustomScreen extends StatelessWidget {
  const FakeCustomScreen({super.key});

  @override
  Widget build(BuildContext context) => const LocalAction();
}
''';

String _dynamicWidgetSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'dynamic')
final class DynamicScreen extends StatelessWidget {
  const DynamicScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
''';

String _unresolvedWidgetSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'unresolved')
final class UnresolvedScreen extends StatelessWidget {
  const UnresolvedScreen({super.key});

  @override
  Widget build(BuildContext context) => MissingButton(onPressed: () {});
}
''';
