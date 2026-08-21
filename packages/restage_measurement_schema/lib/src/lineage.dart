import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';

/// One endpoint in a lineage transition.
final class LineageEndpointV1 extends CanonicalValue {
  /// Creates an occurrence-to-lineage endpoint.
  const LineageEndpointV1({
    required this.occurrenceId,
    required this.lineageId,
  });

  /// Decodes a strict nested lineage endpoint object.
  factory LineageEndpointV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'lineageId', 'occurrenceId'},
      requiredKeys: const {'kind', 'lineageId', 'occurrenceId'},
      path: 'lineageEndpoint',
    );
    if (reader.string('kind') != 'lineageEndpoint') {
      throw const CanonicalFormatException(
        'lineageEndpoint.kind must be "lineageEndpoint"',
      );
    }
    return _constructLineage(
      'lineageEndpoint',
      () => LineageEndpointV1(
        occurrenceId: CanonicalDigest(reader.string('occurrenceId')),
        lineageId: PointLineageId(reader.string('lineageId')),
      ),
    );
  }

  final CanonicalDigest occurrenceId;
  final PointLineageId lineageId;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'lineageEndpoint',
        'lineageId': lineageId.value,
        'occurrenceId': occurrenceId.hex,
      };
}

/// Exhaustive legal transition operations.
enum LineageOperation {
  continueLineage('continue'),
  create('create'),
  retire('retire'),
  split('split'),
  merge('merge');

  const LineageOperation(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;
}

/// Authority under which continuity was accepted.
enum LineageTransitionAuthority {
  exactToken('exactToken'),
  reviewedProposal('reviewedProposal'),
  explicit('explicit');

  const LineageTransitionAuthority(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;
}

/// One reviewed transition between exact published point occurrences.
final class LineageTransitionV1 extends CanonicalDocument {
  /// Creates a transition and enforces operation-specific arity/continuity.
  LineageTransitionV1({
    required this.transitionId,
    required this.publishedSurfaceRevisionId,
    required this.operation,
    required this.authority,
    required List<LineageEndpointV1> prior,
    required List<LineageEndpointV1> next,
  })  : prior = _sortedUniqueEndpoints(prior, 'prior endpoints'),
        next = _sortedUniqueEndpoints(next, 'next endpoints') {
    switch (operation) {
      case LineageOperation.continueLineage:
        if (this.prior.length != 1 ||
            this.next.length != 1 ||
            this.prior.single.lineageId != this.next.single.lineageId) {
          throw ArgumentError(
            'Continue must be exactly 1→1 and preserve the lineage',
          );
        }
      case LineageOperation.create:
        if (this.prior.isNotEmpty || this.next.length != 1) {
          throw ArgumentError('Create must be exactly 0→1');
        }
      case LineageOperation.retire:
        if (this.prior.length != 1 || this.next.isNotEmpty) {
          throw ArgumentError('Retire must be exactly 1→0');
        }
      case LineageOperation.split:
        if (this.prior.length != 1 || this.next.length < 2) {
          throw ArgumentError(
              'Split must be exactly 1→N where N is at least 2');
        }
        final successorLineages =
            this.next.map((endpoint) => endpoint.lineageId.value).toSet();
        if (successorLineages.length != this.next.length) {
          throw ArgumentError(
            'Every split successor must have a unique lineage',
          );
        }
      case LineageOperation.merge:
        if (this.prior.length < 2 || this.next.length != 1) {
          throw ArgumentError(
              'Merge must be exactly N→1 where N is at least 2');
        }
        final oldLineages =
            this.prior.map((endpoint) => endpoint.lineageId).toSet();
        if (oldLineages.length != this.prior.length) {
          throw ArgumentError(
            'Merge predecessors must have distinct lineages',
          );
        }
        if (authority != LineageTransitionAuthority.explicit) {
          throw ArgumentError(
            'Merge requires explicit authority',
          );
        }
    }
  }

  /// Decodes byte-exact canonical lineage-transition JSON.
  factory LineageTransitionV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        LineageTransitionV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'lineageTransition',
      );

  /// Decodes a strict nested lineage-transition object.
  factory LineageTransitionV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'authority',
        'kind',
        'next',
        'operation',
        'prior',
        'publishedSurfaceRevisionId',
        'schemaVersion',
        'transitionId',
      },
      requiredKeys: const {
        'authority',
        'kind',
        'next',
        'operation',
        'prior',
        'publishedSurfaceRevisionId',
        'schemaVersion',
        'transitionId',
      },
      path: 'lineageTransition',
    );
    validateCanonicalDocument(reader, expectedKind: 'lineageTransition');
    return _constructLineage(
      'lineageTransition',
      () => LineageTransitionV1(
        transitionId: LineageTransitionId(reader.string('transitionId')),
        publishedSurfaceRevisionId: SurfaceRevisionId(
          reader.string('publishedSurfaceRevisionId'),
        ),
        operation: _lineageOperationFromWire(reader.string('operation')),
        authority: _lineageAuthorityFromWire(reader.string('authority')),
        prior: reader
            .list('prior')
            .map(
              (value) => LineageEndpointV1.fromJson(
                requireCanonicalObject(value, 'prior[]'),
              ),
            )
            .toList(),
        next: reader
            .list('next')
            .map(
              (value) => LineageEndpointV1.fromJson(
                requireCanonicalObject(value, 'next[]'),
              ),
            )
            .toList(),
      ),
    );
  }

  final LineageTransitionId transitionId;
  final SurfaceRevisionId publishedSurfaceRevisionId;
  final LineageOperation operation;
  final LineageTransitionAuthority authority;
  final List<LineageEndpointV1> prior;
  final List<LineageEndpointV1> next;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.lineageTransition;

  @override
  Map<String, Object?> toJson() => {
        'authority': authority.wireName,
        'kind': 'lineageTransition',
        'next': [for (final endpoint in next) endpoint.toJson()],
        'operation': operation.wireName,
        'prior': [for (final endpoint in prior) endpoint.toJson()],
        'publishedSurfaceRevisionId': publishedSurfaceRevisionId.value,
        'schemaVersion': kMeasurementSchemaVersion,
        'transitionId': transitionId.value,
      };
}

