import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/delivery_calendar.dart';
import 'package:restage_measurement_schema/src/delivery_identity.dart';
import 'package:restage_measurement_schema/src/experiment_authoring.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';

const int _routingDocumentSchemaVersion = 2;

/// The schema version and digest of exact retained routing document bytes.
final class ExactRoutingDocumentRefV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Names a current V2 document without changing its hash authority.
  ExactRoutingDocumentRefV1({
    required this.schemaVersion,
    required this.canonicalDigest,
  }) {
    if (schemaVersion != _routingDocumentSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Expected routing document version 2',
      );
    }
  }

  /// Decodes exact canonical reference bytes.
  factory ExactRoutingDocumentRefV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        ExactRoutingDocumentRefV1.fromJson,
        'exactRoutingDocumentRef',
      );

  /// Decodes a closed exact document reference.
  factory ExactRoutingDocumentRefV1.fromJson(Map<String, Object?> json) {
    final reader = _reader(
      json,
      'exactRoutingDocumentRef',
      const {'schemaVersion', 'canonicalDigest'},
    );
    return _construct(
      'exactRoutingDocumentRef',
      () => ExactRoutingDocumentRefV1(
        schemaVersion: reader.integer('schemaVersion'),
        canonicalDigest: CanonicalDigest(reader.string('canonicalDigest')),
      ),
    );
  }

  /// Schema version of the referenced original document.
  final int schemaVersion;

  /// Digest under the referenced document's fixed hash domain.
  final CanonicalDigest canonicalDigest;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'exactRoutingDocumentRef',
        'schemaVersion': schemaVersion,
        'canonicalDigest': canonicalDigest.hex,
      };
}

/// The exact owner, ordinal and digest of one immutable delivery policy.
final class DeliveryPolicyRevisionRefV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Requires a positive portable ordinal and a bounded revision identity.
  DeliveryPolicyRevisionRefV1({
    required this.scope,
    required this.ordinal,
    required this.canonicalPolicyDigest,
    required this.revisionId,
  }) {
    _requirePositivePortable(ordinal, 'ordinal');
    AuthorityRevisionId(revisionId);
  }

  /// Decodes byte-exact canonical policy-reference bytes.
  factory DeliveryPolicyRevisionRefV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyRevisionRefV1.fromJson,
        'deliveryPolicyRevisionRef',
      );

  /// Decodes one closed immutable policy reference.
  factory DeliveryPolicyRevisionRefV1.fromJson(Map<String, Object?> json) {
    final reader = _reader(
      json,
      'deliveryPolicyRevisionRef',
      const {'scope', 'ordinal', 'canonicalPolicyDigest', 'revisionId'},
    );
    return _construct(
      'deliveryPolicyRevisionRef',
      () => DeliveryPolicyRevisionRefV1(
        scope: DeliveryPolicyScopeV1.fromJson(reader.object('scope')),
        ordinal: reader.integer('ordinal'),
        canonicalPolicyDigest:
            CanonicalDigest(reader.string('canonicalPolicyDigest')),
        revisionId: reader.string('revisionId'),
      ),
    );
  }

  /// Exact policy owner and family.
  final DeliveryPolicyScopeV1 scope;

  /// Positive portable revision ordinal.
  final int ordinal;

  /// Digest of the original canonical policy bytes.
  final CanonicalDigest canonicalPolicyDigest;

  /// Immutable revision identity in the bounded lowercase identifier grammar.
  final String revisionId;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyRevisionRef',
        'scope': scope.toJson(),
        'ordinal': ordinal,
        'canonicalPolicyDigest': canonicalPolicyDigest.hex,
        'revisionId': revisionId,
      };
}

/// An exact selected document qualified by its enclosing policy revision.
final class DeliveryPolicyDocumentSelectionV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Retains the selected document's scope through its policy revision.
  const DeliveryPolicyDocumentSelectionV1({
    required this.policyRevision,
    required this.documentRef,
  });

  /// Decodes byte-exact canonical selected-document bytes.
  factory DeliveryPolicyDocumentSelectionV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyDocumentSelectionV1.fromJson,
        'deliveryPolicyDocumentSelection',
      );

  /// Decodes one closed selection without interpreting policy authority.
  factory DeliveryPolicyDocumentSelectionV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = _reader(
      json,
      'deliveryPolicyDocumentSelection',
      const {'policyRevision', 'documentRef'},
    );
    return DeliveryPolicyDocumentSelectionV1(
      policyRevision:
          DeliveryPolicyRevisionRefV1.fromJson(reader.object('policyRevision')),
      documentRef:
          ExactRoutingDocumentRefV1.fromJson(reader.object('documentRef')),
    );
  }

  /// Enclosing immutable policy identity, including its exact scope.
  final DeliveryPolicyRevisionRefV1 policyRevision;

  /// Exact selected original document identity.
  final ExactRoutingDocumentRefV1 documentRef;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyDocumentSelection',
        'policyRevision': policyRevision.toJson(),
        'documentRef': documentRef.toJson(),
      };
}

/// One complete original document and its civil activation time.
final class DeliveryPolicySnapshotInputV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicySnapshotInputV1({
    required this.effectiveFromLocal,
    required List<int> documentCanonicalBytes,
  }) : _documentCanonicalBytes = _canonicalObjectBytes(documentCanonicalBytes);

  factory DeliveryPolicySnapshotInputV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicySnapshotInput',
      const {'documentCanonicalBytes'},
      optional: const {'effectiveFromLocal'},
    );
    final start = r.optionalObject('effectiveFromLocal');
    return DeliveryPolicySnapshotInputV1(
      effectiveFromLocal:
          start == null ? null : LocalCivilDateTimeV1.fromJson(start),
      documentCanonicalBytes: _readBase64(r.string('documentCanonicalBytes')),
    );
  }

  final LocalCivilDateTimeV1? effectiveFromLocal;
  final Uint8List _documentCanonicalBytes;
  Uint8List get documentCanonicalBytes =>
      Uint8List.fromList(_documentCanonicalBytes);

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicySnapshotInput',
        'documentCanonicalBytes': base64Encode(_documentCanonicalBytes),
        if (effectiveFromLocal != null)
          'effectiveFromLocal': effectiveFromLocal!.toJson(),
      };
}

/// A whole policy plan; the policy owner validates each retained document.
final class DeliveryPolicyPlanV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyPlanV1({
    required this.scope,
    required List<DeliveryPolicySnapshotInputV1> snapshots,
  }) : snapshots = List.unmodifiable(snapshots) {
    if (snapshots.isEmpty || snapshots.first.effectiveFromLocal != null) {
      throw ArgumentError('A policy requires a null-start baseline');
    }
    LocalCivilDateTimeV1? previous;
    for (var i = 1; i < snapshots.length; i++) {
      final start = snapshots[i].effectiveFromLocal;
      if (start == null ||
          (previous != null && start.compareTo(previous) <= 0)) {
        throw ArgumentError(
          'Future snapshots must have strictly increasing civil starts',
        );
      }
      previous = start;
    }
  }

  factory DeliveryPolicyPlanV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyPlanV1.fromJson,
        'deliveryPolicyPlan',
      );
  factory DeliveryPolicyPlanV1.fromJson(Map<String, Object?> json) {
    final r = _reader(json, 'deliveryPolicyPlan', const {'scope', 'snapshots'});
    return _construct(
      'deliveryPolicyPlan',
      () => DeliveryPolicyPlanV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        snapshots: [
          for (final value in r.list('snapshots'))
            DeliveryPolicySnapshotInputV1.fromJson(
              requireCanonicalObject(value, 'snapshots[]'),
            ),
        ],
      ),
    );
  }

  final DeliveryPolicyScopeV1 scope;
  final List<DeliveryPolicySnapshotInputV1> snapshots;
  CanonicalDigest get digest =>
      _managementDigest('delivery-policy-plan', canonicalBytes);

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyPlan',
        'scope': scope.toJson(),
        'snapshots': [for (final s in snapshots) s.toJson()],
      };
}

