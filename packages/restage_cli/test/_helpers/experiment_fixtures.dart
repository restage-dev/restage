import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Destination target every experiment fixture addresses.
final fixtureTarget = TargetCoordinate(
  organizationId: OrganizationId(11),
  appId: ApplicationId(23),
  environmentTargetId: EnvironmentTargetId(31),
  namedEnvironmentId: NamedEnvironmentId(37),
  runtimePlane: RuntimePlane.live,
);

/// A second target, used to prove a view addressed elsewhere is refused.
final fixtureOtherTarget = TargetCoordinate(
  organizationId: OrganizationId(11),
  appId: ApplicationId(23),
  environmentTargetId: EnvironmentTargetId(41),
  namedEnvironmentId: NamedEnvironmentId(43),
  runtimePlane: RuntimePlane.sandbox,
);

/// Draft locator shared by draft-bound fixtures.
const fixtureDraftBinding = <String, Object?>{
  'draftId': 'experiment-draft-checkout',
  'draftRevisionId': 'experiment-draft-checkout.v3',
  'expectedCas': 'draft-cas-3',
};

/// The correlation identity a fixture request for [operationWireName] carries.
String fixtureCorrelationId(String operationWireName) =>
    'correlation-$operationWireName';

/// A stable opaque surface identity in the shape Restage mints for fixtures.
String fixtureMintedSurfaceId(String name) =>
    '$kMintedSurfaceIdPrefix${_fixtureMintedDigest(name)}';

/// A stable opaque surface-revision identity in the shape Restage mints.
String fixtureMintedSurfaceRevisionId(String name) =>
    '$kMintedSurfaceRevisionIdPrefix${_fixtureMintedDigest(name)}';

String _fixtureMintedDigest(String name) =>
    sha256.convert(utf8.encode(name)).toString();

/// Builds one constructor-validated request for [operation].
ExperimentAuthoringRequestV1 canonicalRequest(
  ExperimentAuthoringOperationV1 operation,
) => ExperimentAuthoringRequestV1.fromJson({
  'correlationId': fixtureCorrelationId(operation.wireName),
  if (operation.requiresIdempotencyKey)
    'idempotencyKey': 'idempotency-${operation.wireName}',
  'kind': 'experimentAuthoringRequest',
  'operation': operation.wireName,
  'payload': _requestPayload(operation),
  'schemaVersion': kMeasurementSchemaVersion,
});