/// Validates the complete accepted set of occurrence lineage transitions.
///
/// The validator uses endpoint-claim indexes and a depth-first graph walk, so
/// it runs in O(T + M) time and O(M) space for [transitions] and their endpoint
/// mentions. Producers should call it for every complete transition set before
/// publishing a manifest or lineage closure.
void validateLineageTransitionGraph(List<LineageTransitionV1> transitions) {
  final transitionIds = <String>{};
  final lineageByOccurrence = <String, String>{};
  final priorTransitionByOccurrence = <String, String>{};
  final nextTransitionByOccurrence = <String, String>{};
  final priorOccurrenceByPublicationLineage = <String, String>{};
  final nextOccurrenceByPublicationLineage = <String, String>{};
  final edges = <String, Set<String>>{};

  void claimEndpoints({
    required LineageTransitionV1 transition,
    required List<LineageEndpointV1> endpoints,
    required bool isPrior,
  }) {
    final transitionByOccurrence =
        isPrior ? priorTransitionByOccurrence : nextTransitionByOccurrence;
    final occurrenceByPublicationLineage = isPrior
        ? priorOccurrenceByPublicationLineage
        : nextOccurrenceByPublicationLineage;
    final side = isPrior ? 'prior' : 'next';
    for (final endpoint in endpoints) {
      final occurrenceId = endpoint.occurrenceId.hex;
      final lineageId = endpoint.lineageId.value;
      final claimedLineage = lineageByOccurrence[occurrenceId];
      if (claimedLineage != null && claimedLineage != lineageId) {
        throw ArgumentError(
          'Every occurrence ID must have exactly one lineage',
        );
      }
      lineageByOccurrence[occurrenceId] = lineageId;

      if (transitionByOccurrence.containsKey(occurrenceId)) {
        throw ArgumentError(
          'An occurrence may appear at most once as a $side endpoint',
        );
      }
      transitionByOccurrence[occurrenceId] = transition.transitionId.value;

      final publicationLineageKey =
          '${transition.publishedSurfaceRevisionId.value}\u0000$lineageId';
      if (occurrenceByPublicationLineage.containsKey(publicationLineageKey)) {
        throw ArgumentError(
          'A lineage may appear at most once as a $side endpoint in one '
          'publication',
        );
      }
      occurrenceByPublicationLineage[publicationLineageKey] = occurrenceId;
    }
  }

  for (final transition in transitions) {
    if (!transitionIds.add(transition.transitionId.value)) {
      throw ArgumentError('Lineage transition IDs must be unique');
    }
    claimEndpoints(
      transition: transition,
      endpoints: transition.prior,
      isPrior: true,
    );
    claimEndpoints(
      transition: transition,
      endpoints: transition.next,
      isPrior: false,
    );
    for (final prior in transition.prior) {
      for (final next in transition.next) {
        edges.putIfAbsent(prior.occurrenceId.hex, () => <String>{}).add(
              next.occurrenceId.hex,
            );
      }
    }
  }

  final visiting = <String>{};
  final visited = <String>{};
  void visit(String occurrenceId) {
    if (visiting.contains(occurrenceId)) {
      throw ArgumentError('Lineage transition graph must be acyclic');
    }
    if (!visited.add(occurrenceId)) return;
    visiting.add(occurrenceId);
    for (final next in edges[occurrenceId] ?? const <String>{}) {
      visit(next);
    }
    visiting.remove(occurrenceId);
  }

  for (final occurrenceId in lineageByOccurrence.keys) {
    visit(occurrenceId);
  }
}

List<LineageEndpointV1> _sortedUniqueEndpoints(
  List<LineageEndpointV1> values,
  String label,
) {
  final copy = values.toList()
    ..sort((a, b) => a.occurrenceId.hex.compareTo(b.occurrenceId.hex));
  String? prior;
  for (final endpoint in copy) {
    if (endpoint.occurrenceId.hex == prior) {
      throw ArgumentError('$label must have unique occurrence IDs');
    }
    prior = endpoint.occurrenceId.hex;
  }
  return List.unmodifiable(copy);
}

LineageOperation _lineageOperationFromWire(String value) => _wireEnum(
      LineageOperation.values,
      value,
      (entry) => entry.wireName,
      'lineage operation',
    );

LineageTransitionAuthority _lineageAuthorityFromWire(String value) => _wireEnum(
      LineageTransitionAuthority.values,
      value,
      (entry) => entry.wireName,
      'lineage transition authority',
    );

T _wireEnum<T>(
  List<T> values,
  String value,
  String Function(T) wireName,
  String label,
) {
  for (final entry in values) {
    if (wireName(entry) == value) return entry;
  }
  throw CanonicalFormatException('Unknown $label "$value"');
}

T _constructLineage<T>(String path, T Function() create) {
  try {
    return create();
  } catch (error) {
    if (error is! ArgumentError) rethrow;
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}