abstract base class _DeliveryScopeRequest extends CanonicalValue
    implements ImmutableCanonicalDocument {
  const _DeliveryScopeRequest(this.scope, this._kind);
  final DeliveryPolicyScopeV1 scope;
  final String _kind;
  @override
  Map<String, Object?> toJson() => {'kind': _kind, 'scope': scope.toJson()};
}

final class DeliveryPolicyReadRequestV1 extends _DeliveryScopeRequest {
  const DeliveryPolicyReadRequestV1({required DeliveryPolicyScopeV1 scope})
      : super(scope, 'deliveryPolicyReadRequest');
  factory DeliveryPolicyReadRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyReadRequestV1.fromJson,
        'deliveryPolicyReadRequest',
      );
  factory DeliveryPolicyReadRequestV1.fromJson(Map<String, Object?> json) =>
      DeliveryPolicyReadRequestV1(
        scope: DeliveryPolicyScopeV1.fromJson(
          _reader(json, 'deliveryPolicyReadRequest', const {'scope'})
              .object('scope'),
        ),
      );
}

final class DeliveryPolicyTimelineRequestV1 extends _DeliveryScopeRequest {
  const DeliveryPolicyTimelineRequestV1({required DeliveryPolicyScopeV1 scope})
      : super(scope, 'deliveryPolicyTimelineRequest');
  factory DeliveryPolicyTimelineRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyTimelineRequestV1.fromJson,
        'deliveryPolicyTimelineRequest',
      );
  factory DeliveryPolicyTimelineRequestV1.fromJson(Map<String, Object?> json) =>
      DeliveryPolicyTimelineRequestV1(
        scope: DeliveryPolicyScopeV1.fromJson(
          _reader(json, 'deliveryPolicyTimelineRequest', const {'scope'})
              .object('scope'),
        ),
      );
}

final class DeliveryPolicyHistoryRequestV1 extends _DeliveryScopeRequest {
  DeliveryPolicyHistoryRequestV1(
      {required DeliveryPolicyScopeV1 scope, this.beforeOrdinal, this.pageSize})
      : super(scope, 'deliveryPolicyHistoryRequest') {
    if (beforeOrdinal != null)
      _requirePositivePortable(beforeOrdinal!, 'beforeOrdinal');
    if (pageSize != null) {
      _requirePositivePortable(pageSize!, 'pageSize');
      if (pageSize == kMaximumPortableJsonInteger)
        throw ArgumentError('History page size requires room for continuation');
    }
  }

  /// Returns only immutable ordinals strictly earlier than this one.
  final int? beforeOrdinal;

  /// A caller-selected page size; absence requests the complete history.
  final int? pageSize;
  factory DeliveryPolicyHistoryRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyHistoryRequestV1.fromJson,
        'deliveryPolicyHistoryRequest',
      );
  factory DeliveryPolicyHistoryRequestV1.fromJson(Map<String, Object?> json) {
    final r = _reader(json, 'deliveryPolicyHistoryRequest', const {'scope'},
        optional: const {'beforeOrdinal', 'pageSize'});
    return _construct(
        'deliveryPolicyHistoryRequest',
        () => DeliveryPolicyHistoryRequestV1(
            scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
            beforeOrdinal: r.optionalInteger('beforeOrdinal'),
            pageSize: r.optionalInteger('pageSize')));
  }
  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        if (beforeOrdinal != null) 'beforeOrdinal': beforeOrdinal,
        if (pageSize != null) 'pageSize': pageSize
      };
}

/// One coherent current head, or an admitted scope with no published policy.
final class DeliveryPolicyReadV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyReadV1({
    required this.scope,
    this.rootPresent = true,
    this.headId,
    this.revision,
    List<int>? policyCanonicalBytes,
    this.publishedAtMicros,
  }) : _policyCanonicalBytes = policyCanonicalBytes == null
            ? null
            : _canonicalObjectBytes(policyCanonicalBytes) {
    final present = revision != null;
    if (!rootPresent && (!scope.root.isPlacement || present)) {
      throw ArgumentError('Only an absent placement has no retained root');
    }
    if ((headId != null) != present ||
        (_policyCanonicalBytes != null) != present ||
        (publishedAtMicros != null) != present ||
        (present && revision!.scope != scope)) {
      throw ArgumentError(
        'A policy read carries the complete head authority or none',
      );
    }
    if (headId != null) _requirePositivePortable(headId!, 'headId');
    if (publishedAtMicros != null) {
      _requirePositivePortable(publishedAtMicros!, 'publishedAtMicros');
    }
  }
  factory DeliveryPolicyReadV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyReadV1.fromJson,
        'deliveryPolicyRead',
      );
  factory DeliveryPolicyReadV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyRead',
      const {
        'scope',
        'rootPresent',
      },
      optional: const {
        'headId',
        'revision',
        'policyCanonicalBytes',
        'publishedAtMicros',
      },
    );
    final ref = r.optionalObject('revision');
    final bytes = r.optionalString('policyCanonicalBytes');
    return _construct(
      'deliveryPolicyRead',
      () => DeliveryPolicyReadV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        rootPresent: r.boolean('rootPresent'),
        headId: r.optionalInteger('headId'),
        revision:
            ref == null ? null : DeliveryPolicyRevisionRefV1.fromJson(ref),
        policyCanonicalBytes: bytes == null ? null : _readBase64(bytes),
        publishedAtMicros: r.optionalInteger('publishedAtMicros'),
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final bool rootPresent;
  final int? headId;
  final DeliveryPolicyRevisionRefV1? revision;
  final Uint8List? _policyCanonicalBytes;
  Uint8List? get policyCanonicalBytes => _policyCanonicalBytes == null
      ? null
      : Uint8List.fromList(_policyCanonicalBytes);
  final int? publishedAtMicros;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyRead',
        'rootPresent': rootPresent,
        'scope': scope.toJson(),
        if (headId != null) 'headId': headId,
        if (revision != null) 'revision': revision!.toJson(),
        if (_policyCanonicalBytes != null)
          'policyCanonicalBytes': base64Encode(_policyCanonicalBytes),
        if (publishedAtMicros != null) 'publishedAtMicros': publishedAtMicros,
      };
}

