// Codec factories intentionally follow their JSON writers for local review.
// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:convert';

import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/analytics_id_lowering.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_rfw_presentation_discovery.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show isValidAnalyticsId;

/// Package-wide compiler output carrying only current occurrence labels.
const String kRestageAnalyticsIdControlOutputPath =
    'lib/src/measurement/restage.analytics-id.control.json';

/// Materialized sibling filename for current occurrence-label metadata.
const String kRestageAnalyticsIdMetadataFileName =
    'restage.analytics-id.metadata.json';

/// Label-free target-neutral reservation material for one catalog occurrence.
///
/// The opaque compiler handle that resolves this material is deliberately not
/// represented here. Every field is a durable projection from the completed
/// route join and no field is derived from
/// [AnalyticsIdControlEntry.analyticsId].
@immutable
final class AnalyticsIdPresentationReservation {
  /// Creates one validated target-neutral reservation projection.
  AnalyticsIdPresentationReservation({
    required this.generatedPresentationReferenceId,
    required this.nodeCodeIdentityId,
    required this.canonicalNodeTokenId,
    required this.artifactOccurrenceEdgeToken,
    required this.presentationLineageId,
    required this.displayMetadataRef,
    required this.presentationRouteCarrier,
    required this.presentationRouteFingerprint,
  }) {
    final carrier = MeasurementPublicationRouteCarrierV1.parse(
      presentationRouteCarrier,
    );
    if (carrier.artifactOccurrenceEdgeToken != artifactOccurrenceEdgeToken) {
      throw ArgumentError(
        'The presentation route carrier must retain the exact artifact edge.',
      );
    }
    final fingerprint = OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
      presentationRouteCarrier,
    ).fingerprint;
    if (fingerprint != presentationRouteFingerprint) {
      throw ArgumentError(
        'The presentation route fingerprint must match the complete carrier.',
      );
    }
  }

  /// Projects one exact compiler materialization without author-controlled
  /// identity input.
  factory AnalyticsIdPresentationReservation.fromJoin(
    MeasurementPresentationOccurrenceJoin join,
  ) =>
      AnalyticsIdPresentationReservation(
        generatedPresentationReferenceId: join.presentationReferenceId,
        nodeCodeIdentityId: join.nodeCodeIdentityId,
        canonicalNodeTokenId: join.canonicalNodeTokenId,
        artifactOccurrenceEdgeToken: join.artifactOccurrenceEdgeToken,
        presentationLineageId: join.draftPresentationLineageId,
        displayMetadataRef: join.presentationDisplayMetadataRef,
        presentationRouteCarrier: join.presentationRouteCarrier,
        presentationRouteFingerprint:
            join.presentationRouteFingerprint.fingerprint,
      );

  /// Reserved presentation reference selected before artifact encoding.
  final GeneratedPresentationReferenceId generatedPresentationReferenceId;

  /// Compiler-owned node identity.
  final CodeIdentityId nodeCodeIdentityId;

  /// Canonical node token selected for the catalog occurrence.
  final NodeTokenId canonicalNodeTokenId;

  /// Exact mounted artifact edge.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Draft presentation continuity identity.
  final PointLineageId presentationLineageId;

  /// Non-identity display metadata reference.
  final DisplayMetadataRef displayMetadataRef;

  /// Strict complete route carrier emitted for this reservation.
  final String presentationRouteCarrier;

  /// Domain-separated fingerprint of [presentationRouteCarrier].
  final CanonicalDigest presentationRouteFingerprint;

  /// Label-independent key for one exact current replacement entry.
  String get replacementKey => generatedPresentationReferenceId.value;

  /// Compiler reconciliation key used for deterministic order.
  String get sortKey => [
        generatedPresentationReferenceId.value,
        nodeCodeIdentityId.value,
        canonicalNodeTokenId.value,
        artifactOccurrenceEdgeToken.value,
        presentationLineageId.value,
        displayMetadataRef.value,
        presentationRouteFingerprint.hex,
        presentationRouteCarrier,
      ].join('\u0000');

  Map<String, Object?> toJson() => <String, Object?>{
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'canonicalNodeTokenId': canonicalNodeTokenId.value,
        'displayMetadataRef': displayMetadataRef.value,
        'generatedPresentationReferenceId':
            generatedPresentationReferenceId.value,
        'nodeCodeIdentityId': nodeCodeIdentityId.value,
        'presentationLineageId': presentationLineageId.value,
        'presentationRouteCarrier': presentationRouteCarrier,
        'presentationRouteFingerprint': presentationRouteFingerprint.hex,
      };

  factory AnalyticsIdPresentationReservation.fromJson(Object? value) {
    final json = _object(value, 'presentationReservation');
    _exactKeys(
      json,
      const <String>{
        'artifactOccurrenceEdgeToken',
        'canonicalNodeTokenId',
        'displayMetadataRef',
        'generatedPresentationReferenceId',
        'nodeCodeIdentityId',
        'presentationLineageId',
        'presentationRouteCarrier',
        'presentationRouteFingerprint',
      },
      'presentationReservation',
    );
    try {
      return AnalyticsIdPresentationReservation(
        generatedPresentationReferenceId: GeneratedPresentationReferenceId(
          _string(
            json,
            'generatedPresentationReferenceId',
            'presentationReservation',
          ),
        ),
        nodeCodeIdentityId: CodeIdentityId(
          _string(json, 'nodeCodeIdentityId', 'presentationReservation'),
        ),
        canonicalNodeTokenId: NodeTokenId(
          _string(json, 'canonicalNodeTokenId', 'presentationReservation'),
        ),
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          _string(
            json,
            'artifactOccurrenceEdgeToken',
            'presentationReservation',
          ),
        ),
        presentationLineageId: PointLineageId(
          _string(json, 'presentationLineageId', 'presentationReservation'),
        ),
        displayMetadataRef: DisplayMetadataRef(
          _string(json, 'displayMetadataRef', 'presentationReservation'),
        ),
        presentationRouteCarrier: _string(
          json,
          'presentationRouteCarrier',
          'presentationReservation',
        ),
        presentationRouteFingerprint: CanonicalDigest(
          _string(
            json,
            'presentationRouteFingerprint',
            'presentationReservation',
          ),
        ),
      );
      // Admission failures become wire errors at this decoder boundary.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      throw FormatException('presentationReservation is invalid: $error');
    }
  }
}

