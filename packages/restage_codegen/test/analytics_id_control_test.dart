import 'dart:convert';

import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/analytics_id_lowering.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

const String _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _sourceDeclarationIdentity =
    'package:apps_examples/surfaces.dart#Checkout';

void main() {
  final primaryScope = _scope('checkout');
  final secondaryScope = _scope('receipt');

  test('builds a complete replacement payload from exact reservations', () {
    final first = _capture('checkout.primary', 'handle.one');
    final second = _capture('checkout.primary', 'handle.two');
    final result = buildAnalyticsIdControlOutputFromReservations(
      packageName: 'apps_examples',
      scopes: [primaryScope, secondaryScope],
      captures: [first, second],
      reservations: [
        _resolved(primaryScope, 'one'),
        _resolved(primaryScope, 'two'),
      ],
      location: 'lib/surfaces.dart',
    );

    expect(result.issues, isEmpty);
    expect(result.output.publications, hasLength(2));
    final primary = result.output.publications.singleWhere(
      (publication) => publication.scope.key == primaryScope.key,
    );
    final secondary = result.output.publications.singleWhere(
      (publication) => publication.scope.key == secondaryScope.key,
    );
    expect(primary.entries, hasLength(2));
    expect(secondary.entries, isEmpty);
    expect(
      primary.entries
          .map(
            (entry) => entry
                .presentationReservation.generatedPresentationReferenceId.value,
          )
          .toList(),
      ['reference.one', 'reference.two'],
    );
    final encoded = result.output.encodeJson();
    final decoded = AnalyticsIdControlOutputV1.fromJson(jsonDecode(encoded));
    expect(decoded.encodeJson(), encoded);
    expect(encoded, contains('"measurementSurfaceId"'));
    expect(encoded, contains('"finalTargetNeutralDraftDigest"'));
    expect(encoded, contains('"routePlanClosureDigest"'));
    expect(encoded, contains('"generatedPresentationReferenceId"'));
    expect(encoded, contains('"canonicalNodeTokenId"'));
    expect(encoded, contains('"presentationRouteCarrier"'));
    expect(encoded, contains('"presentationRouteFingerprint"'));
    expect(encoded, isNot(contains('structuralOccurrenceKey')));
    expect(encoded, isNot(contains('handle.one')));
    final keys = _allJsonKeys(jsonDecode(encoded));
    for (final rejectedKey in const <String>{
      'target',
      'surfaceRevisionId',
      'artifactGraphHash',
      'occurrenceId',
    }) {
      expect(keys, isNot(contains(rejectedKey)));
    }
  });

  test('adding or renaming a label changes only current entry bytes', () {
    final original = _buildWithLabel('checkout.primary', primaryScope);
    final renamed = _buildWithLabel('checkout.confirm', primaryScope);
    final without = buildEmptyAnalyticsIdControlOutput(
      packageName: 'apps_examples',
      scopes: [primaryScope],
    );

    expect(original.issues, isEmpty);
    expect(renamed.issues, isEmpty);
    expect(without.publications.single.entries, isEmpty);
    expect(
      _withoutEntries(original.output.toJson()),
      _withoutEntries(renamed.output.toJson()),
    );
    expect(
      _withoutEntries(original.output.toJson()),
      _withoutEntries(without.toJson()),
    );
    final originalEntry = original.output.publications.single.entries.single;
    final renamedEntry = renamed.output.publications.single.entries.single;
    expect(
      originalEntry.presentationReservation.toJson(),
      renamedEntry.presentationReservation.toJson(),
    );
    expect(original.output.encodeJson(), isNot(renamed.output.encodeJson()));
  });

  test('rejects a route carrier with mismatched edge or fingerprint', () {
    final valid = _reservation(primaryScope, 'one');

    expect(
      () => AnalyticsIdPresentationReservation(
        generatedPresentationReferenceId:
            valid.generatedPresentationReferenceId,
        nodeCodeIdentityId: valid.nodeCodeIdentityId,
        canonicalNodeTokenId: valid.canonicalNodeTokenId,
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.two'),
        presentationLineageId: valid.presentationLineageId,
        displayMetadataRef: valid.displayMetadataRef,
        presentationRouteCarrier: valid.presentationRouteCarrier,
        presentationRouteFingerprint: valid.presentationRouteFingerprint,
      ),
      throwsArgumentError,
    );
    expect(
      () => AnalyticsIdPresentationReservation(
        generatedPresentationReferenceId:
            valid.generatedPresentationReferenceId,
        nodeCodeIdentityId: valid.nodeCodeIdentityId,
        canonicalNodeTokenId: valid.canonicalNodeTokenId,
        artifactOccurrenceEdgeToken: valid.artifactOccurrenceEdgeToken,
        presentationLineageId: valid.presentationLineageId,
        displayMetadataRef: valid.displayMetadataRef,
        presentationRouteCarrier: valid.presentationRouteCarrier,
        presentationRouteFingerprint: CanonicalDigest(_digestB),
      ),
      throwsArgumentError,
    );
  });

  test('scope join rejects source and remapped presentation carriers', () {
    final sourceCarrier = _sourceReservation(primaryScope, 'one');
    final wrongReference = _remappedReservation(
      primaryScope,
      'one',
      routeReferenceSuffix: 'other',
    );
    final wrongDigest = _remappedReservation(
      primaryScope,
      'one',
      routeDigest: CanonicalDigest(_digestB),
    );

    for (final reservation in [
      sourceCarrier,
      wrongReference,
      wrongDigest,
    ]) {
      expect(
        () => AnalyticsIdControlPublication(
          scope: primaryScope,
          entries: [
            AnalyticsIdControlEntry(
              analyticsId: 'checkout.primary',
              presentationReservation: reservation,
            ),
          ],
        ),
        throwsArgumentError,
      );
      final result = buildAnalyticsIdControlOutputFromReservations(
        packageName: 'apps_examples',
        scopes: [primaryScope],
        captures: [_capture('checkout.primary', 'handle.one')],
        reservations: [
          _resolved(
            primaryScope,
            'one',
            presentationReservation: reservation,
          ),
        ],
        location: 'lib/surfaces.dart',
      );

      expect(result.isValid, isFalse);
      expect(result.output.publications.single.entries, isEmpty);
    }
  });

  test('rejects a publication above the shared route limit', () {
    expect(
      () => AnalyticsIdControlPublication(
        scope: primaryScope,
        entries: [
          for (var index = 0;
              index <= kMaximumMeasurementPublicationRuntimeRouteCount;
              index += 1)
            AnalyticsIdControlEntry(
              analyticsId: 'label.$index',
              presentationReservation: _reservation(
                primaryScope,
                'entry.$index',
              ),
            ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('fails closed when a reservation is absent or conflicts', () {
    final unresolved = buildAnalyticsIdControlOutputFromReservations(
      packageName: 'apps_examples',
      scopes: [primaryScope],
      captures: [_capture('checkout.primary', 'handle.one')],
      reservations: const [],
      location: 'lib/surfaces.dart',
    );
    final wrongScope = buildAnalyticsIdControlOutputFromReservations(
      packageName: 'apps_examples',
      scopes: [primaryScope],
      captures: [_capture('checkout.primary', 'handle.one')],
      reservations: [_resolved(secondaryScope, 'one')],
      location: 'lib/surfaces.dart',
    );
    final conflictingLabels = buildAnalyticsIdControlOutputFromReservations(
      packageName: 'apps_examples',
      scopes: [primaryScope],
      captures: [
        _capture('checkout.primary', 'handle.one'),
        _capture('checkout.confirm', 'handle.two'),
      ],
      reservations: [
        _resolved(
          primaryScope,
          'one',
          reservationSuffix: 'shared',
        ),
        _resolved(
          primaryScope,
          'two',
          reservationSuffix: 'shared',
        ),
      ],
      location: 'lib/surfaces.dart',
    );
    final conflictingProjection = buildAnalyticsIdControlOutputFromReservations(
      packageName: 'apps_examples',
      scopes: [primaryScope],
      captures: [
        _capture('checkout.primary', 'handle.one'),
        _capture('checkout.primary', 'handle.two'),
      ],
      reservations: [
        _resolved(
          primaryScope,
          'one',
          generatedReferenceSuffix: 'shared',
        ),
        _resolved(
          primaryScope,
          'two',
          generatedReferenceSuffix: 'shared',
        ),
      ],
      location: 'lib/surfaces.dart',
    );
    final mismatchedHandle = buildAnalyticsIdControlOutputFromReservations(
      packageName: 'apps_examples',
      scopes: [primaryScope],
      captures: [_capture('checkout.primary', 'handle.one')],
      reservations: [_resolved(primaryScope, 'two')],
      location: 'lib/surfaces.dart',
    );

    for (final result in [
      unresolved,
      wrongScope,
      conflictingLabels,
      conflictingProjection,
      mismatchedHandle,
    ]) {
      expect(result.isValid, isFalse);
      expect(result.issues, isNotEmpty);
    }
  });
}

AnalyticsIdControlBuildResult _buildWithLabel(
  String analyticsId,
  AnalyticsIdControlPublicationScope scope,
) =>
    buildAnalyticsIdControlOutputFromReservations(
      packageName: 'apps_examples',
      scopes: [scope],
      captures: [_capture(analyticsId, 'handle.one')],
      reservations: [_resolved(scope, 'one')],
      location: 'lib/surfaces.dart',
    );

AnalyticsIdControlCapture _capture(String analyticsId, String handle) =>
    AnalyticsIdControlCapture(
      sourceDeclarationIdentity: _sourceDeclarationIdentity,
      capture: AnalyticsIdDeclaration(
        analyticsId: analyticsId,
        presentationHandle: _fixtureHandle(handle),
      ),
    );

AnalyticsIdControlPublicationScope _scope(String slug) {
  final selector = MeasurementPublicationSelectorV1(
    surface: Surface.general,
    slug: slug,
    sourceKind: SurfaceSourceKind.screen,
    contractVersion: 1,
  );
  return AnalyticsIdControlPublicationScope(
    selector: selector,
    measurementSurfaceId: selector.stableSurfaceId,
    routePlanClosureDigest: CanonicalDigest(_digestA),
    finalTargetNeutralDraftDigest: CanonicalDigest(_digestB),
  );
}

AnalyticsIdResolvedControlReservation _resolved(
  AnalyticsIdControlPublicationScope scope,
  String handleSuffix, {
  String? reservationSuffix,
  String? generatedReferenceSuffix,
  AnalyticsIdPresentationReservation? presentationReservation,
}) =>
    AnalyticsIdResolvedControlReservation(
      sourceDeclarationIdentity: _sourceDeclarationIdentity,
      presentationHandle: _fixtureHandle('handle.$handleSuffix'),
      scope: scope,
      presentationReservation: presentationReservation ??
          _reservation(
            scope,
            reservationSuffix ?? handleSuffix,
            generatedReferenceSuffix: generatedReferenceSuffix,
          ),
    );

AnalyticsIdPresentationReservation _reservation(
  AnalyticsIdControlPublicationScope scope,
  String suffix, {
  String? generatedReferenceSuffix,
}) {
  final edge = ArtifactOccurrenceEdgeToken('edge.$suffix');
  final reference = GeneratedPresentationReferenceId(
    'reference.${generatedReferenceSuffix ?? suffix}',
  );
  final carrier = MeasurementPublicationRouteCarrierV1.derivePresentation(
    routeDraftClosureDigest: scope.routePlanClosureDigest,
    artifactOccurrenceEdgeToken: edge,
    generatedPresentationReferenceId: reference,
  ).value;
  return AnalyticsIdPresentationReservation(
    generatedPresentationReferenceId: reference,
    nodeCodeIdentityId: CodeIdentityId('node.$suffix'),
    canonicalNodeTokenId: NodeTokenId('token.$suffix'),
    artifactOccurrenceEdgeToken: edge,
    presentationLineageId: PointLineageId('lineage.$suffix'),
    displayMetadataRef: DisplayMetadataRef('display.$suffix'),
    presentationRouteCarrier: carrier,
    presentationRouteFingerprint:
        OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(carrier).fingerprint,
  );
}

AnalyticsIdPresentationReservation _sourceReservation(
  AnalyticsIdControlPublicationScope scope,
  String suffix,
) {
  final edge = ArtifactOccurrenceEdgeToken('edge.$suffix');
  final carrier = MeasurementPublicationRouteCarrierV1.derive(
    routeDraftClosureDigest: scope.routePlanClosureDigest,
    artifactOccurrenceEdgeToken: edge,
    generatedReferenceId: GeneratedReferenceId('route.$suffix'),
  ).value;
  return _reservationWithCarrier(suffix, carrier);
}

AnalyticsIdPresentationReservation _remappedReservation(
  AnalyticsIdControlPublicationScope scope,
  String suffix, {
  String? routeReferenceSuffix,
  CanonicalDigest? routeDigest,
}) {
  final edge = ArtifactOccurrenceEdgeToken('edge.$suffix');
  final carrier = MeasurementPublicationRouteCarrierV1.derivePresentation(
    routeDraftClosureDigest: routeDigest ?? scope.routePlanClosureDigest,
    artifactOccurrenceEdgeToken: edge,
    generatedPresentationReferenceId: GeneratedPresentationReferenceId(
      'reference.${routeReferenceSuffix ?? suffix}',
    ),
  ).value;
  return _reservationWithCarrier(suffix, carrier);
}

AnalyticsIdPresentationReservation _reservationWithCarrier(
  String suffix,
  String carrier,
) =>
    AnalyticsIdPresentationReservation(
      generatedPresentationReferenceId:
          GeneratedPresentationReferenceId('reference.$suffix'),
      nodeCodeIdentityId: CodeIdentityId('node.$suffix'),
      canonicalNodeTokenId: NodeTokenId('token.$suffix'),
      artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.$suffix'),
      presentationLineageId: PointLineageId('lineage.$suffix'),
      displayMetadataRef: DisplayMetadataRef('display.$suffix'),
      presentationRouteCarrier: carrier,
      presentationRouteFingerprint:
          OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(carrier).fingerprint,
    );

Map<String, Object?> _withoutEntries(Map<String, Object?> source) {
  final publications = source['publications']! as List<Object?>;
  return <String, Object?>{
    ...source,
    'publications': [
      for (final value in publications)
        <String, Object?>{
          ...(value! as Map<String, Object?>),
          'entries': const <Object?>[],
        },
    ],
  };
}

Set<String> _allJsonKeys(Object? value) {
  final result = <String>{};
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      result
        ..add(entry.key)
        ..addAll(_allJsonKeys(entry.value));
    }
  } else if (value is List<Object?>) {
    for (final item in value) {
      result.addAll(_allJsonKeys(item));
    }
  }
  return result;
}

fmt.RfwCatalogOccurrenceHandle _fixtureHandle(String value) {
  final library = fmt.parseLibraryFile('widget Root = Card();');
  final occurrenceSet = fmt.ResolvedRfwCatalogOccurrenceSet.resolve(
    parsedLibrary: library,
    input: fmt.RfwCatalogOccurrenceResolutionInput(
      artifactProvenance: 'fixture.$value',
      sourceLibraryIdentity: 'fixture.library',
      sourceDeclarationIdentity: _sourceDeclarationIdentity,
      renderEntryNames: const ['Root'],
      catalogConstructors: [
        fmt.RfwCatalogConstructorProvenance(
          constructorName: 'Card',
          catalogLibraryNamespace: WidgetLibrary.core.namespace,
          catalogWidgetWireId: WireId('w0001'),
        ),
      ],
      localSymbols: [fmt.RfwCatalogLocalSymbol(name: 'Root')],
    ),
  );
  return occurrenceSet.occurrences.single.handle;
}