final class DeliveryPolicyHistoryV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyHistoryV1(
      {required this.scope,
      required List<DeliveryPolicyReadV1> revisions,
      this.nextBeforeOrdinal})
      : revisions = List.unmodifiable(revisions) {
    int? prior;
    for (final item in revisions) {
      if (item.scope != scope ||
          item.revision == null ||
          (prior != null && item.revision!.ordinal >= prior)) {
        throw ArgumentError(
          'History carries descending exact revisions of one scope',
        );
      }
      prior = item.revision!.ordinal;
    }
    if (nextBeforeOrdinal != null &&
        (revisions.isEmpty ||
            nextBeforeOrdinal != revisions.last.revision!.ordinal)) {
      throw ArgumentError(
          'History continuation names the final returned ordinal');
    }
  }
  factory DeliveryPolicyHistoryV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyHistoryV1.fromJson,
        'deliveryPolicyHistory',
      );
  factory DeliveryPolicyHistoryV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
        json, 'deliveryPolicyHistory', const {'scope', 'revisions'},
        optional: const {'nextBeforeOrdinal'});
    return _construct(
      'deliveryPolicyHistory',
      () => DeliveryPolicyHistoryV1(
          scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
          revisions: [
            for (final value in r.list('revisions'))
              DeliveryPolicyReadV1.fromJson(
                requireCanonicalObject(value, 'revisions[]'),
              ),
          ],
          nextBeforeOrdinal: r.optionalInteger('nextBeforeOrdinal')),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final List<DeliveryPolicyReadV1> revisions;

  /// Exclusive ordinal cursor for the next page, absent on the final page.
  final int? nextBeforeOrdinal;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyHistory',
        'scope': scope.toJson(),
        'revisions': [for (final item in revisions) item.toJson()],
        if (nextBeforeOrdinal != null) 'nextBeforeOrdinal': nextBeforeOrdinal,
      };
}

/// A definite shadow is emitted only when the selector's audience/window prove it.
final class DeliveryPolicyTimelineRuleV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyTimelineRuleV1({
    required this.snapshotIndex,
    required this.routeId,
    required this.overlap,
  }) {
    if (snapshotIndex < 0 || snapshotIndex > kMaximumPortableJsonInteger) {
      throw ArgumentError('Invalid snapshot index');
    }
    AuthorityRevisionId(routeId);
    if (!const {'none', 'potentialOverlap', 'definitelyShadowed'}
        .contains(overlap)) {
      throw ArgumentError('Unknown overlap');
    }
  }
  factory DeliveryPolicyTimelineRuleV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyTimelineRule',
      const {'snapshotIndex', 'routeId', 'overlap'},
    );
    return _construct(
      'deliveryPolicyTimelineRule',
      () => DeliveryPolicyTimelineRuleV1(
        snapshotIndex: r.integer('snapshotIndex'),
        routeId: r.string('routeId'),
        overlap: r.string('overlap'),
      ),
    );
  }
  final int snapshotIndex;
  final String routeId;
  final String overlap;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyTimelineRule',
        'snapshotIndex': snapshotIndex,
        'routeId': routeId,
        'overlap': overlap,
      };
}

final class DeliveryPolicyTimelineV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyTimelineV1({
    required this.policy,
    this.plan,
    List<DeliveryPolicyTimelineRuleV1> rules = const [],
  }) : rules = List.unmodifiable(rules) {
    if ((plan != null) != (policy.revision != null) ||
        (plan != null && plan!.scope != policy.scope)) {
      throw ArgumentError('Timeline plan belongs to its exact policy');
    }
  }
  factory DeliveryPolicyTimelineV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyTimelineV1.fromJson,
        'deliveryPolicyTimeline',
      );
  factory DeliveryPolicyTimelineV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyTimeline',
      const {'policy', 'rules'},
      optional: const {'plan'},
    );
    final plan = r.optionalObject('plan');
    return _construct(
      'deliveryPolicyTimeline',
      () => DeliveryPolicyTimelineV1(
        policy: DeliveryPolicyReadV1.fromJson(r.object('policy')),
        plan: plan == null ? null : DeliveryPolicyPlanV1.fromJson(plan),
        rules: [
          for (final value in r.list('rules'))
            DeliveryPolicyTimelineRuleV1.fromJson(
              requireCanonicalObject(value, 'rules[]'),
            ),
        ],
      ),
    );
  }
  final DeliveryPolicyReadV1 policy;
  final DeliveryPolicyPlanV1? plan;
  final List<DeliveryPolicyTimelineRuleV1> rules;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyTimeline',
        'policy': policy.toJson(),
        if (plan != null) 'plan': plan!.toJson(),
        'rules': [for (final r in rules) r.toJson()],
      };
}

/// Explicit request facts for the ordinary selector; simulation never enrolls.
final class DeliverySimulationInputsV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliverySimulationInputsV1({
    required this.localNow,
    this.analyticsAnonymousId,
    List<int>? assignmentContextCanonicalBytes,
    List<int>? sdkBuiltInsCanonicalBytes,
  })  : _assignmentContextCanonicalBytes =
            assignmentContextCanonicalBytes == null
                ? null
                : _canonicalObjectBytes(assignmentContextCanonicalBytes),
        _sdkBuiltInsCanonicalBytes = sdkBuiltInsCanonicalBytes == null
            ? null
            : _canonicalObjectBytes(sdkBuiltInsCanonicalBytes) {
    if (analyticsAnonymousId != null && analyticsAnonymousId!.isEmpty) {
      throw ArgumentError('Anonymous id must be nonempty when present');
    }
  }
  factory DeliverySimulationInputsV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliverySimulationInputs',
      const {},
      optional: const {
        'localNow',
        'analyticsAnonymousId',
        'assignmentContextCanonicalBytes',
        'sdkBuiltInsCanonicalBytes',
      },
    );
    final time = r.optionalObject('localNow');
    final context = r.optionalString('assignmentContextCanonicalBytes');
    final builtIns = r.optionalString('sdkBuiltInsCanonicalBytes');
    return _construct(
      'deliverySimulationInputs',
      () => DeliverySimulationInputsV1(
        localNow: time == null ? null : LocalCivilDateTimeV1.fromJson(time),
        analyticsAnonymousId: r.optionalString('analyticsAnonymousId'),
        assignmentContextCanonicalBytes:
            context == null ? null : _readBase64(context),
        sdkBuiltInsCanonicalBytes:
            builtIns == null ? null : _readBase64(builtIns),
      ),
    );
  }
  final LocalCivilDateTimeV1? localNow;
  final String? analyticsAnonymousId;
  final Uint8List? _assignmentContextCanonicalBytes;
  final Uint8List? _sdkBuiltInsCanonicalBytes;
  Uint8List? get assignmentContextCanonicalBytes =>
      _assignmentContextCanonicalBytes == null
          ? null
          : Uint8List.fromList(_assignmentContextCanonicalBytes);
  Uint8List? get sdkBuiltInsCanonicalBytes => _sdkBuiltInsCanonicalBytes == null
      ? null
      : Uint8List.fromList(_sdkBuiltInsCanonicalBytes);
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliverySimulationInputs',
        if (localNow != null) 'localNow': localNow!.toJson(),
        if (analyticsAnonymousId != null)
          'analyticsAnonymousId': analyticsAnonymousId,
        if (_assignmentContextCanonicalBytes != null)
          'assignmentContextCanonicalBytes':
              base64Encode(_assignmentContextCanonicalBytes),
        if (_sdkBuiltInsCanonicalBytes != null)
          'sdkBuiltInsCanonicalBytes': base64Encode(_sdkBuiltInsCanonicalBytes),
      };
}