/// One label paired with an exact target-neutral presentation reservation.
@immutable
final class AnalyticsIdControlEntry {
  /// Creates one current replacement entry.
  AnalyticsIdControlEntry({
    required this.analyticsId,
    required this.presentationReservation,
  }) {
    if (!isValidAnalyticsId(analyticsId)) {
      throw ArgumentError.value(analyticsId, 'analyticsId');
    }
  }

  /// Bounded author-facing identifier.
  final String analyticsId;

  /// Exact label-independent reservation projection.
  final AnalyticsIdPresentationReservation presentationReservation;

  Map<String, Object?> toJson() => <String, Object?>{
        'analyticsId': analyticsId,
        'presentationReservation': presentationReservation.toJson(),
      };

  factory AnalyticsIdControlEntry.fromJson(Object? value) {
    final json = _object(value, 'analyticsIdControlEntry');
    _exactKeys(
      json,
      const <String>{'analyticsId', 'presentationReservation'},
      'analyticsIdControlEntry',
    );
    final analyticsId = _string(json, 'analyticsId', 'analyticsIdControlEntry');
    if (!isValidAnalyticsId(analyticsId)) {
      throw const FormatException(
        'analyticsIdControlEntry.analyticsId is not a valid identifier.',
      );
    }
    return AnalyticsIdControlEntry(
      analyticsId: analyticsId,
      presentationReservation: AnalyticsIdPresentationReservation.fromJson(
        json['presentationReservation'],
      ),
    );
  }
}

