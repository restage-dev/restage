import 'dart:typed_data';

import 'package:restage_codegen/src/measurement/measurement_rfw_route_composer.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

void main() {
  test(
    'wraps only the constructor that directly owns an admitted event',
    () {
      final routePlan = _routePlan(const ['reference.presentation.owner']);
      final source = _library(
        fmt.ConstructorCall(
          'Container',
          <String, Object?>{
            'child': fmt.ConstructorCall(
              'Button',
              <String, Object?>{
                'onPressed': _markedEvent('reference.presentation.owner'),
              },
            ),
          },
        ),
      );

      final composed = _compose(source, routePlan);
      final root = composed.widgets.single.root as fmt.ConstructorCall;
      final wrapper = root.arguments['child']! as fmt.ConstructorCall;

      expect(root.name, 'Container');
      expect(wrapper.name, 'MeasurementPresented');
      final child = wrapper.arguments['child']! as fmt.ConstructorCall;
      expect(child.name, 'Button');
      expect(
        wrapper.arguments['carriers'],
        orderedEquals([routePlan.routes.single.carrier]),
      );
      expect(
        wrapper.arguments['pointTokens'],
        orderedEquals([_compactToken(routePlan.routes.single.carrier)]),
      );
      expect(
        composed.imports.where(
          (entry) => entry.name.parts.join('.') == 'restage.measurement',
        ),
        hasLength(1),
      );
    },
  );

  test('keeps every direct event route on the same exact owner', () {
    final routePlan = _routePlan(const [
      'reference.presentation.tap',
      'reference.presentation.double-tap',
    ]);
    final source = _library(
      fmt.ConstructorCall(
        'GestureDetector',
        <String, Object?>{
          'onTap': _markedEvent('reference.presentation.tap'),
          'onDoubleTap': _markedEvent('reference.presentation.double-tap'),
          'child': const fmt.ConstructorCall('Text', <String, Object?>{}),
        },
      ),
    );

    final composed = _compose(source, routePlan);
    final wrapper = composed.widgets.single.root as fmt.ConstructorCall;
    final child = wrapper.arguments['child']! as fmt.ConstructorCall;

    expect(wrapper.name, 'MeasurementPresented');
    expect(child.name, 'GestureDetector');
    expect(
      wrapper.arguments['carriers'],
      unorderedEquals([for (final route in routePlan.routes) route.carrier]),
    );
    expect(
      wrapper.arguments['pointTokens'],
      orderedEquals(_compactTokens(routePlan.routes)),
    );
    expect(
      _eventHandlers(composed)
          .map((event) => event.eventArguments[kMeasurementRouteArgumentKeyV1])
          .whereType<String>(),
      unorderedEquals([for (final route in routePlan.routes) route.carrier]),
    );
  });

  test(
    'keeps a presentation wrapper inside the selected conditional branch',
    () {
      final routePlan = _routePlan(const [
        'reference.presentation.conditional',
      ]);
      final source = _library(
        fmt.Switch(
          'selected',
          <Object?, Object>{
            true: fmt.ConstructorCall(
              'Button',
              <String, Object?>{
                'onPressed': _markedEvent('reference.presentation.conditional'),
              },
            ),
            false: const fmt.ConstructorCall('Text', <String, Object?>{}),
          },
        ),
      );

      final composed = _compose(source, routePlan);
      final root = composed.widgets.single.root as fmt.Switch;
      final selected = root.outputs[true]! as fmt.ConstructorCall;
      final unselected = root.outputs[false]! as fmt.ConstructorCall;

      expect(root, isA<fmt.Switch>());
      expect(selected.name, 'MeasurementPresented');
      expect(
        (selected.arguments['child']! as fmt.ConstructorCall).name,
        'Button',
      );
      expect(unselected.name, 'Text');
    },
  );

  test(
    'leaves a Measurement-disabled artifact without a wrapper or import',
    () {
      final routePlan = _routePlan(const []);
      final source = _library(
        const fmt.ConstructorCall('Container', <String, Object?>{}),
      );
      final blob = Uint8List.fromList(fmt.encodeLibraryBlob(source));

      final result = MeasurementRfwRouteComposer.composeBlob(
        blob: blob,
        routePlan: routePlan,
      );
      final composed = fmt.decodeLibraryBlob(result.blob);

      expect(result.blob, orderedEquals(blob));
      expect(result.generatedReferences, isEmpty);
      expect(
        composed.imports.where(
          (entry) => entry.name.parts.join('.') == 'restage.measurement',
        ),
        isEmpty,
      );
      expect(composed.widgets.single.root, isA<fmt.ConstructorCall>());
      expect(
        (composed.widgets.single.root as fmt.ConstructorCall).name,
        'Container',
      );
    },
  );

  test('does not reserve the presentation namespace when no wrapper is needed',
      () {
    const source = fmt.RemoteWidgetLibrary(
      [
        fmt.Import(fmt.LibraryName(<String>['restage', 'measurement'])),
      ],
      [
        fmt.WidgetDeclaration(
          'Root',
          null,
          fmt.ConstructorCall('Text', <String, Object?>{}),
        ),
      ],
    );
    final blob = Uint8List.fromList(fmt.encodeLibraryBlob(source));

    final result = MeasurementRfwRouteComposer.composeBlob(
      blob: blob,
      routePlan: _routePlan(const []),
    );

    expect(result.blob, orderedEquals(blob));
    expect(result.generatedReferences, isEmpty);
  });

  test('retains a byte-stable complete final route closure', () {
    final routePlan = _routePlan(const [
      'reference.presentation.alpha',
      'reference.presentation.beta',
    ]);
    final source = _library(
      fmt.ConstructorCall(
        'Column',
        <String, Object?>{
          'children': <Object?>[
            fmt.ConstructorCall(
              'Button',
              <String, Object?>{
                'onPressed': _markedEvent('reference.presentation.alpha'),
              },
            ),
            fmt.ConstructorCall(
              'Button',
              <String, Object?>{
                'onPressed': _markedEvent('reference.presentation.beta'),
              },
            ),
          ],
        },
      ),
    );
    final blob = Uint8List.fromList(fmt.encodeLibraryBlob(source));

    final first = MeasurementRfwRouteComposer.composeBlob(
      blob: blob,
      routePlan: routePlan,
    );
    final second = MeasurementRfwRouteComposer.composeBlob(
      blob: blob,
      routePlan: routePlan,
    );

    expect(first.blob, orderedEquals(second.blob));
    expect(
      first.generatedReferences,
      routePlan.routes.map((route) => route.generatedReferenceId.value).toSet(),
    );
    expect(
      () => MeasurementRfwRouteComposer.requireCompleteRouteClosure(
        routePlan: routePlan,
        consumedReferences: first.generatedReferences,
      ),
      returnsNormally,
    );
  });

  test('rejects an ambiguous private presentation library spelling', () {
    final routePlan = _routePlan(const ['reference.presentation.conflict']);
    final source = fmt.RemoteWidgetLibrary(
      const [
        fmt.Import(fmt.LibraryName(<String>['restage', 'core'])),
        fmt.Import(fmt.LibraryName(<String>['restage', 'measurement'])),
      ],
      [
        fmt.WidgetDeclaration(
          'Root',
          null,
          fmt.ConstructorCall(
            'Button',
            <String, Object?>{
              'onPressed': _markedEvent('reference.presentation.conflict'),
            },
          ),
        ),
      ],
    );

    expect(
      () => MeasurementRfwRouteComposer.composeBlob(
        blob: Uint8List.fromList(fmt.encodeLibraryBlob(source)),
        routePlan: routePlan,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a conflicting local presentation constructor spelling', () {
    final routePlan = _routePlan(const ['reference.presentation.constructor']);
    final source = fmt.RemoteWidgetLibrary(
      const [
        fmt.Import(fmt.LibraryName(<String>['restage', 'core'])),
      ],
      [
        const fmt.WidgetDeclaration(
          'MeasurementPresented',
          null,
          fmt.ConstructorCall('Text', <String, Object?>{}),
        ),
        fmt.WidgetDeclaration(
          'Root',
          null,
          fmt.ConstructorCall(
            'Button',
            <String, Object?>{
              'onPressed': _markedEvent(
                'reference.presentation.constructor',
              ),
            },
          ),
        ),
      ],
    );

    expect(
      () => MeasurementRfwRouteComposer.composeBlob(
        blob: Uint8List.fromList(fmt.encodeLibraryBlob(source)),
        routePlan: routePlan,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

fmt.RemoteWidgetLibrary _compose(
  fmt.RemoteWidgetLibrary source,
  MeasurementPublicationRoutePlanV1 routePlan,
) {
  final result = MeasurementRfwRouteComposer.composeBlob(
    blob: Uint8List.fromList(fmt.encodeLibraryBlob(source)),
    routePlan: routePlan,
  );
  MeasurementRfwRouteComposer.requireCompleteRouteClosure(
    routePlan: routePlan,
    consumedReferences: result.generatedReferences,
  );
  return fmt.decodeLibraryBlob(result.blob);
}

fmt.RemoteWidgetLibrary _library(fmt.BlobNode root) => fmt.RemoteWidgetLibrary(
      const [
        fmt.Import(fmt.LibraryName(<String>['restage', 'core'])),
      ],
      [fmt.WidgetDeclaration('Root', null, root)],
    );

fmt.EventHandler _markedEvent(String generatedReference) => fmt.EventHandler(
      'activate',
      <String, Object?>{
        kMeasurementRouteReferenceMarkerKeyV1:
            MeasurementRouteEmissionPlan.markerForGeneratedReference(
          GeneratedReferenceId(generatedReference),
        ),
      },
    );

MeasurementPublicationRoutePlanV1 _routePlan(List<String> references) {
  final edge = ArtifactOccurrenceEdgeToken('edge.presentation-root');
  final code = CodeIdentityId('code.presentation-root');
  final nodeToken = NodeTokenId('node.presentation-root');
  return MeasurementPublicationRoutePlanV1(
    surfaceId: SurfaceId('surface.presentation'),
    analyticsSurfaceKey: AnalyticsSurfaceKey('presentation'),
    deliverySurfaceType: DeliverySurfaceTypeId('surface.general'),
    minimumMeasurementClient: 1,
    completeManifestId: MeasurementManifestId('manifest.presentation'),
    privacyPolicyRevisionId: AuthorityRevisionId('privacy.presentation-v1'),
    collectionBudgetRevisionId: AuthorityRevisionId('budget.presentation-v1'),
    artifacts: [
      MeasurementPublicationRouteArtifactV1(
        artifactId: ArtifactId('artifact.presentation'),
        artifactKind: ArtifactKindId('rfw.blob'),
        occurrenceEdgeToken: edge,
        localManifestId: MeasurementManifestId('manifest.presentation-local'),
      ),
    ],
    codeIdentityBindings: [
      CodeIdentityBindingV1(
        codeIdentityId: code,
        canonicalNodeTokenId: nodeToken,
      ),
    ],
    nodes: [
      MeasurementPublicationDraftNodeV1(
        codeIdentityId: code,
        artifactOccurrenceEdgeToken: edge,
      ),
    ],
    events: [
      for (var index = 0; index < references.length; index += 1)
        MeasurementPublicationDraftEventV1(
          nodeCodeIdentityId: code,
          sourceEventIdentity: SourceEventIdentity('onPressed$index'),
          lineageId: PointLineageId('lineage.presentation-$index'),
          generatedReferenceId: GeneratedReferenceId(references[index]),
          dartSymbol: GeneratedDartSymbol('presentationPoint$index'),
          displayMetadataRef: DisplayMetadataRef('display.presentation-$index'),
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
        ),
    ],
    routeSeeds: [
      for (final reference in references)
        MeasurementPublicationDraftRouteSeedV1(
          generatedReferenceId: GeneratedReferenceId(reference),
          artifactOccurrenceEdgeToken: edge,
        ),
    ],
    lineageIntents: [
      for (var index = 0; index < references.length; index += 1)
        MeasurementPublicationLineageIntentV1(
          transitionId: LineageTransitionId('transition.presentation-$index'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          next: [
            MeasurementPublicationCurrentEndpointIntentV1(
              generatedReferenceId: GeneratedReferenceId(references[index]),
              lineageId: PointLineageId('lineage.presentation-$index'),
            ),
          ],
        ),
    ],
  );
}

List<fmt.EventHandler> _eventHandlers(fmt.RemoteWidgetLibrary library) {
  final result = <fmt.EventHandler>[];

  void visit(Object? value) {
    switch (value) {
      case final fmt.RemoteWidgetLibrary library:
        library.widgets.forEach(visit);
      case final fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case final fmt.EventHandler handler:
        result.add(handler);
        visit(handler.eventArguments);
      case final fmt.ConstructorCall call:
        visit(call.arguments);
      case final fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case final fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case final fmt.Switch switchNode:
        visit(switchNode.input);
        switchNode.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        break;
    }
  }

  visit(library);
  return result;
}

String _compactToken(String routeCarrier) => routeCarrier.split('.').last;

List<String> _compactTokens(
  Iterable<MeasurementPublicationDraftRouteV1> routes,
) {
  final carriers = [for (final route in routes) route.carrier]..sort();
  return [for (final carrier in carriers) _compactToken(carrier)];
}