final class DeliveryPolicySimulationRequestV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  const DeliveryPolicySimulationRequestV1({
    required this.scope,
    required this.inputs,
  });
  factory DeliveryPolicySimulationRequestV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicySimulationRequestV1.fromJson,
        'deliveryPolicySimulationRequest',
      );
  factory DeliveryPolicySimulationRequestV1.fromJson(
    Map<String, Object?> json,
  ) {
    final r = _reader(
      json,
      'deliveryPolicySimulationRequest',
      const {'scope', 'inputs'},
    );
    return DeliveryPolicySimulationRequestV1(
      scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
      inputs: DeliverySimulationInputsV1.fromJson(r.object('inputs')),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final DeliverySimulationInputsV1 inputs;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicySimulationRequest',
        'scope': scope.toJson(),
        'inputs': inputs.toJson(),
      };
}

final class DeliveryPolicySimulationV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicySimulationV1({
    required this.scope,
    required this.reason,
    this.policySelection,
    this.actualPublication,
    this.routeId,
    this.allocationId,
    this.branch,
  }) {
    if (reason.isEmpty ||
        (policySelection != null &&
            policySelection!.policyRevision.scope != scope) ||
        (actualPublication != null &&
            actualPublication!.surface.target != scope.target)) {
      throw ArgumentError('Invalid simulation authority');
    }
  }
  factory DeliveryPolicySimulationV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicySimulationV1.fromJson,
        'deliveryPolicySimulation',
      );
  factory DeliveryPolicySimulationV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicySimulation',
      const {
        'scope',
        'reason',
      },
      optional: const {
        'policySelection',
        'actualPublication',
        'routeId',
        'allocationId',
        'branch',
      },
    );
    final selection = r.optionalObject('policySelection');
    final publication = r.optionalObject('actualPublication');
    return _construct(
      'deliveryPolicySimulation',
      () => DeliveryPolicySimulationV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        reason: r.string('reason'),
        policySelection: selection == null
            ? null
            : DeliveryPolicyDocumentSelectionV1.fromJson(selection),
        actualPublication: publication == null
            ? null
            : DeliveryPublicationReferenceV1.fromJson(publication),
        routeId: r.optionalString('routeId'),
        allocationId: r.optionalString('allocationId'),
        branch: r.optionalString('branch'),
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final String reason;
  final DeliveryPolicyDocumentSelectionV1? policySelection;
  final DeliveryPublicationReferenceV1? actualPublication;
  final String? routeId;
  final String? allocationId;
  final String? branch;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicySimulation',
        'scope': scope.toJson(),
        'reason': reason,
        if (policySelection != null)
          'policySelection': policySelection!.toJson(),
        if (actualPublication != null)
          'actualPublication': actualPublication!.toJson(),
        if (routeId != null) 'routeId': routeId,
        if (allocationId != null) 'allocationId': allocationId,
        if (branch != null) 'branch': branch,
      };
}

/// A picker scope or an exact stored publication's inverse fit report.
final class DeliveryPolicyFitReadRequestV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyFitReadRequestV1.forScope({
    required DeliveryPolicyScopeV1 this.scope,
    this.pageSize,
    this.cursor,
  }) : publication = null {
    _validatePage();
  }
  DeliveryPolicyFitReadRequestV1.forPublication({
    required DeliveryPublicationReferenceV1 this.publication,
    this.pageSize,
    this.cursor,
  }) : scope = null {
    _validatePage();
  }
  factory DeliveryPolicyFitReadRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyFitReadRequestV1.fromJson,
        'deliveryPolicyFitReadRequest',
      );
  factory DeliveryPolicyFitReadRequestV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyFitReadRequest',
      const {},
      optional: const {'scope', 'publication', 'pageSize', 'cursor'},
    );
    final scope = r.optionalObject('scope');
    final publication = r.optionalObject('publication');
    if ((scope == null) == (publication == null)) {
      throw const CanonicalFormatException(
        'Fit read names one scope or publication',
      );
    }
    return _construct(
        'deliveryPolicyFitReadRequest',
        () => scope != null
            ? DeliveryPolicyFitReadRequestV1.forScope(
                scope: DeliveryPolicyScopeV1.fromJson(scope),
                pageSize: r.optionalInteger('pageSize'),
                cursor: r.optionalString('cursor'),
              )
            : DeliveryPolicyFitReadRequestV1.forPublication(
                publication:
                    DeliveryPublicationReferenceV1.fromJson(publication!),
                pageSize: r.optionalInteger('pageSize'),
                cursor: r.optionalString('cursor'),
              ));
  }
  final DeliveryPolicyScopeV1? scope;
  final DeliveryPublicationReferenceV1? publication;

  /// A positive caller-selected page size; absence requests a complete report.
  final int? pageSize;

  /// Opaque continuation bound to this selector and its original authority cut.
  final String? cursor;
  void _validatePage() {
    if (pageSize != null) _requirePositivePortable(pageSize!, 'pageSize');
    if (cursor != null && (cursor!.isEmpty || pageSize == null)) {
      throw ArgumentError(
          'A continuation requires a nonempty cursor and page size');
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyFitReadRequest',
        if (scope != null) 'scope': scope!.toJson(),
        if (publication != null) 'publication': publication!.toJson(),
        if (pageSize != null) 'pageSize': pageSize,
        if (cursor != null) 'cursor': cursor,
      };
}

/// An exact fit verdict retained from the shared fit authority.
final class DeliveryPolicyFitEntryV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyFitEntryV1({
    required this.scope,
    required this.publication,
    required List<int> verdictCanonicalBytes,
  }) : _verdictCanonicalBytes = _canonicalObjectBytes(verdictCanonicalBytes) {
    if (scope.target != publication.surface.target) {
      throw ArgumentError('Fit entry target differs');
    }
  }
  factory DeliveryPolicyFitEntryV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyFitEntry',
      const {'scope', 'publication', 'verdictCanonicalBytes'},
    );
    return _construct(
      'deliveryPolicyFitEntry',
      () => DeliveryPolicyFitEntryV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        publication: DeliveryPublicationReferenceV1.fromJson(
          r.object('publication'),
        ),
        verdictCanonicalBytes: _readBase64(r.string('verdictCanonicalBytes')),
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final DeliveryPublicationReferenceV1 publication;
  final Uint8List _verdictCanonicalBytes;
  Uint8List get verdictCanonicalBytes =>
      Uint8List.fromList(_verdictCanonicalBytes);
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyFitEntry',
        'scope': scope.toJson(),
        'publication': publication.toJson(),
        'verdictCanonicalBytes': base64Encode(_verdictCanonicalBytes),
      };
}