/// Exact publication material shared by every current replacement entry.
@immutable
final class AnalyticsIdControlPublicationScope {
  /// Creates a current-label scope for one publication selector.
  AnalyticsIdControlPublicationScope({
    required this.selector,
    required this.measurementSurfaceId,
    required this.routePlanClosureDigest,
    required this.finalTargetNeutralDraftDigest,
  }) {
    if (measurementSurfaceId != selector.stableSurfaceId) {
      throw ArgumentError(
        'Measurement surface id must match the publication selector.',
      );
    }
  }

  /// Builds the exact scope from one completed compiler publication.
  factory AnalyticsIdControlPublicationScope.fromCompilerPublication(
    MeasurementCompilerPublication publication,
  ) =>
      AnalyticsIdControlPublicationScope(
        selector: publication.selector,
        measurementSurfaceId: publication.draft.surfaceId,
        routePlanClosureDigest: publication.routePlan.routeDraftClosureDigest,
        finalTargetNeutralDraftDigest: publication.draft.canonicalDigest,
      );

  /// Target-neutral publication selector.
  final MeasurementPublicationSelectorV1 selector;

  /// Stable surface identity sealed by the Measurement draft.
  final SurfaceId measurementSurfaceId;

  /// Exact route-plan closure selected by this build.
  final CanonicalDigest routePlanClosureDigest;

  /// Final target-neutral draft selected by this build.
  final CanonicalDigest finalTargetNeutralDraftDigest;

  /// Stable selector key used to group current entries.
  String get key => selector.key;

  Map<String, Object?> toJson() => <String, Object?>{
        'finalTargetNeutralDraftDigest': finalTargetNeutralDraftDigest.hex,
        'measurementSurfaceId': measurementSurfaceId.value,
        'routePlanClosureDigest': routePlanClosureDigest.hex,
        'selector': selector.toJson(),
      };

  factory AnalyticsIdControlPublicationScope.fromJson(Object? value) {
    final json = _object(value, 'analyticsIdControlPublicationScope');
    _exactKeys(
      json,
      const <String>{
        'finalTargetNeutralDraftDigest',
        'measurementSurfaceId',
        'routePlanClosureDigest',
        'selector',
      },
      'analyticsIdControlPublicationScope',
    );
    return AnalyticsIdControlPublicationScope(
      selector: MeasurementPublicationSelectorV1.fromJson(json['selector']),
      measurementSurfaceId: SurfaceId(
        _string(
          json,
          'measurementSurfaceId',
          'analyticsIdControlPublicationScope',
        ),
      ),
      routePlanClosureDigest: CanonicalDigest(
        _string(
          json,
          'routePlanClosureDigest',
          'analyticsIdControlPublicationScope',
        ),
      ),
      finalTargetNeutralDraftDigest: CanonicalDigest(
        _string(
          json,
          'finalTargetNeutralDraftDigest',
          'analyticsIdControlPublicationScope',
        ),
      ),
    );
  }
}

/// Complete current replacement material for one publication selector.
@immutable
final class AnalyticsIdControlPublication {
  /// Creates one current replacement scope.
  AnalyticsIdControlPublication({
    required this.scope,
    required Iterable<AnalyticsIdControlEntry> entries,
  }) : entries = _sortedUniqueEntries(entries) {
    for (final entry in this.entries) {
      if (!_matchesPresentationRoute(entry.presentationReservation, scope)) {
        throw ArgumentError(
          'A control entry does not match its presentation route closure.',
        );
      }
    }
  }

  /// Exact target-neutral publication material.
  final AnalyticsIdControlPublicationScope scope;

  /// Every currently labeled presentation occurrence in this scope.
  final List<AnalyticsIdControlEntry> entries;

  Map<String, Object?> toJson() => <String, Object?>{
        ...scope.toJson(),
        'entries': <Object?>[for (final entry in entries) entry.toJson()],
      };