/// Canonical bytes of an accepted result for the route [operationWireName].
Uint8List acceptedFor(
  String operationWireName, {
  String? correlationId,
  TargetCoordinate? target,
  bool completeDraft = true,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId ?? fixtureCorrelationId(operationWireName),
  'kind': 'accepted',
  'operation': operationWireName,
  'response': _acceptedResponse(
    _operationFor(operationWireName),
    target ?? fixtureTarget,
    completeDraft: completeDraft,
  ),
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

/// Canonical bytes of a typed refusal for the route [operationWireName].
Uint8List refusalFor(
  String operationWireName,
  ExperimentAuthoringRefusalCodeV1 code, {
  String? correlationId,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId ?? fixtureCorrelationId(operationWireName),
  'kind': 'refused',
  'operation': operationWireName,
  'refusal': {
    'code': code.wireName,
    'kind': 'experimentAuthoringRefusal',
    'messageKey': 'experiment.authoring.${code.wireName}',
    'retryable':
        code == ExperimentAuthoringRefusalCodeV1.backendUnavailable ||
        code == ExperimentAuthoringRefusalCodeV1.transportUnknownOutcome,
    'schemaVersion': kMeasurementSchemaVersion,
  },
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

/// Canonical bytes of one accepted discovery page.
Uint8List discoveryPage({
  List<String> namedEnvironmentLabels = const [],
  List<(String, String)> surfaces = const [],
  String? nextPageCursor,
  TargetCoordinate? target,
  String? correlationId,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId':
      correlationId ?? fixtureCorrelationId('discoverTargetsAndCapabilities'),
  'kind': 'accepted',
  'operation': 'discoverTargetsAndCapabilities',
  'response': _discoveryResponse(
    target: target ?? fixtureTarget,
    namedEnvironmentLabels: namedEnvironmentLabels,
    surfaces: surfaces,
    nextPageCursor: nextPageCursor,
  ),
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

/// Canonical bytes of one accepted, evaluated experiment result.
Uint8List resultsView({String? correlationId, TargetCoordinate? target}) =>
    ExperimentAuthoringResultV1.fromJson({
      'correlationId':
          correlationId ?? fixtureCorrelationId('readExperimentResults'),
      'kind': 'accepted',
      'operation': 'readExperimentResults',
      'response': _resultsResponse(target ?? fixtureTarget),
      'schemaVersion': kMeasurementSchemaVersion,
    }).canonicalBytes;

/// Canonical bytes of one accepted experiment-list page.
Uint8List listPage({
  List<String> experimentIds = const [],
  String? nextPageCursor,
  TargetCoordinate? target,
  String? correlationId,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId ?? fixtureCorrelationId('listExperiments'),
  'kind': 'accepted',
  'operation': 'listExperiments',
  'response': _listResponse(
    target: target ?? fixtureTarget,
    experimentIds: experimentIds,
    nextPageCursor: nextPageCursor,
  ),
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

/// Canonical bytes of a delivery handover with the sealed audience and arms.
Uint8List deliveryOptionsAccepted(
  String correlationId, {
  List<Map<String, Object?>>? arms,
  TargetCoordinate? target,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId,
  'kind': 'accepted',
  'operation': 'readDeliveryOptions',
  'response': {
    'arms':
        arms ??
        [
          {
            'kind': 'experimentArmDelivery',
            'label': 'Control',
            'publishedVersion': 4,
            'stableArmId': 'arm.control',
          },
          {
            'kind': 'experimentArmDelivery',
            'label': 'Treatment',
            'publishedVersion': 5,
            'stableArmId': 'arm.treatment',
          },
        ],
    'audienceLabel': 'Sweden',
    'audienceRevisionId': 'audience.sweden.v4',
    'experimentId': 'experiment.checkout',
    'kind': 'experimentDeliveryOptionsView',
    'schemaVersion': kMeasurementSchemaVersion,
    'surfaceSlug': 'checkout',
    'surfaceType': 'paywall',
    'target': (target ?? fixtureTarget).toJson(),
  },
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

/// Encodes [bytes] the way the RPC layer carries a binary payload.
String byteDataWire(List<int> bytes) =>
    "decode('${base64Encode(bytes)}', 'base64')";

/// Reads bytes back out of the RPC layer's binary payload spelling.
Uint8List byteDataBytes(String wire) {
  const prefix = "decode('";
  const suffix = "', 'base64')";
  return Uint8List.fromList(
    base64Decode(wire.substring(prefix.length, wire.length - suffix.length)),
  );
}

ExperimentAuthoringOperationV1 _operationFor(String wireName) =>
    ExperimentAuthoringOperationV1.values.firstWhere(
      (operation) => operation.wireName == wireName,
    );

Map<String, Object?> _requestPayload(
  ExperimentAuthoringOperationV1 operation,
) => switch (operation) {
  ExperimentAuthoringOperationV1.discoverTargetsAndCapabilities => const {
    'pageSize': 100,
  },
  ExperimentAuthoringOperationV1.openDraft => const {},
  ExperimentAuthoringOperationV1.deleteDraft ||
  ExperimentAuthoringOperationV1.readDraft ||
  ExperimentAuthoringOperationV1.validateDraft ||
  ExperimentAuthoringOperationV1.reviewDraft => fixtureDraftBinding,
  ExperimentAuthoringOperationV1.readDeliveryOptions => const {
    'experimentId': 'experiment.checkout',
  },
  ExperimentAuthoringOperationV1.resolveDraft => {
    'draftId': fixtureDraftBinding['draftId'],
  },
  ExperimentAuthoringOperationV1.replaceDraft => {
    ...fixtureDraftBinding,
    'replacement': emptyDraftChoices,
  },
  ExperimentAuthoringOperationV1.copyDraftToTarget => {
    'sourceDraft': fixtureDraftBinding,
    'sourceTarget': fixtureOtherTarget.toJson(),
  },
  ExperimentAuthoringOperationV1.activateDraft => {
    ...fixtureDraftBinding,
    'reviewReference': {
      'kind': 'experimentReviewReference',
      'recordDigest': 'a' * 64,
      'reviewId': 'review.checkout.v1',
      'schemaVersion': kMeasurementSchemaVersion,
    },
  },
  ExperimentAuthoringOperationV1.pauseExperiment ||
  ExperimentAuthoringOperationV1.resumeExperiment ||
  ExperimentAuthoringOperationV1.concludeExperiment => const {
    'expectedLifecycleOrdinal': 8,
    'experimentId': 'experiment.checkout',
  },
  ExperimentAuthoringOperationV1.listExperiments => const {'pageSize': 50},
  ExperimentAuthoringOperationV1.readExperiment => const {
    'experimentId': 'experiment.checkout',
  },
  ExperimentAuthoringOperationV1.readExperimentResults => {
    'activationOrdinal': 7,
    'experimentId': 'experiment.checkout',
    'resultDigest': 'b' * 64,
  },
  ExperimentAuthoringOperationV1.setExperimentArchived => const {
    'archived': true,
    'expectedControlPlaneOrdinal': 8,
    'experimentId': 'experiment.checkout',
  },
  ExperimentAuthoringOperationV1.registerBuildCapabilities => {
    'appBuildOrdinal': 412,
    'contextSchemaRef': {
      'contextSchemaId': 'assignment.context.checkout',
      'revisionId': 'assignment.context.checkout.v2',
      'semanticDigest': 'c' * 64,
    },
    'platform': 'ios',
    'sdkApiLevel': 3,
  },
  ExperimentAuthoringOperationV1.readExperimentReadiness => const {
    'pageSize': 100,
  },
};

/// Unselected draft mutation choices for strict API requests.
const emptyDraftChoices = <String, Object?>{
  'analysisSelection': {'kind': 'unselected'},
  'arms': <Object?>[],
  'assignmentAudienceSelection': {'kind': 'unselected'},
  'assignmentEligibilitySelection': {'kind': 'unselected'},
  'description': '',
  'diagnosticBindingIds': <Object?>[],
  'guardrails': <Object?>[],
  'kind': 'experimentDraftChoices',
  'label': '',
  'layerHoldoutIds': <Object?>[],
  'memberHoldouts': <Object?>[],
  'memberNoTreatment': {'kind': 'unselected'},
  'metricBindings': <Object?>[],
  'primaryBindingSelection': {'kind': 'unselected'},
  'randomizedUnitSelection': {'kind': 'serverDefault'},
  'rootSelection': {'kind': 'unselected'},
  'subjectSelection': {'kind': 'subjectless'},
};

Map<String, Object?> _discoveryResponse({
  required TargetCoordinate target,
  required List<String> namedEnvironmentLabels,
  required List<(String, String)> surfaces,
  required String? nextPageCursor,
}) => {
  'actionAvailability': [
    for (final action in ExperimentActionV1.values)
      {
        'action': action.wireName,
        'available': true,
        'kind': 'experimentActionAvailability',
      },
  ],
  'appLabel': 'Checkout',
  'environmentLabel': 'Production',
  'kind': 'experimentTargetDiscovery',
  'metricCapabilities': <Object?>[],
  'namedEnvironments': [
    for (var index = 0; index < namedEnvironmentLabels.length; index++)
      {
        'kind': 'experimentNamedEnvironmentOption',
        'label': namedEnvironmentLabels[index],
        'namedEnvironmentId': index + 1,
        'selected': index == 0,
      },
  ],
  'nextPageCursor': nextPageCursor,
  'organizationLabel': 'Restage',
  'runtimePlanes': <Object?>[],
  'schemaVersion': kMeasurementSchemaVersion,
  'surfaceCapabilities': [
    for (final surface in surfaces) _surfaceCapability(surface),
  ],
  'target': target.toJson(),
};

Map<String, Object?> _resultsResponse(TargetCoordinate target) => {
  'analysis': 'fixedHorizonNArmRate',
  'armResults': const [
    {
      'admittedCount': 5000,
      'effect': '0.000000000',
      'effectExact': {'denominator': '1', 'numerator': '0'},
      'interval': {
        'lower': '0.000000000',
        'lowerExact': {'denominator': '1', 'numerator': '0'},
        'upper': '0.000000000',
        'upperExact': {'denominator': '1', 'numerator': '0'},
      },
      'kind': 'experimentArmResult',
      'observedCount': 5000,
      'rate': '0.100000000',
      'rateExact': {'denominator': '10', 'numerator': '1'},
      'stableArmId': 'arm.control',
      'successCount': 500,
    },
    {
      'admittedCount': 5000,
      'effect': '0.005000000',
      'effectExact': {'denominator': '200', 'numerator': '1'},
      'interval': {
        'lower': '-0.000976563',
        'lowerExact': {'denominator': '1024', 'numerator': '-1'},
        'upper': '0.008789063',
        'upperExact': {'denominator': '1024', 'numerator': '9'},
      },
      'kind': 'experimentArmResult',
      'observedCount': 5000,
      'rate': '0.105000000',
      'rateExact': {'denominator': '200', 'numerator': '21'},
      'stableArmId': 'arm.variant',
      'successCount': 525,
    },
  ],
  'availability': const {'kind': 'available'},
  'designDigest': _fixtureMintedDigest('results-design'),
  'epochDigest': _fixtureMintedDigest('results-epoch'),
  'experimentId': 'experiment.checkout',
  'generatedAtMicros': 1788091400000000,
  'guardrailOutcomes': const [
    {
      'guardrailId': 'guardrail.checkout-errors',
      'kind': 'experimentGuardrailOutcome',
      'outcome': 'withinBound',
    },
  ],
  'kind': 'experimentResultsView',
  'lifecycleState': 'active',
  'resultDigest': _fixtureMintedDigest('results-digest'),
  'schemaVersion': kMeasurementSchemaVersion,
  'structuredCopyKeys': const ['experiment.result.noDecision'],
  'target': target.toJson(),
};

Map<String, Object?> _surfaceCapability((String, String) surface) => {
  'active': true,
  'analysisChoices': <Object?>[],
  'deliverySurfaceType': 'paywall',
  'installedMetricCapabilities': <Object?>[],
  'kind': 'experimentSurfaceCapability',
  'label': surface.$1,
  'revisionOrdinal': 1,
  'surfaceReference': {
    'kind': 'exactSurfaceReference',
    'surfaceId': fixtureMintedSurfaceId(surface.$1),
    'surfaceRevisionId': fixtureMintedSurfaceRevisionId(surface.$2),
  },
  'treatmentOrigins': [
    {
      'kind': 'wholeSurface',
      'locusIds': ['${surface.$2}.locus'],
    },
  ],
};

Map<String, Object?> _listResponse({
  required TargetCoordinate target,
  required List<String> experimentIds,
  required String? nextPageCursor,
}) => {
  'experiments': [
    for (final experimentId in experimentIds)
      _draftSummary(experimentId, target),
  ],
  'kind': 'experimentListView',
  'nextPageCursor': nextPageCursor,
  'schemaVersion': kMeasurementSchemaVersion,
  'target': target.toJson(),
};

Map<String, Object?> _draftSummary(
  String experimentId,
  TargetCoordinate target,
) => {
  'archivedAtMicros': null,
  'completeness': {'kind': 'complete'},
  'controlPlaneOrdinal': 1,
  'createdAtMicros': 1700000000000000,
  'draftId': '$experimentId.draft',
  'draftRevisionId': '$experimentId.draft.v1',
  'experimentId': experimentId,
  'kind': 'experimentDraftSummary',
  'label': experimentId,
  'liveState': {'kind': 'unavailable', 'reasonCode': 'notActivated'},
  'schemaVersion': kMeasurementSchemaVersion,
  'target': target.toJson(),
};

Map<String, Object?> _acceptedResponse(
  ExperimentAuthoringOperationV1 operation,
  TargetCoordinate target, {
  bool completeDraft = true,
}) => switch (operation) {
  ExperimentAuthoringOperationV1.discoverTargetsAndCapabilities =>
    _discoveryResponse(
      target: target,
      namedEnvironmentLabels: const ['Production'],
      surfaces: const [],
      nextPageCursor: null,
    ),
  ExperimentAuthoringOperationV1.listExperiments => _listResponse(
    target: target,
    experimentIds: const [],
    nextPageCursor: null,
  ),
  ExperimentAuthoringOperationV1.openDraft ||
  ExperimentAuthoringOperationV1.readDraft ||
  ExperimentAuthoringOperationV1.resolveDraft ||
  ExperimentAuthoringOperationV1.replaceDraft ||
  ExperimentAuthoringOperationV1.copyDraftToTarget => _draftResponse(
    target,
    complete: completeDraft,
  ),
  _ => throw UnimplementedError(
    'No accepted fixture for ${operation.wireName}',
  ),
};

Map<String, Object?> _resolved(Object value) => {
  'kind': 'exactRef',
  'resolvedExactRef': value,
};

Map<String, Object?> _draftResponse(
  TargetCoordinate target, {
  required bool complete,
}) => {
  ...fixtureDraftBinding,
  'choices': {
    ...emptyDraftChoices,
    'analysisSelection': {'kind': complete ? 'measureOnly' : 'unselected'},
    'arms': [
      for (final arm in ['control', 'variant'])
        {
          if (complete) 'candidate': _draftCandidate(arm),
          if (!complete) 'candidateSelection': _resolved(_draftCandidate(arm)),
          'kind': 'experimentDraftArmChoice',
          'label': arm,
          'relativeWeight': 1,
          'stableArmId': 'arm.$arm',
        },
    ],
    'assignmentAudienceSelection': _resolved(_draftPolicy('audience')),
    'assignmentEligibilitySelection': complete
        ? _resolved(_draftPolicy('eligibility'))
        : {'kind': 'unselected'},
    'description': 'Compare checkout surfaces.',
    'label': 'Checkout completion',
    'memberNoTreatment': _resolved(_draftCandidate('control')),
    'metricBindings': [
      {
        'armProjectionSets': [
          for (final arm in ['control', 'variant']) _draftProjectionSet(arm),
        ],
        'kind': 'experimentDraftMetricBindingChoice',
        'label': 'Completed checkout',
        'metricBindingId': 'binding.checkout',
        'metricDefinitionChoice': _resolved({
          'direction': 'higherIsBetter',
          'metricDefinitionId': 'metric.checkout',
          'metricDefinitionRevisionId': 'metric.checkout.v1',
          'metricDefinitionSemanticDigest': 'a' * 64,
        }),
      },
    ],
    'primaryBindingSelection': _resolved({
      'metricBindingId': 'binding.checkout',
    }),
    'randomizedUnitSelection': {
      'kind': 'serverDefault',
      'resolvedValue': 'installation',
      'source': const ExperimentRandomizedUnitDefaultsV1().toJson(),
    },
    'rootSelection': _resolved(
      DeliveryRootIdentityV1.surface(
        PublishedSurfaceIdentityV1(
          target: target,
          surfaceId: SurfaceId(fixtureMintedSurfaceId('checkout')),
        ),
      ).toJson(),
    ),
  },
  'completeness': {
    'kind': complete ? 'complete' : 'incomplete',
    if (!complete)
      'missingFieldPaths': [
        'analysisSelection',
        'assignmentEligibilitySelection',
      ],
  },
  'conflicts': <Object?>[],
  'experimentId': 'experiment.checkout',
  'kind': 'experimentDraftView',
  'revisionOrdinal': 3,
  'schemaVersion': kMeasurementSchemaVersion,
  'semanticDigest': 'b' * 64,
  'target': target.toJson(),
};

Map<String, Object?> _draftPolicy(String id) => {
  'policyId': id,
  'revisionId': '$id.v1',
  'semanticDigest': 'a' * 64,
};

Map<String, Object?> _draftCandidate(String arm) => {
  'kind': 'exactCandidate',
  'label': arm,
  'surfaceReference': {
    'kind': 'exactSurfaceReference',
    'surfaceId': fixtureMintedSurfaceId('checkout'),
    'surfaceRevisionId': fixtureMintedSurfaceRevisionId(arm),
  },
  'treatmentOrigin': {
    'kind': 'wholeSurface',
    'locusIds': ['locus.checkout'],
  },
};

Map<String, Object?> _draftProjectionSet(String arm) {
  final digests = {'canonicalDigest': 'a' * 64, 'semanticDigest': 'a' * 64};
  final members = [
    {
      'kind': 'experimentInstalledProjectionSetMember',
      'projectionReference': {
        ...digests,
        'projectionRevisionId': 'projection.$arm.v1',
      },
      'slotId': 'slot.checkout',
    },
  ];
  return {
    'installedProjectionSetChoice': _resolved({
      'compatibilityProofReference': {
        ...digests,
        'compatibilityProofRevisionId': 'proof.$arm.v1',
      },
      'kind': 'experimentInstalledProjectionSetCapability',
      'label': arm,
      'members': members,
      'metricBindingReference': {
        ...digests,
        'metricBindingId': 'installed-binding.$arm',
        'metricBindingRevisionId': 'installed-binding.$arm.v1',
      },
      'projectionSetReference': {
        ...digests,
        'projectionSetId': 'projection-set.$arm',
      },
    }),
    'kind': 'experimentDraftArmProjectionSetChoice',
    'resolvedMembers': members,
    'stableArmId': 'arm.$arm',
  };
}