final class DeliveryPolicyFitReadV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyFitReadV1({
    required this.request,
    required this.authorityDigest,
    required List<DeliveryPolicyFitEntryV1> entries,
    this.refusalCode,
    this.nextCursor,
  }) : entries = List.unmodifiable(entries) {
    if (request.pageSize != null && entries.length > request.pageSize!) {
      throw ArgumentError('Fit page exceeds the requested size');
    }
    if (nextCursor != null &&
        (nextCursor!.isEmpty || request.pageSize == null || entries.isEmpty)) {
      throw ArgumentError(
          'A fit continuation requires a nonempty bounded page');
    }
    for (final entry in entries) {
      if ((request.scope != null && entry.scope != request.scope) ||
          (request.publication != null &&
              entry.publication != request.publication)) {
        throw ArgumentError('Fit page differs from its requested selector');
      }
    }
  }
  factory DeliveryPolicyFitReadV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyFitReadV1.fromJson,
        'deliveryPolicyFitRead',
      );
  factory DeliveryPolicyFitReadV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyFitRead',
      const {'request', 'authorityDigest', 'entries'},
      optional: const {'refusalCode', 'nextCursor'},
    );
    return _construct(
      'deliveryPolicyFitRead',
      () => DeliveryPolicyFitReadV1(
        request: DeliveryPolicyFitReadRequestV1.fromJson(r.object('request')),
        authorityDigest: CanonicalDigest(r.string('authorityDigest')),
        entries: [
          for (final value in r.list('entries'))
            DeliveryPolicyFitEntryV1.fromJson(
              requireCanonicalObject(value, 'entries[]'),
            ),
        ],
        refusalCode: r.optionalString('refusalCode'),
        nextCursor: r.optionalString('nextCursor'),
      ),
    );
  }
  final DeliveryPolicyFitReadRequestV1 request;
  final CanonicalDigest authorityDigest;
  final List<DeliveryPolicyFitEntryV1> entries;
  final String? refusalCode;
  final String? nextCursor;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyFitRead',
        'request': request.toJson(),
        'authorityDigest': authorityDigest.hex,
        'entries': [for (final e in entries) e.toJson()],
        if (refusalCode != null) 'refusalCode': refusalCode,
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Safe public references and warnings for one affected experiment metric.
final class DeliveryMeasurementSourceImpactV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryMeasurementSourceImpactV1({
    required this.experimentReference,
    required this.experimentName,
    required this.metricName,
    required this.metricBindingReference,
    required List<DeliveryPublicationReferenceV1> affectedPublications,
    required this.warningCode,
  }) : affectedPublications = List.unmodifiable(affectedPublications) {
    if (experimentName.isEmpty || metricName.isEmpty) {
      throw ArgumentError('Affected authorities require names');
    }
    if (affectedPublications
        .any((p) => p.surface.target != experimentReference.target)) {
      throw ArgumentError(
        'Affected publications belong to the experiment target',
      );
    }
    _requireWarning(warningCode);
  }
  factory DeliveryMeasurementSourceImpactV1.fromJson(
    Map<String, Object?> json,
  ) {
    final r = _reader(json, 'deliveryMeasurementSourceImpact', const {
      'experimentReference',
      'experimentName',
      'metricName',
      'metricBindingReference',
      'affectedPublications',
      'warningCode',
    });
    return _construct(
      'deliveryMeasurementSourceImpact',
      () => DeliveryMeasurementSourceImpactV1(
        experimentReference: ExperimentLiveReadReferenceV1.fromJson(
          r.object('experimentReference'),
        ),
        experimentName: r.string('experimentName'),
        metricName: r.string('metricName'),
        metricBindingReference:
            ExperimentExactMetricBindingReferenceV1.fromJson(
          r.object('metricBindingReference'),
          path: 'metricBindingReference',
        ),
        affectedPublications: [
          for (final p in r.list('affectedPublications'))
            DeliveryPublicationReferenceV1.fromJson(
              requireCanonicalObject(p, 'affectedPublications[]'),
            ),
        ],
        warningCode: r.string('warningCode'),
      ),
    );
  }
  final ExperimentLiveReadReferenceV1 experimentReference;
  final String experimentName;
  final String metricName;
  final ExperimentExactMetricBindingReferenceV1 metricBindingReference;
  final List<DeliveryPublicationReferenceV1> affectedPublications;
  final String warningCode;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryMeasurementSourceImpact',
        'experimentReference': experimentReference.toJson(),
        'experimentName': experimentName,
        'metricName': metricName,
        'metricBindingReference': metricBindingReference.toJson(),
        'affectedPublications': [
          for (final p in affectedPublications) p.toJson(),
        ],
        'warningCode': warningCode,
      };
}

/// Reviewed source loss for the exact candidate and expected live authority.
final class DeliveryMeasurementImpactReviewV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryMeasurementImpactReviewV1({
    required this.scope,
    required this.operation,
    this.candidatePolicy,
    this.expectedLivePolicy,
    List<DeliveryPublicationReferenceV1> candidatePublications = const [],
    List<DeliveryPublicationReferenceV1> expectedLivePublications = const [],
    List<DeliveryMeasurementSourceImpactV1> affectedSources = const [],
    required this.dependencyDigest,
  })  : candidatePublications = List.unmodifiable(candidatePublications),
        expectedLivePublications = List.unmodifiable(expectedLivePublications),
        affectedSources = List.unmodifiable(affectedSources) {
    if (!const {
      'policyPublish',
      'surfaceActivate',
      'surfaceRollback',
      'surfaceArchive',
      'surfaceKill',
      'surfaceFreeze',
    }.contains(operation)) {
      throw ArgumentError('Unknown live delivery operation');
    }
    if ((candidatePolicy != null && candidatePolicy!.scope != scope) ||
        (expectedLivePolicy != null && expectedLivePolicy!.scope != scope) ||
        candidatePublications.any((p) => p.surface.target != scope.target) ||
        expectedLivePublications.any((p) => p.surface.target != scope.target) ||
        affectedSources
            .any((s) => s.experimentReference.target != scope.target)) {
      throw ArgumentError('Impact authorities must share the exact target');
    }
  }
  factory DeliveryMeasurementImpactReviewV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decodeCanonical(
        bytes,
        DeliveryMeasurementImpactReviewV1.fromJson,
        'deliveryMeasurementImpactReview',
      );
  factory DeliveryMeasurementImpactReviewV1.fromJson(
    Map<String, Object?> json,
  ) {
    final r = _reader(
      json,
      'deliveryMeasurementImpactReview',
      const {
        'scope',
        'operation',
        'candidatePublications',
        'expectedLivePublications',
        'affectedSources',
        'dependencyDigest',
      },
      optional: const {
        'candidatePolicy',
        'expectedLivePolicy',
      },
    );
    final candidate = r.optionalObject('candidatePolicy');
    final live = r.optionalObject('expectedLivePolicy');
    return _construct(
      'deliveryMeasurementImpactReview',
      () => DeliveryMeasurementImpactReviewV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        operation: r.string('operation'),
        candidatePolicy: candidate == null
            ? null
            : DeliveryPolicyRevisionRefV1.fromJson(candidate),
        expectedLivePolicy:
            live == null ? null : DeliveryPolicyRevisionRefV1.fromJson(live),
        candidatePublications: [
          for (final p in r.list('candidatePublications'))
            DeliveryPublicationReferenceV1.fromJson(
              requireCanonicalObject(p, 'candidatePublications[]'),
            ),
        ],
        expectedLivePublications: [
          for (final p in r.list('expectedLivePublications'))
            DeliveryPublicationReferenceV1.fromJson(
              requireCanonicalObject(p, 'expectedLivePublications[]'),
            ),
        ],
        affectedSources: [
          for (final s in r.list('affectedSources'))
            DeliveryMeasurementSourceImpactV1.fromJson(
              requireCanonicalObject(s, 'affectedSources[]'),
            ),
        ],
        dependencyDigest: CanonicalDigest(r.string('dependencyDigest')),
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final String operation;
  final DeliveryPolicyRevisionRefV1? candidatePolicy;
  final DeliveryPolicyRevisionRefV1? expectedLivePolicy;
  final List<DeliveryPublicationReferenceV1> candidatePublications;
  final List<DeliveryPublicationReferenceV1> expectedLivePublications;
  final List<DeliveryMeasurementSourceImpactV1> affectedSources;
  final CanonicalDigest dependencyDigest;
  CanonicalDigest get digest =>
      _managementDigest('delivery-measurement-impact-review', canonicalBytes);
  List<String> get warningCodes => List.unmodifiable(
        affectedSources.map((s) => s.warningCode).toSet().toList()..sort(),
      );
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryMeasurementImpactReview',
        'scope': scope.toJson(),
        'operation': operation,
        if (candidatePolicy != null)
          'candidatePolicy': candidatePolicy!.toJson(),
        if (expectedLivePolicy != null)
          'expectedLivePolicy': expectedLivePolicy!.toJson(),
        'candidatePublications': [
          for (final p in candidatePublications) p.toJson(),
        ],
        'expectedLivePublications': [
          for (final p in expectedLivePublications) p.toJson(),
        ],
        'affectedSources': [for (final s in affectedSources) s.toJson()],
        'dependencyDigest': dependencyDigest.hex,
      };
}