  factory AnalyticsIdControlPublication.fromJson(Object? value) {
    final json = _object(value, 'analyticsIdControlPublication');
    _exactKeys(
      json,
      const <String>{
        'finalTargetNeutralDraftDigest',
        'entries',
        'measurementSurfaceId',
        'routePlanClosureDigest',
        'selector',
      },
      'analyticsIdControlPublication',
    );
    return AnalyticsIdControlPublication(
      scope: AnalyticsIdControlPublicationScope.fromJson(<String, Object?>{
        'finalTargetNeutralDraftDigest': json['finalTargetNeutralDraftDigest'],
        'measurementSurfaceId': json['measurementSurfaceId'],
        'routePlanClosureDigest': json['routePlanClosureDigest'],
        'selector': json['selector'],
      }),
      entries: _list(json, 'entries', 'analyticsIdControlPublication')
          .map(AnalyticsIdControlEntry.fromJson),
    );
  }
}

/// Build-owned, noncanonical package metadata for current label replacement.
@immutable
final class AnalyticsIdControlOutputV1 {
  /// Creates a deterministic current-value control output.
  AnalyticsIdControlOutputV1({
    required this.packageName,
    required Iterable<AnalyticsIdControlPublication> publications,
  }) : publications = _sortedUniquePublications(publications) {
    if (packageName.isEmpty || packageName.trim() != packageName) {
      throw ArgumentError.value(packageName, 'packageName');
    }
  }

  /// Package that produced the metadata.
  final String packageName;

  /// Complete replacement scopes, including scopes with no labels.
  final List<AnalyticsIdControlPublication> publications;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': 'restageAnalyticsIdControl',
        'package': packageName,
        'publications': <Object?>[
          for (final publication in publications) publication.toJson(),
        ],
        'schemaVersion': 1,
      };

  /// Deterministic JSON for a noncanonical current-value output.
  String encodeJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory AnalyticsIdControlOutputV1.fromJson(Object? value) {
    final json = _object(value, 'analyticsIdControl');
    _exactKeys(
      json,
      const <String>{'kind', 'package', 'publications', 'schemaVersion'},
      'analyticsIdControl',
    );
    if (_string(json, 'kind', 'analyticsIdControl') !=
        'restageAnalyticsIdControl') {
      throw const FormatException('analyticsIdControl.kind is unsupported.');
    }
    if (_integer(json, 'schemaVersion', 'analyticsIdControl') != 1) {
      throw const FormatException(
        'analyticsIdControl.schemaVersion is unsupported.',
      );
    }
    return AnalyticsIdControlOutputV1(
      packageName: _string(json, 'package', 'analyticsIdControl'),
      publications: _list(json, 'publications', 'analyticsIdControl')
          .map(AnalyticsIdControlPublication.fromJson),
    );
  }
}

/// Reads the package-wide current-label control output when it is available.
///
/// Callers use this only for metadata materialization. Publication assembly,
/// bundle encoding, and normal publication commands intentionally do not use
/// this reader.
Future<AnalyticsIdControlOutputV1?> readAnalyticsIdControlOutput(
  BuildStep buildStep,
) async {
  final asset = AssetId(
    buildStep.inputId.package,
    kRestageAnalyticsIdControlOutputPath,
  );
  if (!await buildStep.canRead(asset)) return null;
  return AnalyticsIdControlOutputV1.fromJson(
    jsonDecode(await buildStep.readAsString(asset)),
  );
}

/// Source-local capture retained until the presentation compiler supplies an
/// exact target-neutral reservation.
@immutable
final class AnalyticsIdControlCapture {
  /// Creates one label capture awaiting reservation resolution.
  const AnalyticsIdControlCapture({
    required this.sourceDeclarationIdentity,
    required this.capture,
  });

  /// Analyzer-owned source declaration identity.
  final String sourceDeclarationIdentity;

  /// Extracted label and opaque presentation reference.
  final AnalyticsIdDeclaration capture;
}

/// Typed target-neutral reservation resolved for one frozen occurrence.
@immutable
final class AnalyticsIdResolvedControlReservation {
  /// Creates one exact resolved reservation.
  const AnalyticsIdResolvedControlReservation({
    required this.sourceDeclarationIdentity,
    required this.presentationHandle,
    required this.scope,
    required this.presentationReservation,
  });

  /// Analyzer-owned source declaration identity.
  final String sourceDeclarationIdentity;

  /// Shared compiler-owned occurrence handle.
  final rfw.RfwCatalogOccurrenceHandle presentationHandle;

  /// Publication scope containing the reservation.
  final AnalyticsIdControlPublicationScope scope;

  /// Durable label-independent projection of the completed route join.
  final AnalyticsIdPresentationReservation presentationReservation;
}

/// Result of building the noncanonical current-label output.
@immutable
final class AnalyticsIdControlBuildResult {
  /// Creates a control build result.
  AnalyticsIdControlBuildResult({
    required this.output,
    required Iterable<Issue> issues,
  }) : issues = List.unmodifiable(issues);

  /// Current replacement payload.
  final AnalyticsIdControlOutputV1 output;

  /// Fail-closed capture or reservation diagnostics.
  final List<Issue> issues;

  /// Whether every captured label reached one exact reservation.
  bool get isValid => issues.isEmpty;
}

/// Builds a complete current-value output for publications without labels.
AnalyticsIdControlOutputV1 buildEmptyAnalyticsIdControlOutput({
  required String packageName,
  required Iterable<AnalyticsIdControlPublicationScope> scopes,
}) =>
    AnalyticsIdControlOutputV1(
      packageName: packageName,
      publications: [
        for (final scope in scopes)
          AnalyticsIdControlPublication(scope: scope, entries: const []),
      ],
    );

/// Joins label captures to compiler-owned target-neutral reservations.
///
/// [scopes] must come from the completed Measurement compiler output. It keeps
/// an empty entry for a publication whose current replacement has no labels.
AnalyticsIdControlBuildResult buildAnalyticsIdControlOutput({
  required String packageName,
  required Iterable<AnalyticsIdControlPublicationScope> scopes,
  required Iterable<AnalyticsIdControlCapture> captures,
  required Iterable<MeasurementRfwPresentationArtifactMaterialization>
      presentationMaterializations,
  required String location,
}) {
  final scopeList = List<AnalyticsIdControlPublicationScope>.unmodifiable(
    scopes,
  );
  final reservations = <AnalyticsIdResolvedControlReservation>[];
  final issues = <Issue>[];
  for (final materialization in presentationMaterializations) {
    final sourceDeclarationIdentity =
        materialization.occurrenceSet.input.sourceDeclarationIdentity;
    for (final join in materialization.joins) {
      final matchingScopes = scopeList
          .where(
            (scope) =>
                scope.measurementSurfaceId == join.measurementSurfaceId &&
                scope.routePlanClosureDigest == join.routeDraftClosureDigest,
          )
          .toList(growable: false);
      if (matchingScopes.length != 1) {
        issues.add(
          Issue(
            code: IssueCode.invalidAnalyticsId,
            message: 'A presentation materialization does not match exactly '
                'one completed publication scope.',
            location: '$location/$sourceDeclarationIdentity',
          ),
        );
        continue;
      }
      reservations.add(
        AnalyticsIdResolvedControlReservation(
          sourceDeclarationIdentity: sourceDeclarationIdentity,
          presentationHandle: join.handle,
          scope: matchingScopes.single,
          presentationReservation:
              AnalyticsIdPresentationReservation.fromJoin(join),
        ),
      );
    }
  }
  return _buildAnalyticsIdControlOutput(
    packageName: packageName,
    scopes: scopeList,
    captures: captures,
    reservations: reservations,
    location: location,
    initialIssues: issues,
  );
}

/// Validates caller-supplied typed reservations without constructing a
/// compiler materialization.
@visibleForTesting
AnalyticsIdControlBuildResult buildAnalyticsIdControlOutputFromReservations({
  required String packageName,
  required Iterable<AnalyticsIdControlPublicationScope> scopes,
  required Iterable<AnalyticsIdControlCapture> captures,
  required Iterable<AnalyticsIdResolvedControlReservation> reservations,
  required String location,
}) =>
    _buildAnalyticsIdControlOutput(
      packageName: packageName,
      scopes: scopes,
      captures: captures,
      reservations: reservations,
      location: location,
      initialIssues: const [],
    );