/// Acknowledges only the reviewed warning set; it grants no render or deletion bypass.
final class DeliveryMeasurementImpactAcknowledgementV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryMeasurementImpactAcknowledgementV1({
    required this.reviewDigest,
    required List<String> warningCodes,
  }) : warningCodes = List.unmodifiable(warningCodes) {
    for (final code in warningCodes) {
      _requireWarning(code);
    }
    _requireSortedUnique(warningCodes, 'warningCodes');
  }
  factory DeliveryMeasurementImpactAcknowledgementV1.fromJson(
    Map<String, Object?> json,
  ) {
    final r = _reader(
      json,
      'deliveryMeasurementImpactAcknowledgement',
      const {'reviewDigest', 'warningCodes'},
    );
    return _construct(
      'deliveryMeasurementImpactAcknowledgement',
      () => DeliveryMeasurementImpactAcknowledgementV1(
        reviewDigest: CanonicalDigest(r.string('reviewDigest')),
        warningCodes: [
          for (final code in r.list('warningCodes'))
            requireCanonicalString(code, 'warningCodes[]'),
        ],
      ),
    );
  }
  final CanonicalDigest reviewDigest;
  final List<String> warningCodes;
  bool acknowledges(DeliveryMeasurementImpactReviewV1 review) =>
      reviewDigest == review.digest &&
      _sameStrings(warningCodes, review.warningCodes);
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryMeasurementImpactAcknowledgement',
        'reviewDigest': reviewDigest.hex,
        'warningCodes': warningCodes,
      };
}

/// The complete safe review for an identity-wide or cross-target mutation.
final class DeliveryMeasurementMutationReviewV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryMeasurementMutationReviewV1({
    required this.operation,
    required List<DeliveryMeasurementImpactReviewV1> reviews,
    required this.dependencyDigest,
    List<String> refusalCodes = const [],
  })  : reviews = List.unmodifiable(reviews),
        refusalCodes = List.unmodifiable(refusalCodes) {
    if (!const {
          'surfaceActivate',
          'surfaceRollback',
          'surfaceArchive',
          'surfaceKill',
          'surfaceFreeze',
        }.contains(operation) ||
        reviews.any((r) => r.operation != operation)) {
      throw ArgumentError(
          'Mutation reviews require one live surface operation');
    }
    _requireSortedUnique(
      reviews.map((r) => base64Encode(r.scope.canonicalBytes)).toList(),
      'reviews',
    );
    _requireSortedUnique(refusalCodes, 'refusalCodes');
  }

  factory DeliveryMeasurementMutationReviewV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decodeCanonical(
        bytes,
        DeliveryMeasurementMutationReviewV1.fromJson,
        'deliveryMeasurementMutationReview',
      );

  factory DeliveryMeasurementMutationReviewV1.fromJson(
    Map<String, Object?> json,
  ) {
    final r = _reader(json, 'deliveryMeasurementMutationReview', const {
      'operation',
      'reviews',
      'dependencyDigest',
      'refusalCodes',
    });
    return _construct(
      'deliveryMeasurementMutationReview',
      () => DeliveryMeasurementMutationReviewV1(
        operation: r.string('operation'),
        reviews: [
          for (final review in r.list('reviews'))
            DeliveryMeasurementImpactReviewV1.fromJson(
              requireCanonicalObject(review, 'reviews[]'),
            ),
        ],
        dependencyDigest: CanonicalDigest(r.string('dependencyDigest')),
        refusalCodes: [
          for (final code in r.list('refusalCodes'))
            requireCanonicalString(code, 'refusalCodes[]'),
        ],
      ),
    );
  }

  final String operation;
  final List<DeliveryMeasurementImpactReviewV1> reviews;
  final CanonicalDigest dependencyDigest;
  final List<String> refusalCodes;
  CanonicalDigest get digest =>
      _managementDigest('delivery-measurement-mutation-review', canonicalBytes);
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryMeasurementMutationReview',
        'operation': operation,
        'reviews': [for (final review in reviews) review.toJson()],
        'dependencyDigest': dependencyDigest.hex,
        'refusalCodes': refusalCodes,
      };
}

/// Binds one replayable mutation to its complete retained review and warnings.
final class DeliveryMeasurementMutationProceedV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryMeasurementMutationProceedV1({
    required this.operationId,
    required this.reviewDigest,
    List<DeliveryMeasurementImpactAcknowledgementV1> acknowledgements =
        const [],
  }) : acknowledgements = List.unmodifiable(acknowledgements) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(operationId)) {
      throw ArgumentError('Operation id must be a canonical v4 UUID');
    }
    _requireSortedUnique(
      acknowledgements.map((a) => a.reviewDigest.hex).toList(),
      'acknowledgements',
    );
  }

  factory DeliveryMeasurementMutationProceedV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decodeCanonical(
        bytes,
        DeliveryMeasurementMutationProceedV1.fromJson,
        'deliveryMeasurementMutationProceed',
      );

  factory DeliveryMeasurementMutationProceedV1.fromJson(
    Map<String, Object?> json,
  ) {
    final r = _reader(json, 'deliveryMeasurementMutationProceed', const {
      'operationId',
      'reviewDigest',
      'acknowledgements',
    });
    return _construct(
      'deliveryMeasurementMutationProceed',
      () => DeliveryMeasurementMutationProceedV1(
        operationId: r.string('operationId'),
        reviewDigest: CanonicalDigest(r.string('reviewDigest')),
        acknowledgements: [
          for (final acknowledgement in r.list('acknowledgements'))
            DeliveryMeasurementImpactAcknowledgementV1.fromJson(
              requireCanonicalObject(acknowledgement, 'acknowledgements[]'),
            ),
        ],
      ),
    );
  }

  final String operationId;
  final CanonicalDigest reviewDigest;
  final List<DeliveryMeasurementImpactAcknowledgementV1> acknowledgements;

  bool acknowledges(DeliveryMeasurementMutationReviewV1 review) {
    if (reviewDigest != review.digest || review.refusalCodes.isNotEmpty) {
      return false;
    }
    final warned =
        review.reviews.where((r) => r.warningCodes.isNotEmpty).toList();
    return warned.length == acknowledgements.length &&
        warned.every((r) => acknowledgements.any((a) => a.acknowledges(r)));
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryMeasurementMutationProceed',
        'operationId': operationId,
        'reviewDigest': reviewDigest.hex,
        'acknowledgements': [for (final a in acknowledgements) a.toJson()],
      };
}