AnalyticsIdControlBuildResult _buildAnalyticsIdControlOutput({
  required String packageName,
  required Iterable<AnalyticsIdControlPublicationScope> scopes,
  required Iterable<AnalyticsIdControlCapture> captures,
  required Iterable<AnalyticsIdResolvedControlReservation> reservations,
  required String location,
  required Iterable<Issue> initialIssues,
}) {
  final entriesByScope = <String, List<AnalyticsIdControlEntry>>{
    for (final scope in scopes) scope.key: <AnalyticsIdControlEntry>[],
  };
  final scopesByKey = <String, AnalyticsIdControlPublicationScope>{
    for (final scope in scopes) scope.key: scope,
  };
  final entryByReservation = <String, AnalyticsIdControlEntry>{};
  final issues = <Issue>[...initialIssues];
  final reservationsByCaptureKey = <(String, rfw.RfwCatalogOccurrenceHandle),
      List<AnalyticsIdResolvedControlReservation>>{};
  for (final reservation in reservations) {
    reservationsByCaptureKey.putIfAbsent(
      (
        reservation.sourceDeclarationIdentity,
        reservation.presentationHandle,
      ),
      () => <AnalyticsIdResolvedControlReservation>[],
    ).add(reservation);
  }

  for (final sourceCapture in captures) {
    final matchingReservations = reservationsByCaptureKey[(
          sourceCapture.sourceDeclarationIdentity,
          sourceCapture.capture.presentationHandle,
        )] ??
        const <AnalyticsIdResolvedControlReservation>[];
    if (matchingReservations.length != 1) {
      issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'analyticsId did not resolve to exactly one target-neutral '
              'presentation materialization.',
          location: '$location/${sourceCapture.sourceDeclarationIdentity}',
        ),
      );
      continue;
    }
    final resolved = matchingReservations.single;
    final declaredScope = scopesByKey[resolved.scope.key];
    if (declaredScope == null || !_sameScope(declaredScope, resolved.scope)) {
      issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'analyticsId reservation is absent from the completed '
              'Measurement publication output.',
          location: '$location/${sourceCapture.sourceDeclarationIdentity}',
        ),
      );
      continue;
    }
    if (!_matchesPresentationRoute(
      resolved.presentationReservation,
      declaredScope,
    )) {
      issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'analyticsId reservation does not match its presentation '
              'route closure.',
          location: '$location/${sourceCapture.sourceDeclarationIdentity}',
        ),
      );
      continue;
    }
    final entry = AnalyticsIdControlEntry(
      analyticsId: sourceCapture.capture.analyticsId,
      presentationReservation: resolved.presentationReservation,
    );
    final reservationKey = '${declaredScope.key}\u0000'
        '${entry.presentationReservation.replacementKey}';
    final previous = entryByReservation[reservationKey];
    if (previous != null) {
      if (!_sameReservation(
        previous.presentationReservation,
        entry.presentationReservation,
      )) {
        issues.add(
          Issue(
            code: IssueCode.invalidAnalyticsId,
            message: 'Conflicting compiler reservations share one generated '
                'presentation reference.',
            location: '$location/${sourceCapture.sourceDeclarationIdentity}',
          ),
        );
      } else if (previous.analyticsId != entry.analyticsId) {
        issues.add(
          Issue(
            code: IssueCode.invalidAnalyticsId,
            message: 'Conflicting analyticsId declarations share one exact '
                'presentation reservation.',
            location: '$location/${sourceCapture.sourceDeclarationIdentity}',
          ),
        );
      }
      continue;
    }
    entryByReservation[reservationKey] = entry;
    entriesByScope[declaredScope.key]!.add(entry);
  }

  return AnalyticsIdControlBuildResult(
    output: AnalyticsIdControlOutputV1(
      packageName: packageName,
      publications: [
        for (final scope in scopesByKey.values)
          AnalyticsIdControlPublication(
            scope: scope,
            entries: entriesByScope[scope.key]!,
          ),
      ],
    ),
    issues: issues,
  );
}