final class DeliveryPolicyReviewRequestV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyReviewRequestV1({
    required this.scope,
    required this.expectedHeadOrdinal,
    required this.candidatePlan,
    required this.reason,
  }) {
    if (scope != candidatePlan.scope) {
      throw ArgumentError('Plan belongs to another scope');
    }
    if (expectedHeadOrdinal != null) {
      _requirePositivePortable(expectedHeadOrdinal!, 'expectedHeadOrdinal');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A review requires a reason');
    }
  }
  factory DeliveryPolicyReviewRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyReviewRequestV1.fromJson,
        'deliveryPolicyReviewRequest',
      );
  factory DeliveryPolicyReviewRequestV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyReviewRequest',
      const {'scope', 'candidatePlan', 'reason'},
      optional: const {'expectedHeadOrdinal'},
    );
    return _construct(
      'deliveryPolicyReviewRequest',
      () => DeliveryPolicyReviewRequestV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        expectedHeadOrdinal: r.optionalInteger('expectedHeadOrdinal'),
        candidatePlan: DeliveryPolicyPlanV1.fromJson(r.object('candidatePlan')),
        reason: r.string('reason'),
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final int? expectedHeadOrdinal;
  final DeliveryPolicyPlanV1 candidatePlan;
  final String reason;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyReviewRequest',
        'scope': scope.toJson(),
        if (expectedHeadOrdinal != null)
          'expectedHeadOrdinal': expectedHeadOrdinal,
        'candidatePlan': candidatePlan.toJson(),
        'reason': reason,
      };
}

final class DeliveryPolicyReviewRefV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  const DeliveryPolicyReviewRefV1({required this.scope, required this.digest});
  factory DeliveryPolicyReviewRefV1.fromJson(Map<String, Object?> json) {
    final r =
        _reader(json, 'deliveryPolicyReviewRef', const {'scope', 'digest'});
    return _construct(
      'deliveryPolicyReviewRef',
      () => DeliveryPolicyReviewRefV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        digest: CanonicalDigest(r.string('digest')),
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final CanonicalDigest digest;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyReviewRef',
        'scope': scope.toJson(),
        'digest': digest.hex,
      };
}

/// The frozen whole candidate, head expectation and dependency authority.
final class DeliveryPolicyReviewV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyReviewV1({
    required this.scope,
    required this.expectedHeadOrdinal,
    required this.candidatePlan,
    required this.candidateRevision,
    required this.reviewedAuthorityDigest,
    required this.measurementImpact,
    required this.reason,
    required this.reviewedAtMicros,
    List<String> refusalCodes = const [],
  }) : refusalCodes = List.unmodifiable(refusalCodes) {
    if (scope != candidatePlan.scope ||
        scope != candidateRevision.scope ||
        scope != measurementImpact.scope ||
        candidateRevision.ordinal != (expectedHeadOrdinal ?? 0) + 1) {
      throw ArgumentError('Review authorities disagree');
    }
    _requirePositivePortable(reviewedAtMicros, 'reviewedAtMicros');
    _requireSortedUnique(refusalCodes, 'refusalCodes');
  }
  factory DeliveryPolicyReviewV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyReviewV1.fromJson,
        'deliveryPolicyReview',
      );
  factory DeliveryPolicyReviewV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyReview',
      const {
        'scope',
        'candidatePlan',
        'candidateRevision',
        'reviewedAuthorityDigest',
        'measurementImpact',
        'reason',
        'reviewedAtMicros',
        'refusalCodes',
      },
      optional: const {
        'expectedHeadOrdinal',
      },
    );
    return _construct(
      'deliveryPolicyReview',
      () => DeliveryPolicyReviewV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        expectedHeadOrdinal: r.optionalInteger('expectedHeadOrdinal'),
        candidatePlan: DeliveryPolicyPlanV1.fromJson(r.object('candidatePlan')),
        candidateRevision: DeliveryPolicyRevisionRefV1.fromJson(
          r.object('candidateRevision'),
        ),
        reviewedAuthorityDigest:
            CanonicalDigest(r.string('reviewedAuthorityDigest')),
        measurementImpact: DeliveryMeasurementImpactReviewV1.fromJson(
          r.object('measurementImpact'),
        ),
        reason: r.string('reason'),
        reviewedAtMicros: r.integer('reviewedAtMicros'),
        refusalCodes: [
          for (final code in r.list('refusalCodes'))
            requireCanonicalString(code, 'refusalCodes[]'),
        ],
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final int? expectedHeadOrdinal;
  final DeliveryPolicyPlanV1 candidatePlan;
  final DeliveryPolicyRevisionRefV1 candidateRevision;
  final CanonicalDigest reviewedAuthorityDigest;
  final DeliveryMeasurementImpactReviewV1 measurementImpact;
  final String reason;
  final int reviewedAtMicros;
  final List<String> refusalCodes;
  CanonicalDigest get digest =>
      _managementDigest('delivery-policy-review', canonicalBytes);
  DeliveryPolicyReviewRefV1 get reviewRef =>
      DeliveryPolicyReviewRefV1(scope: scope, digest: digest);
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyReview',
        'scope': scope.toJson(),
        if (expectedHeadOrdinal != null)
          'expectedHeadOrdinal': expectedHeadOrdinal,
        'candidatePlan': candidatePlan.toJson(),
        'candidateRevision': candidateRevision.toJson(),
        'reviewedAuthorityDigest': reviewedAuthorityDigest.hex,
        'measurementImpact': measurementImpact.toJson(),
        'reason': reason,
        'reviewedAtMicros': reviewedAtMicros,
        'refusalCodes': refusalCodes,
      };
}

final class DeliveryPolicyPublishRequestV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyPublishRequestV1({
    required this.reviewRef,
    required this.operationId,
    this.measurementAcknowledgement,
  }) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(operationId)) {
      throw ArgumentError('Operation id must be a lowercase UUID v4');
    }
  }
  factory DeliveryPolicyPublishRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyPublishRequestV1.fromJson,
        'deliveryPolicyPublishRequest',
      );
  factory DeliveryPolicyPublishRequestV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyPublishRequest',
      const {'reviewRef', 'operationId'},
      optional: const {'measurementAcknowledgement'},
    );
    final ack = r.optionalObject('measurementAcknowledgement');
    return _construct(
      'deliveryPolicyPublishRequest',
      () => DeliveryPolicyPublishRequestV1(
        reviewRef: DeliveryPolicyReviewRefV1.fromJson(r.object('reviewRef')),
        operationId: r.string('operationId'),
        measurementAcknowledgement: ack == null
            ? null
            : DeliveryMeasurementImpactAcknowledgementV1.fromJson(ack),
      ),
    );
  }
  final DeliveryPolicyReviewRefV1 reviewRef;
  final String operationId;
  final DeliveryMeasurementImpactAcknowledgementV1? measurementAcknowledgement;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyPublishRequest',
        'reviewRef': reviewRef.toJson(),
        'operationId': operationId,
        if (measurementAcknowledgement != null)
          'measurementAcknowledgement': measurementAcknowledgement!.toJson(),
      };
}

final class DeliveryPolicyPublishResultV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  const DeliveryPolicyPublishResultV1.applied(
    DeliveryPolicyRevisionRefV1 this.revision,
  )   : outcome = 'applied',
        refusalCode = null,
        current = null;
  const DeliveryPolicyPublishResultV1.replayed(
    DeliveryPolicyRevisionRefV1 this.revision,
  )   : outcome = 'replayed',
        refusalCode = null,
        current = null;
  const DeliveryPolicyPublishResultV1.conflict(this.current)
      : outcome = 'conflict',
        refusalCode = null,
        revision = null;
  const DeliveryPolicyPublishResultV1.refused(String this.refusalCode)
      : outcome = 'refused',
        revision = null,
        current = null;
  factory DeliveryPolicyPublishResultV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyPublishResultV1.fromJson,
        'deliveryPolicyPublishResult',
      );
  factory DeliveryPolicyPublishResultV1.fromJson(Map<String, Object?> json) {
    final r = _reader(
      json,
      'deliveryPolicyPublishResult',
      const {'outcome'},
      optional: const {'revision', 'refusalCode', 'current'},
    );
    final revision = r.optionalObject('revision');
    final current = r.optionalObject('current');
    final code = r.optionalString('refusalCode');
    final result = switch (r.string('outcome')) {
      'applied' when revision != null => DeliveryPolicyPublishResultV1.applied(
          DeliveryPolicyRevisionRefV1.fromJson(revision),
        ),
      'replayed' when revision != null =>
        DeliveryPolicyPublishResultV1.replayed(
          DeliveryPolicyRevisionRefV1.fromJson(revision),
        ),
      'conflict' => DeliveryPolicyPublishResultV1.conflict(
          current == null
              ? null
              : DeliveryPolicyRevisionRefV1.fromJson(current),
        ),
      'refused' when code != null && code.isNotEmpty =>
        DeliveryPolicyPublishResultV1.refused(code),
      _ => throw const CanonicalFormatException('Invalid publish result'),
    };
    if (CanonicalJsonCodec.encode(result.toJson()).toString() !=
        CanonicalJsonCodec.encode(json).toString()) {
      throw const CanonicalFormatException(
        'Publish outcome carries fields for another outcome',
      );
    }
    return result;
  }
  final String outcome;
  final DeliveryPolicyRevisionRefV1? revision;
  final DeliveryPolicyRevisionRefV1? current;
  final String? refusalCode;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyPublishResult',
        'outcome': outcome,
        if (revision != null) 'revision': revision!.toJson(),
        if (current != null) 'current': current!.toJson(),
        if (refusalCode != null) 'refusalCode': refusalCode,
      };
}

final class DeliveryPolicyUndoReviewRequestV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  DeliveryPolicyUndoReviewRequestV1({
    required this.scope,
    required this.expectedHeadOrdinal,
    required this.restoreOrdinal,
    required this.reason,
  }) {
    _requirePositivePortable(restoreOrdinal, 'restoreOrdinal');
    if (expectedHeadOrdinal != null) {
      _requirePositivePortable(expectedHeadOrdinal!, 'expectedHeadOrdinal');
    }
    if (reason.trim().isEmpty) throw ArgumentError('Undo requires a reason');
  }
  factory DeliveryPolicyUndoReviewRequestV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decodeCanonical(
        bytes,
        DeliveryPolicyUndoReviewRequestV1.fromJson,
        'deliveryPolicyUndoReviewRequest',
      );
  factory DeliveryPolicyUndoReviewRequestV1.fromJson(
    Map<String, Object?> json,
  ) {
    final r = _reader(
      json,
      'deliveryPolicyUndoReviewRequest',
      const {'scope', 'restoreOrdinal', 'reason'},
      optional: const {'expectedHeadOrdinal'},
    );
    return _construct(
      'deliveryPolicyUndoReviewRequest',
      () => DeliveryPolicyUndoReviewRequestV1(
        scope: DeliveryPolicyScopeV1.fromJson(r.object('scope')),
        expectedHeadOrdinal: r.optionalInteger('expectedHeadOrdinal'),
        restoreOrdinal: r.integer('restoreOrdinal'),
        reason: r.string('reason'),
      ),
    );
  }
  final DeliveryPolicyScopeV1 scope;
  final int? expectedHeadOrdinal;
  final int restoreOrdinal;
  final String reason;
  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryPolicyUndoReviewRequest',
        'scope': scope.toJson(),
        if (expectedHeadOrdinal != null)
          'expectedHeadOrdinal': expectedHeadOrdinal,
        'restoreOrdinal': restoreOrdinal,
        'reason': reason,
      };
}

CanonicalDigest _managementDigest(String domain, List<int> bytes) =>
    CanonicalDigest(
      sha256.convert(
        [...utf8.encode('restage.$domain.v1\u0000'), ...bytes],
      ).toString(),
    );
Uint8List _canonicalObjectBytes(List<int> bytes) {
  final copied = _copyOctets(bytes);
  decodeCanonicalObject(copied);
  return copied;
}

Uint8List _readBase64(String value) {
  try {
    final bytes = base64Decode(value);
    if (base64Encode(bytes) != value) {
      throw const CanonicalFormatException('Expected canonical padded base64');
    }
    return bytes;
  } on FormatException {
    throw const CanonicalFormatException('Expected canonical padded base64');
  }
}

void _requireWarning(String code) {
  if (!const {
    'metricSourceUnavailable',
    'deliveryPopulationChanged',
    'scheduledOutputLost',
  }.contains(code)) {
    throw ArgumentError.value(
      code,
      'warningCode',
      'Unknown measurement warning',
    );
  }
}

void _requireSortedUnique(List<String> values, String name) {
  for (var i = 1; i < values.length; i++) {
    if (values[i - 1].compareTo(values[i]) >= 0) {
      throw ArgumentError('$name must be unique and sorted');
    }
  }
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

CanonicalObjectReader _reader(
  Map<String, Object?> json,
  String kind,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: {'kind', ...required, ...optional},
    requiredKeys: {'kind', ...required},
    path: kind,
  );
  if (reader.string('kind') != kind) {
    throw CanonicalFormatException('Expected routing kind "$kind"');
  }
  return reader;
}

T _construct<T>(String path, T Function() construct) {
  try {
    return construct();
    // Constructor refusals become canonical-format refusals when decoding.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}

T _decodeCanonical<T extends CanonicalValue>(
  List<int> bytes,
  T Function(Map<String, Object?>) decode,
  String path,
) {
  final original = _copyOctets(bytes);
  return verifyCanonicalRoundTrip(
    decode(decodeCanonicalObject(original)),
    original,
    path: path,
  );
}

Uint8List _copyOctets(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw const CanonicalFormatException('Canonical bytes must be octets');
    }
  }
  return Uint8List.fromList(bytes);
}

void _requirePositivePortable(int value, String name) {
  if (value <= 0 || value > kMaximumPortableJsonInteger) {
    throw ArgumentError.value(
      value,
      name,
      'Expected a positive portable integer',
    );
  }
}