bool _sameScope(
  AnalyticsIdControlPublicationScope left,
  AnalyticsIdControlPublicationScope right,
) =>
    left.selector.key == right.selector.key &&
    left.measurementSurfaceId == right.measurementSurfaceId &&
    left.routePlanClosureDigest == right.routePlanClosureDigest &&
    left.finalTargetNeutralDraftDigest == right.finalTargetNeutralDraftDigest;

bool _sameReservation(
  AnalyticsIdPresentationReservation left,
  AnalyticsIdPresentationReservation right,
) =>
    left.generatedPresentationReferenceId ==
        right.generatedPresentationReferenceId &&
    left.nodeCodeIdentityId == right.nodeCodeIdentityId &&
    left.canonicalNodeTokenId == right.canonicalNodeTokenId &&
    left.artifactOccurrenceEdgeToken == right.artifactOccurrenceEdgeToken &&
    left.presentationLineageId == right.presentationLineageId &&
    left.displayMetadataRef == right.displayMetadataRef &&
    left.presentationRouteCarrier == right.presentationRouteCarrier &&
    left.presentationRouteFingerprint == right.presentationRouteFingerprint;

bool _matchesPresentationRoute(
  AnalyticsIdPresentationReservation reservation,
  AnalyticsIdControlPublicationScope scope,
) {
  final expectedCarrier =
      MeasurementPublicationRouteCarrierV1.derivePresentation(
    routeDraftClosureDigest: scope.routePlanClosureDigest,
    artifactOccurrenceEdgeToken: reservation.artifactOccurrenceEdgeToken,
    generatedPresentationReferenceId:
        reservation.generatedPresentationReferenceId,
  ).value;
  if (reservation.presentationRouteCarrier != expectedCarrier) return false;
  return reservation.presentationRouteFingerprint ==
      OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
        expectedCarrier,
      ).fingerprint;
}

List<AnalyticsIdControlEntry> _sortedUniqueEntries(
  Iterable<AnalyticsIdControlEntry> values,
) {
  final byReservation = <String, AnalyticsIdControlEntry>{};
  for (final value in values) {
    final key = value.presentationReservation.replacementKey;
    final previous = byReservation[key];
    if (previous != null) {
      throw ArgumentError(
        'One presentation reservation cannot be repeated.',
      );
    }
    byReservation[key] = value;
  }
  if (byReservation.length > kMaximumMeasurementPublicationRuntimeRouteCount) {
    throw ArgumentError(
      'A control publication exceeds the Measurement route limit.',
    );
  }
  final result = byReservation.values.toList()
    ..sort(
      (left, right) => left.presentationReservation.sortKey.compareTo(
        right.presentationReservation.sortKey,
      ),
    );
  return List.unmodifiable(result);
}

List<AnalyticsIdControlPublication> _sortedUniquePublications(
  Iterable<AnalyticsIdControlPublication> values,
) {
  final bySelector = <String, AnalyticsIdControlPublication>{};
  for (final value in values) {
    final previous = bySelector[value.scope.key];
    if (previous != null) {
      throw ArgumentError('A control output cannot repeat one selector.');
    }
    bySelector[value.scope.key] = value;
  }
  final result = bySelector.values.toList()
    ..sort((left, right) => left.scope.key.compareTo(right.scope.key));
  return List.unmodifiable(result);
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?> _list(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List) throw FormatException('$path.$key must be a list.');
  return List<Object?>.unmodifiable(value);
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String) throw FormatException('$path.$key must be a string.');
  return value;
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer.');
  return value;
}

void _exactKeys(Map<String, Object?> json, Set<String> expected, String path) {
  if (json.length == expected.length &&
      json.keys.toSet().containsAll(expected)) {
    return;
  }
  throw FormatException('$path has an unexpected key set.');
}
