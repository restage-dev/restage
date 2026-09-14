import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  group('experiment authoring operations', () {
    test('uses one closed set of semantic operations', () {
      expect(
        ExperimentAuthoringOperationV1.values
            .map((operation) => operation.wireName),
        [
          'discoverTargetsAndCapabilities',
          'openDraft',
          'readDraft',
          'resolveDraft',
          'replaceDraft',
          'copyDraftToTarget',
          'validateDraft',
          'reviewDraft',
          'activateDraft',
          'pauseExperiment',
          'resumeExperiment',
          'concludeExperiment',
          'listExperiments',
          'readExperiment',
          'readExperimentResults',
          'setExperimentArchived',
        ],
      );
    });

    test('uses six stable authorization actions', () {
      expect(
        ExperimentActionV1.values.map((action) => action.wireName),
        [
          'experiment.read',
          'experiment.draft.create',
          'experiment.draft.edit',
          'experiment.validate',
          'experiment.activate',
          'experiment.archive',
        ],
      );
    });

    test('pins selectors, CAS, idempotency, and correlation by operation', () {
      final requests = <String, Map<String, Object?>>{
        'discoverTargetsAndCapabilities': _request(
          operation: 'discoverTargetsAndCapabilities',
          correlationId: 'correlation-discover-1',
          payload: const {'pageSize': 100},
        ),
        'openDraft': _request(
          operation: 'openDraft',
          correlationId: 'correlation-open-1',
          idempotencyKey: 'idempotency-open-1',
          payload: {
            'initialCandidate': _surfaceReference(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
          },
        ),
        'readDraft': _request(
          operation: 'readDraft',
          correlationId: 'correlation-read-draft-1',
          payload: _draftBinding(),
        ),
        'resolveDraft': _request(
          operation: 'resolveDraft',
          correlationId: 'correlation-resolve-draft-1',
          payload: const {'draftId': 'draft-9f2c'},
        ),
        'replaceDraft': _request(
          operation: 'replaceDraft',
          correlationId: 'correlation-replace-1',
          idempotencyKey: 'idempotency-replace-1',
          payload: {
            ..._draftBinding(),
            'replacement': _incompleteDraftMutationChoices(),
          },
        ),
        'copyDraftToTarget': _request(
          operation: 'copyDraftToTarget',
          correlationId: 'correlation-copy-1',
          idempotencyKey: 'idempotency-copy-1',
          payload: {
            'sourceDraft': _draftBinding(),
            'sourceTarget': _target(),
          },
        ),
        'validateDraft': _request(
          operation: 'validateDraft',
          correlationId: 'correlation-validate-1',
          payload: _draftBinding(),
        ),
        'reviewDraft': _request(
          operation: 'reviewDraft',
          correlationId: 'correlation-review-1',
          idempotencyKey: 'idempotency-review-1',
          payload: _draftBinding(),
        ),
        'activateDraft': _request(
          operation: 'activateDraft',
          correlationId: 'correlation-activate-1',
          idempotencyKey: 'idempotency-activate-1',
          payload: {
            ..._draftBinding(),
            'reviewReference': _reviewReference(),
          },
        ),
        'pauseExperiment': _request(
          operation: 'pauseExperiment',
          correlationId: 'correlation-pause-1',
          idempotencyKey: 'idempotency-pause-1',
          payload: const {
            'expectedLifecycleOrdinal': 8,
            'experimentId': 'experiment.checkout',
          },
        ),
        'resumeExperiment': _request(
          operation: 'resumeExperiment',
          correlationId: 'correlation-resume-1',
          idempotencyKey: 'idempotency-resume-1',
          payload: const {
            'expectedLifecycleOrdinal': 9,
            'experimentId': 'experiment.checkout',
          },
        ),
        'concludeExperiment': _request(
          operation: 'concludeExperiment',
          correlationId: 'correlation-conclude-1',
          idempotencyKey: 'idempotency-conclude-1',
          payload: const {
            'expectedLifecycleOrdinal': 10,
            'experimentId': 'experiment.checkout',
          },
        ),
        'listExperiments': _request(
          operation: 'listExperiments',
          correlationId: 'correlation-list-1',
          payload: const {'pageCursor': 'cursor-3', 'pageSize': 50},
        ),
        'readExperiment': _request(
          operation: 'readExperiment',
          correlationId: 'correlation-read-experiment-1',
          payload: const {'experimentId': 'experiment.checkout'},
        ),
        'readExperimentResults': _request(
          operation: 'readExperimentResults',
          correlationId: 'correlation-results-1',
          payload: {
            'activationOrdinal': 7,
            'experimentId': 'experiment.checkout',
            'resultDigest': _digest('9'),
          },
        ),
        'setExperimentArchived': _request(
          operation: 'setExperimentArchived',
          correlationId: 'correlation-archive-1',
          idempotencyKey: 'idempotency-archive-1',
          payload: const {
            'archived': true,
            'expectedControlPlaneOrdinal': 8,
            'experimentId': 'experiment.checkout',
          },
        ),
      };

      expect(requests.keys.toSet(), <String>{
        ...ExperimentAuthoringOperationV1.values
            .map((operation) => operation.wireName),
      });
      for (final entry in requests.entries) {
        final request = ExperimentAuthoringRequestV1.fromJson(entry.value);
        expect(request.operation.wireName, entry.key);
        expect(request.correlationId, isNotEmpty);
        expect(request.toJson(), entry.value);
        expect(
          ExperimentAuthoringRequestV1.fromCanonicalBytes(
            request.canonicalBytes,
          ).canonicalBytes,
          orderedEquals(request.canonicalBytes),
        );
        _expectNoSensitiveKeys(request.toJson(), request: true);
      }
    });

    test('closes payload keys and versions for every operation', () {
      for (final operation in ExperimentAuthoringOperationV1.values) {
        final valid = _minimalRequest(operation.wireName);
        final payload = valid['payload']! as Map<String, Object?>;

        for (final invalid in <Map<String, Object?>>[
          {...valid, 'schemaVersion': 2},
          {
            ...valid,
            'payload': {...payload, 'unexpected': true},
          },
        ]) {
          expect(
            () => ExperimentAuthoringRequestV1.fromJson(invalid),
            throwsA(isA<CanonicalFormatException>()),
            reason: '${operation.wireName}: $invalid',
          );
        }
      }

      expect(
        () => ExperimentAuthoringRequestV1.fromJson({
          ..._minimalRequest('discoverTargetsAndCapabilities'),
          'operation': 'unknownOperation',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentAuthoringRequestV1.fromJson({
          ..._minimalRequest('copyDraftToTarget'),
          'payload': {
            ...(_minimalRequest('copyDraftToTarget')['payload']!
                as Map<String, Object?>),
            'sourceTarget': {..._target(), 'projectId': 41},
          },
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('bounds request correlation, retry, and pagination values', () {
      final open = _minimalRequest('openDraft');
      for (final invalid in <Map<String, Object?>>[
        {...open, 'correlationId': 'x' * 4097},
        {...open, 'idempotencyKey': 'x' * 4097},
        {
          ..._minimalRequest('listExperiments'),
          'payload': const {'pageSize': 0},
        },
        {
          ..._minimalRequest('listExperiments'),
          'payload': const {'pageSize': 101},
        },
        {
          ..._minimalRequest('listExperiments'),
          'payload': {'pageCursor': 'x' * 4097, 'pageSize': 50},
        },
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(invalid),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('does not duplicate the exact target in semantic request bytes', () {
      for (final operation in ExperimentAuthoringOperationV1.values) {
        final request = ExperimentAuthoringRequestV1.fromJson(
          _minimalRequest(operation.wireName),
        );
        _expectNoSensitiveKeys(request.toJson(), request: true);
        expect(request.toJson(), isNot(contains('target')));
      }
    });

    test('copy identifies one exact source draft and source target', () {
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'copyDraftToTarget',
          correlationId: 'correlation-copy-source-1',
          idempotencyKey: 'idempotency-copy-source-1',
          payload: {
            'sourceDraft': _draftBinding(),
            'sourceTarget': _target(),
          },
        ),
      );
      expect(request.payload, {
        'sourceDraft': _draftBinding(),
        'sourceTarget': _target(),
      });

      final malformedTarget = Map<String, Object?>.from(_target())
        ..remove('appId');
      final malformedBinding = Map<String, Object?>.from(_draftBinding())
        ..remove('draftId');
      for (final invalid in <Map<String, Object?>>[
        _draftBinding(),
        {'sourceDraft': _draftBinding()},
        {'sourceTarget': _target()},
        {
          'sourceDraft': _draftBinding(),
          'sourceTarget': _target(),
          'unexpected': true,
        },
        {
          'sourceDraft': _draftBinding(),
          'sourceTarget': malformedTarget,
        },
        {
          'sourceDraft': malformedBinding,
          'sourceTarget': _target(),
        },
        {
          'sourceDraft': _draftBinding(),
          'sourceTarget': _target(),
          'target': _target(),
        },
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'copyDraftToTarget',
              correlationId: 'correlation-invalid-copy-source-1',
              idempotencyKey: 'idempotency-invalid-copy-source-1',
              payload: invalid,
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('read, archive, and results selectors remain distinct', () {
      final read = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'readExperiment',
          correlationId: 'correlation-read-selector-1',
          payload: const {'experimentId': 'experiment.checkout'},
        ),
      );
      expect(read.payload, const {'experimentId': 'experiment.checkout'});

      for (final invalid in <Map<String, Object?>>[
        const {},
        const {
          'activationOrdinal': 7,
          'experimentId': 'experiment.checkout',
        },
        const {'experimentId': 'experiment.checkout', 'unexpected': true},
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'readExperiment',
              correlationId: 'correlation-invalid-read-selector-1',
              payload: invalid,
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }

      final archive = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'setExperimentArchived',
          correlationId: 'correlation-archive-selector-1',
          idempotencyKey: 'idempotency-archive-selector-1',
          payload: const {
            'archived': true,
            'expectedControlPlaneOrdinal': 8,
            'experimentId': 'experiment.checkout',
          },
        ),
      );
      expect(archive.payload, const {
        'archived': true,
        'expectedControlPlaneOrdinal': 8,
        'experimentId': 'experiment.checkout',
      });

      final validArchive = Map<String, Object?>.from(archive.payload);
      for (final invalid in <Map<String, Object?>>[
        for (final key in validArchive.keys)
          Map<String, Object?>.from(validArchive)..remove(key),
        {
          ...validArchive,
          'expectedControlPlaneOrdinal': 0,
        },
        {
          'archived': true,
          'expectedLifecycleOrdinal': 8,
          'experimentId': 'experiment.checkout',
        },
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'setExperimentArchived',
              correlationId: 'correlation-invalid-archive-selector-1',
              idempotencyKey: 'idempotency-invalid-archive-selector-1',
              payload: invalid,
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }

      final results = ExperimentAuthoringRequestV1.fromJson(
        _minimalRequest('readExperimentResults'),
      );
      expect(results.payload, {
        'activationOrdinal': 7,
        'experimentId': 'experiment.checkout',
        'resultDigest': _digest('9'),
      });
    });

    test('lifecycle transitions carry only a positive lifecycle ordinal', () {
      final payloads = <String, Map<String, Object?>>{
        'pauseExperiment': const {
          'expectedLifecycleOrdinal': 8,
          'experimentId': 'experiment.checkout',
        },
        'resumeExperiment': const {
          'expectedLifecycleOrdinal': 9,
          'experimentId': 'experiment.checkout',
        },
        'concludeExperiment': const {
          'expectedLifecycleOrdinal': 10,
          'experimentId': 'experiment.checkout',
        },
      };

      for (final entry in payloads.entries) {
        final request = ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: entry.key,
            correlationId: 'correlation-${entry.key}-selector-1',
            idempotencyKey: 'idempotency-${entry.key}-selector-1',
            payload: entry.value,
          ),
        );
        expect(request.payload, entry.value);

        for (final invalid in <Map<String, Object?>>[
          for (final key in entry.value.keys)
            Map<String, Object?>.from(entry.value)..remove(key),
          {...entry.value, 'unexpected': true},
          {...entry.value, 'expectedControlPlaneOrdinal': 8},
          {...entry.value, 'target': _target()},
          {...entry.value, 'expectedLifecycleOrdinal': 0},
          {...entry.value, 'expectedLifecycleOrdinal': -1},
          {...entry.value, 'expectedLifecycleOrdinal': '8'},
          {...entry.value, 'expectedLifecycleOrdinal': 9007199254740992},
          {...entry.value, 'experimentId': 8},
        ]) {
          expect(
            () => ExperimentAuthoringRequestV1.fromJson(
              _request(
                operation: entry.key,
                correlationId: 'correlation-${entry.key}-invalid-1',
                idempotencyKey: 'idempotency-${entry.key}-invalid-1',
                payload: invalid,
              ),
            ),
            throwsA(isA<CanonicalFormatException>()),
            reason: '${entry.key}: $invalid',
          );
        }
      }
    });

    test('generic targets remain outside non-copy payloads', () {
      for (final operation in ExperimentAuthoringOperationV1.values) {
        if (operation == ExperimentAuthoringOperationV1.copyDraftToTarget) {
          continue;
        }
        final valid = _minimalRequest(operation.wireName);
        expect(
          () => ExperimentAuthoringRequestV1.fromJson({
            ...valid,
            'payload': {
              ...(valid['payload']! as Map<String, Object?>),
              'target': _target(),
            },
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: operation.wireName,
        );
      }
    });

    test('rejects proprietary candidate-family fields', () {
      for (final key in const <String>{
        'familyReference',
        'fullBasePublication',
        'fullOutputPublication',
        'resolvedCandidate',
      }) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'openDraft',
              correlationId: 'correlation-family-boundary-1',
              idempotencyKey: 'idempotency-family-boundary-1',
              payload: {
                'initialCandidate': _surfaceReference(
                  'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
                ),
                key: const <String, Object?>{},
              },
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: key,
        );
        expect(
          () => ExperimentDraftViewV1.fromJson({
            ..._draftView(),
            key: const <String, Object?>{},
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: key,
        );
      }
    });

    test('replace accepts closed unresolved choices without resolved defaults',
        () {
      final replacement = _incompleteDraftMutationChoices();
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'replaceDraft',
          correlationId: 'correlation-incomplete-replace-1',
          idempotencyKey: 'idempotency-incomplete-replace-1',
          payload: {..._draftBinding(), 'replacement': replacement},
        ),
      );

      expect(request.payload['replacement'], replacement);
      expect(
        ExperimentAuthoringRequestV1.fromCanonicalBytes(request.canonicalBytes)
            .canonicalBytes,
        orderedEquals(request.canonicalBytes),
      );
      expect(
        _containsKeyFragment(request.toJson(), 'resolvedExactRef'),
        isFalse,
      );
      expect(_containsKeyFragment(request.toJson(), 'resolvedValue'), isFalse);
      expect(_containsKeyFragment(request.toJson(), 'source'), isFalse);

      final emptyLabels = _incompleteDraftMutationChoices();
      emptyLabels['label'] = '';
      final emptyBinding = Map<String, Object?>.from(
        (emptyLabels['metricBindings']! as List).single as Map,
      )..['label'] = '';
      emptyLabels['metricBindings'] = [emptyBinding];
      final emptyArm = Map<String, Object?>.from(
        (emptyLabels['arms']! as List).first as Map,
      )..['label'] = '';
      emptyLabels['arms'] = [
        emptyArm,
        (emptyLabels['arms']! as List).last,
      ];
      expect(
        ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-empty-labels-1',
            idempotencyKey: 'idempotency-empty-labels-1',
            payload: {..._draftBinding(), 'replacement': emptyLabels},
          ),
        ).payload['replacement'],
        emptyLabels,
      );

      for (final length in [4096, 4097]) {
        final boundedLabels = _incompleteDraftMutationChoices();
        final boundedArm = Map<String, Object?>.from(
          (boundedLabels['arms']! as List).first as Map,
        )..['label'] = 'x' * length;
        boundedLabels['arms'] = [
          boundedArm,
          (boundedLabels['arms']! as List).last,
        ];
        ExperimentAuthoringRequestV1 decode() =>
            ExperimentAuthoringRequestV1.fromJson(
              _request(
                operation: 'replaceDraft',
                correlationId: 'correlation-bounded-arm-label-$length',
                idempotencyKey: 'idempotency-bounded-arm-label-$length',
                payload: {
                  ..._draftBinding(),
                  'replacement': boundedLabels,
                },
              ),
            );
        if (length == 4096) {
          expect(decode().payload['replacement'], boundedLabels);
        } else {
          expect(decode, throwsA(isA<CanonicalFormatException>()));
        }
      }

      final audience = Map<String, Object?>.from(
        replacement['assignmentAudienceSelection']! as Map,
      )..['resolvedExactRef'] = const {
          'policyId': 'audience.installed',
          'revisionId': 'audience.installed.v2',
          'semanticDigest':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        };
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-resolved-default-input-1',
            idempotencyKey: 'idempotency-resolved-default-input-1',
            payload: {
              ..._draftBinding(),
              'replacement': {
                ...replacement,
                'assignmentAudienceSelection': audience,
              },
            },
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('replace never falls back to a resolved draft read shape', () {
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-resolved-read-input-1',
            idempotencyKey: 'idempotency-resolved-read-input-1',
            payload: {..._draftBinding(), 'replacement': _draftChoices()},
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );

      for (final replacement in <Map<String, Object?>>[
        _incompleteDraftMutationChoices(
          assignmentAudienceSelection: {
            'kind': 'serverDefault',
            'resolvedExactRef': _policyReference('audience.installed'),
          },
        ),
        _incompleteDraftMutationChoices(
          planningSelection: {
            ..._planningMutationSelection(),
            'practicalSuperiorityMarginChoice': {
              'kind': 'serverDefault',
              'resolvedValue': _rational(1, 100),
              'source': _statisticalDefaults(),
            },
          },
        ),
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-client-resolution-1',
              idempotencyKey: 'idempotency-client-resolution-1',
              payload: {..._draftBinding(), 'replacement': replacement},
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: replacement.toString(),
        );
      }
    });

    test('replace decodes every exact reference by its field type', () {
      final replacement = _incompleteDraftMutationChoices(
        assignmentAudienceSelection: {
          'kind': 'exactRef',
          'exactRef': _policyReference('audience.installed'),
        },
        assignmentEligibilitySelection: {
          'kind': 'exactRef',
          'exactRef': _policyReference('eligibility.active'),
        },
        randomizedUnitSelection: {
          'kind': 'explicitValue',
          'value': 'installation',
        },
        memberNoTreatmentSelection: {
          'kind': 'exactRef',
          'exactRef': _exactCandidate(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
        },
        primaryBindingSelection: const {
          'kind': 'exactRef',
          'exactRef': {
            'metricBindingId': 'metric-binding.completed-checkout',
          },
        },
        candidateSelection: {
          'kind': 'exactRef',
          'exactRef': _exactCandidate(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
        },
        metricDefinitionSelection: {
          'kind': 'exactRef',
          'exactRef': _metricDefinitionReference(),
        },
        projectionSelection: {
          'kind': 'exactRef',
          'exactRef': _installedProjectionSetCapability(
            metricBindingId: 'installed-binding.completed-checkout.control',
            projectionSetId:
                'installed-projection-set.completed-checkout.control',
            projectionRevisionId: 'projection.checkout.control.v1',
            slotId: 'slot.checkout.completed',
            digestDigit: '1',
          ),
        },
        subjectSelection: {
          'kind': 'exactSubjectRef',
          'exactRef': _policyReference('subject.account'),
        },
      );
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'replaceDraft',
          correlationId: 'correlation-exact-references-1',
          idempotencyKey: 'idempotency-exact-references-1',
          payload: {..._draftBinding(), 'replacement': replacement},
        ),
      );
      expect(request.payload['replacement'], replacement);
      final stored = request.payload['replacement']! as Map;
      final binding = (stored['metricBindings']! as List).single as Map;
      final projectionSet =
          (binding['armProjectionSets']! as List).single as Map;
      expect(binding['metricBindingId'], 'metric-binding.completed-checkout');
      final selectedGroup = (projectionSet['installedProjectionSetChoice']!
          as Map)['exactRef'] as Map;
      expect(
        ((selectedGroup['projectionSetReference']! as Map)['projectionSetId']),
        'installed-projection-set.completed-checkout.control',
      );
      expect(
        ((selectedGroup['metricBindingReference']! as Map)['metricBindingId']),
        'installed-binding.completed-checkout.control',
      );

      for (final invalid in <Map<String, Object?>>[
        _incompleteDraftMutationChoices(
          assignmentAudienceSelection: {
            'kind': 'exactRef',
            'exactRef': _surfaceReference(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
          },
        ),
        _incompleteDraftMutationChoices(
          memberNoTreatmentSelection: {
            'kind': 'exactRef',
            'exactRef': _policyReference('audience.installed'),
          },
        ),
        _incompleteDraftMutationChoices(
          candidateSelection: {
            'kind': 'exactRef',
            'exactRef': _surfaceReference(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
          },
        ),
        _incompleteDraftMutationChoices(
          candidateSelection: {
            'kind': 'exactRef',
            'exactRef': _policyReference('audience.installed'),
          },
        ),
        _incompleteDraftMutationChoices(
          primaryBindingSelection: {
            'kind': 'exactRef',
            'exactRef': _policyReference('audience.installed'),
          },
        ),
        _incompleteDraftMutationChoices(
          metricDefinitionSelection: {
            'kind': 'exactRef',
            'exactRef': _policyReference('audience.installed'),
          },
        ),
        _incompleteDraftMutationChoices(
          projectionSelection: {
            'kind': 'exactRef',
            'exactRef': _policyReference('audience.installed'),
          },
        ),
        _incompleteDraftMutationChoices(
          subjectSelection: {
            'kind': 'exactSubjectRef',
            'exactRef': _surfaceReference(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
          },
        ),
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-foreign-exact-reference-1',
              idempotencyKey: 'idempotency-foreign-exact-reference-1',
              payload: {..._draftBinding(), 'replacement': invalid},
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('primary binding mutation requires an exact reference', () {
      final replacement = _incompleteDraftMutationChoices(
        primaryBindingSelection: const {'kind': 'serverDefault'},
      );
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-primary-binding-exact-ref',
            idempotencyKey: 'idempotency-primary-binding-exact-ref',
            payload: {..._draftBinding(), 'replacement': replacement},
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test(
      'replace retains an exact selected projection group',
      () {
        const authorityRevisions = [
          'installed-projection.checkout.completed.v7',
          'installed-projection.checkout.completed.v8',
        ];

        for (final authorityRevisionId in authorityRevisions) {
          final replacement = _incompleteDraftMutationChoices(
            projectionSelection: {
              'kind': 'exactRef',
              'exactRef': _installedProjectionSetCapability(
                metricBindingId:
                    'installed-binding.completed-checkout.$authorityRevisionId',
                projectionSetId:
                    'installed-projection-set.completed-checkout.$authorityRevisionId',
                projectionRevisionId: authorityRevisionId,
                slotId: 'slot.checkout.completed',
                digestDigit: '1',
              ),
            },
          );
          final request = ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId:
                  'correlation-projection-authority-$authorityRevisionId',
              idempotencyKey:
                  'idempotency-projection-authority-$authorityRevisionId',
              payload: {..._draftBinding(), 'replacement': replacement},
            ),
          );
          final stored = request.payload['replacement']! as Map;
          final binding = (stored['metricBindings']! as List).single as Map;
          final projectionSet =
              (binding['armProjectionSets']! as List).single as Map;
          final choice = projectionSet['installedProjectionSetChoice']! as Map;
          final exactRef = choice['exactRef']! as Map;

          expect(
            ((exactRef['projectionSetReference']! as Map)['projectionSetId']),
            'installed-projection-set.completed-checkout.$authorityRevisionId',
          );
          expect(
            (((exactRef['members']! as List).single
                as Map)['projectionReference'] as Map)['projectionRevisionId'],
            authorityRevisionId,
          );
          expect(
            ExperimentAuthoringRequestV1.fromCanonicalBytes(
              request.canonicalBytes,
            ).canonicalBytes,
            orderedEquals(request.canonicalBytes),
          );
        }
      },
    );

    test('replace accepts distinct installed projection groups for each arm',
        () {
      final controlGroup = _installedProjectionSetCapability(
        metricBindingId: 'installed-binding.completed-checkout.control',
        projectionSetId: 'installed-projection-set.completed-checkout.control',
        projectionRevisionId: 'projection.checkout.control.v1',
        slotId: 'slot.checkout.completed',
        digestDigit: '1',
      );
      final variantGroup = _installedProjectionSetCapability(
        metricBindingId: 'installed-binding.completed-checkout.variant',
        projectionSetId: 'installed-projection-set.completed-checkout.variant',
        projectionRevisionId: 'projection.checkout.variant.v1',
        slotId: 'slot.checkout.completed',
        digestDigit: '2',
      );
      final replacement = _mutationChoicesWithInstalledProjectionSets([
        _installedProjectionSetMutationChoice(
          stableArmId: 'arm.control',
          exactRef: controlGroup,
        ),
        _installedProjectionSetMutationChoice(
          stableArmId: 'arm.variant',
          exactRef: variantGroup,
        ),
      ]);
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'replaceDraft',
          correlationId: 'correlation-distinct-installed-projection-groups',
          idempotencyKey: 'idempotency-distinct-installed-projection-groups',
          payload: {..._draftBinding(), 'replacement': replacement},
        ),
      );
      final stored = request.payload['replacement']! as Map;
      final binding = (stored['metricBindings']! as List).single as Map;
      final selectedGroups = [
        for (final projectionSet in binding['armProjectionSets']! as List)
          ((projectionSet as Map)['installedProjectionSetChoice']
              as Map)['exactRef'] as Map,
      ];

      expect(binding['metricBindingId'], 'metric-binding.completed-checkout');
      expect(
        selectedGroups
            .map(
              (group) =>
                  (group['metricBindingReference']! as Map)['metricBindingId'],
            )
            .toList(),
        [
          'installed-binding.completed-checkout.control',
          'installed-binding.completed-checkout.variant',
        ],
      );
      expect(
        selectedGroups
            .map(
              (group) =>
                  (group['projectionSetReference']! as Map)['projectionSetId'],
            )
            .toList(),
        [
          'installed-projection-set.completed-checkout.control',
          'installed-projection-set.completed-checkout.variant',
        ],
      );
    });

    test('replace accepts one installed projection group for multiple arms',
        () {
      final group = _installedProjectionSetCapability(
        metricBindingId: 'installed-binding.completed-checkout',
        projectionSetId: 'installed-projection-set.completed-checkout',
        projectionRevisionId: 'projection.checkout.control.v1',
        slotId: 'slot.checkout.completed',
        digestDigit: '1',
      );
      final replacement = _mutationChoicesWithInstalledProjectionSets([
        _installedProjectionSetMutationChoice(
          stableArmId: 'arm.control',
          exactRef: group,
        ),
        _installedProjectionSetMutationChoice(
          stableArmId: 'arm.variant',
          exactRef: group,
        ),
      ]);

      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-shared-installed-projection-group',
            idempotencyKey: 'idempotency-shared-installed-projection-group',
            payload: {..._draftBinding(), 'replacement': replacement},
          ),
        ),
        returnsNormally,
      );
    });

    test('replace rejects duplicate draft arm identities', () {
      final group = _installedProjectionSetCapability(
        metricBindingId: 'installed-binding.completed-checkout',
        projectionSetId: 'installed-projection-set.completed-checkout',
        projectionRevisionId: 'projection.checkout.control.v1',
        slotId: 'slot.checkout.completed',
        digestDigit: '1',
      );
      final replacement = _mutationChoicesWithInstalledProjectionSets([
        _installedProjectionSetMutationChoice(
          stableArmId: 'arm.control',
          exactRef: group,
        ),
        _installedProjectionSetMutationChoice(
          stableArmId: 'arm.control',
          exactRef: group,
        ),
      ]);

      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-duplicate-draft-arm',
            idempotencyKey: 'idempotency-duplicate-draft-arm',
            payload: {..._draftBinding(), 'replacement': replacement},
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('randomized-unit mutation accepts a default or explicit kind', () {
      for (final randomizedUnitSelection in const [
        {'kind': 'serverDefault'},
        {'kind': 'explicitValue', 'value': 'assignmentSession'},
        {'kind': 'explicitValue', 'value': 'installation'},
      ]) {
        final replacement = _incompleteDraftMutationChoices(
          randomizedUnitSelection: randomizedUnitSelection,
        );
        final request = ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-randomized-unit-choice-1',
            idempotencyKey: 'idempotency-randomized-unit-choice-1',
            payload: {..._draftBinding(), 'replacement': replacement},
          ),
        );
        expect(request.payload['replacement'], replacement);
        expect(
          ExperimentAuthoringRequestV1.fromCanonicalBytes(
            request.canonicalBytes,
          ).canonicalBytes,
          orderedEquals(request.canonicalBytes),
        );
      }

      for (final randomizedUnitSelection in const [
        {'kind': 'unselected'},
        {'kind': 'explicitValue', 'value': 'identifiedUser'},
        {'kind': 'explicitValue', 'value': 'account'},
        {'kind': 'explicitValue', 'value': 'device'},
        {'kind': 'serverDefault', 'value': 'installation'},
        {'kind': 'exactRef', 'exactRef': <String, Object?>{}},
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-randomized-unit-refusal-1',
              idempotencyKey: 'idempotency-randomized-unit-refusal-1',
              payload: {
                ..._draftBinding(),
                'replacement': _incompleteDraftMutationChoices(
                  randomizedUnitSelection: randomizedUnitSelection,
                ),
              },
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('draft reads carry the resolved randomized-unit kind', () {
      final complete = ExperimentDraftViewV1.fromJson(_draftView());
      final partial = ExperimentDraftViewV1.fromJson({
        ..._draftView(),
        'choices': _resolvedPartialDraftChoices(),
        'completeness': const {
          'kind': 'incomplete',
          'missingFieldPaths': ['analysisSelection'],
        },
      });

      expect(
        (complete.choices as ExperimentDraftChoicesV1).randomizedUnitSelection,
        isA<ExperimentRandomizedUnitSelectionV1>(),
      );
      expect(
        (partial.choices as ExperimentResolvedPartialDraftChoicesV1)
            .randomizedUnitSelection,
        isA<ExperimentRandomizedUnitSelectionV1>(),
      );
      expect(
        (complete.choices as ExperimentDraftChoicesV1)
            .randomizedUnitSelection
            .resolvedValue,
        ExperimentRandomizedUnitKindV1.installation,
      );
      expect(complete.toJson(), _draftView());

      for (final (choices, incomplete) in <(Map<String, Object?>, bool)>[
        (_draftChoices(), false),
        (_resolvedPartialDraftChoices(), true),
      ]) {
        for (final randomizedUnitSelection in <Map<String, Object?>>[
          {'kind': 'unselected'},
          {
            'kind': 'serverDefault',
            'resolvedValue': 'assignmentSession',
            'source': const ExperimentRandomizedUnitDefaultsV1().toJson(),
          },
          {'kind': 'explicitValue', 'value': 'device'},
          {'kind': 'exactRef', 'resolvedExactRef': <String, Object?>{}},
        ]) {
          expect(
            () => ExperimentDraftViewV1.fromJson({
              ..._draftView(),
              'choices': {
                ...choices,
                'randomizedUnitSelection': randomizedUnitSelection,
              },
              if (incomplete)
                'completeness': const {
                  'kind': 'incomplete',
                  'missingFieldPaths': ['analysisSelection'],
                },
            }),
            throwsA(isA<CanonicalFormatException>()),
            reason: randomizedUnitSelection.toString(),
          );
        }
      }
    });

    test('draft responses may expose exact resolution for default choices', () {
      final view = ExperimentDraftViewV1.fromJson({
        ..._draftView(),
        'choices': {
          ..._draftChoices(),
          'assignmentAudienceSelection': {
            'kind': 'serverDefault',
            'resolvedExactRef': const {
              'policyId': 'audience.installed',
              'revisionId': 'audience.installed.v2',
              'semanticDigest':
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
            'source': _canonicalAuthorityDefaultSource(
              authorityKind: 'assignmentAudiencePolicy',
              authorityId: 'audience.installed',
              authorityRevisionId: 'audience.installed.v2',
              digestDigit: 'a',
            ),
          },
        },
      });

      expect(view.choices.assignmentAudienceSelection.kind, 'serverDefault');
      expect(
        view.choices.assignmentAudienceSelection.resolvedExactRef,
        isNotNull,
      );
    });

    test('draft reads preserve zero and partial authoring state', () {
      final zeroJson = {
        ..._draftView(),
        'choices': _resolvedPartialDraftChoices(zero: true),
        'completeness': const {
          'kind': 'incomplete',
          'missingFieldPaths': ['arms', 'metricBindings'],
        },
      };
      final zero = ExperimentDraftViewV1.fromJson(zeroJson);
      expect(zero.choices, isA<ExperimentResolvedPartialDraftChoicesV1>());
      final zeroChoices =
          zero.choices as ExperimentResolvedPartialDraftChoicesV1;
      expect(zeroChoices.label, isEmpty);
      expect(zeroChoices.description, isEmpty);
      expect(zeroChoices.arms, isEmpty);
      expect(zeroChoices.metricBindings, isEmpty);
      expect(zero.toJson(), zeroJson);

      final partialJson = {
        ..._draftView(),
        'choices': _resolvedPartialDraftChoices(),
        'completeness': const {
          'kind': 'incomplete',
          'missingFieldPaths': ['analysisSelection'],
        },
      };
      final partial = ExperimentDraftViewV1.fromJson(partialJson);
      final choices =
          partial.choices as ExperimentResolvedPartialDraftChoicesV1;
      expect(choices.label, isEmpty);
      expect(choices.metricBindings.single.label, isEmpty);
      expect(
        choices.metricBindings.single.metricBindingId.value,
        'metric-binding.completed-checkout',
      );
      final projectionSet =
          choices.metricBindings.single.armProjectionSets.single;
      expect(projectionSet.stableArmId.value, 'arm.control');
      final selectedGroup =
          projectionSet.installedProjectionSetChoice.resolvedExactRef!;
      expect(
        selectedGroup.projectionSetReference.projectionSetId.value,
        'installed-projection-set.completed-checkout.control',
      );
      expect(
        selectedGroup.metricBindingReference.metricBindingId.value,
        'installed-binding.completed-checkout.control',
      );
      final member = projectionSet.resolvedMembers.single;
      expect(member.slotId.value, 'slot.checkout.completed');
      expect(
        member.projectionReference.projectionRevisionId.value,
        'projection.checkout.control.v1',
      );
      expect(partial.toJson(), partialJson);
    });

    test('draft choices and completeness must agree', () {
      for (final invalid in <Map<String, Object?>>[
        {
          ..._draftView(),
          'completeness': const {
            'kind': 'incomplete',
            'missingFieldPaths': ['analysisSelection'],
          },
        },
        {
          ..._draftView(),
          'choices': _resolvedPartialDraftChoices(),
        },
      ]) {
        expect(
          () => ExperimentDraftViewV1.fromJson(invalid),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid['completeness'].toString(),
        );
      }
    });

    test('incomplete completeness requires canonical missing paths', () {
      const canonical = <String, Object?>{
        'kind': 'incomplete',
        'missingFieldPaths': ['analysisSelection', 'metricBindings'],
      };
      final completeness = ExperimentDraftCompletenessV1.fromJson(
        canonical,
        path: 'experimentDraftCompleteness',
      );

      expect(
        completeness.missingFieldPaths,
        ['analysisSelection', 'metricBindings'],
      );
      expect(completeness.toJson(), canonical);

      final roundTripped = ExperimentDraftCompletenessV1.fromJson(
        completeness.toJson(),
        path: 'experimentDraftCompleteness',
      );
      expect(roundTripped.toJson(), canonical);
      expect(
        roundTripped.canonicalBytes,
        orderedEquals(completeness.canonicalBytes),
      );

      for (final invalid in const <Map<String, Object?>>[
        {'kind': 'incomplete', 'missingFieldPaths': []},
        {
          'kind': 'incomplete',
          'missingFieldPaths': ['metricBindings', 'analysisSelection'],
        },
      ]) {
        expect(
          () => ExperimentDraftCompletenessV1.fromJson(
            invalid,
            path: 'experimentDraftCompleteness',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('complete draft views resolve required choices and arm sets', () {
      Map<String, Object?> completeView(Map<String, Object?> choices) => {
            ..._draftView(),
            'choices': choices,
          };

      final unselectedMetric = _draftChoices();
      final metricBinding = Map<String, Object?>.from(
        (unselectedMetric['metricBindings']! as List).first as Map,
      )..['metricDefinitionChoice'] = const {'kind': 'unselected'};
      unselectedMetric['metricBindings'] = [
        metricBinding,
        ...((unselectedMetric['metricBindings']! as List).skip(1)),
      ];

      final allocationMismatch = _draftChoices();
      final analysis = Map<String, Object?>.from(
        allocationMismatch['analysisSelection']! as Map,
      );
      final planning = Map<String, Object?>.from(
        analysis['planningSelection']! as Map,
      )..['allocationWeights'] = const [
          {'armId': 'arm.control', 'relativeWeight': 1},
          {'armId': 'arm.other', 'relativeWeight': 1},
        ];
      analysis['planningSelection'] = planning;
      allocationMismatch['analysisSelection'] = analysis;

      final projectionMismatch = _draftChoices();
      final projectionBinding = Map<String, Object?>.from(
        (projectionMismatch['metricBindings']! as List).first as Map,
      );
      final projectionSets = List<Map<String, Object?>>.from(
        projectionBinding['armProjectionSets']! as List,
      );
      projectionBinding['armProjectionSets'] = [
        projectionSets.first,
        Map<String, Object?>.from(projectionSets.last)
          ..['stableArmId'] = 'arm.other',
      ];
      projectionMismatch['metricBindings'] = [
        projectionBinding,
        ...((projectionMismatch['metricBindings']! as List).skip(1)),
      ];

      final unresolved = <Map<String, Object?>>[
        _draftChoices()..['arms'] = <Object?>[],
        _draftChoices()
          ..['rootSurfaceSelection'] = const {'kind': 'unselected'},
        _draftChoices()
          ..['assignmentAudienceSelection'] = const {'kind': 'unselected'},
        _draftChoices()
          ..['assignmentEligibilitySelection'] = const {'kind': 'unselected'},
        _draftChoices()..['memberNoTreatment'] = const {'kind': 'unselected'},
        _draftChoices()
          ..['primaryBindingSelection'] = const {'kind': 'unselected'},
        _draftChoices()..['analysisSelection'] = const {'kind': 'unselected'},
        unselectedMetric,
        allocationMismatch,
        projectionMismatch,
      ];
      for (final choices in unresolved) {
        expect(
          () => ExperimentDraftViewV1.fromJson(completeView(choices)),
          throwsA(isA<CanonicalFormatException>()),
          reason: choices.toString(),
        );
      }
    });

    test(
      'partial projection reads retain a complete selected group',
      () {
        final json = {
          ..._draftView(),
          'choices': _resolvedPartialDraftChoices(),
          'completeness': const {
            'kind': 'incomplete',
            'missingFieldPaths': ['analysisSelection'],
          },
        };
        final view = ExperimentDraftViewV1.fromJson(json);
        final set = (view.choices as ExperimentResolvedPartialDraftChoicesV1)
            .metricBindings
            .single
            .armProjectionSets
            .single;
        final selected = set.installedProjectionSetChoice.resolvedExactRef!;

        expect(
          selected.projectionSetReference.projectionSetId.value,
          'installed-projection-set.completed-checkout.control',
        );
        expect(set.resolvedMembers, selected.members);
        expect(
          set.resolvedMembers.single.projectionReference.projectionRevisionId
              .value,
          'projection.checkout.control.v1',
        );

        final roundTripped = ExperimentDraftViewV1.fromJson(view.toJson());
        expect(roundTripped.toJson(), json);
        expect(
          roundTripped.canonicalBytes,
          orderedEquals(view.canonicalBytes),
        );
      },
    );

    test('partial projection identities reject duplicate stable IDs or slots',
        () {
      for (final projections in <List<Map<String, Object?>>>[
        [
          _partialProjectionChoice(
            'projection.checkout.control',
            'slot.checkout.completed',
          ),
          _partialProjectionChoice(
            'projection.checkout.control',
            'slot.checkout.repeated',
          ),
        ],
        [
          _partialProjectionChoice(
            'projection.checkout.control',
            'slot.checkout.completed',
          ),
          _partialProjectionChoice(
            'projection.checkout.other',
            'slot.checkout.completed',
          ),
        ],
      ]) {
        expect(
          () => ExperimentDraftViewV1.fromJson(
            _partialDraftViewWithProjections(projections),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: projections.toString(),
        );
      }
    });

    test('partial draft views reject a server-default primary binding', () {
      final json = _partialDraftViewWithProjections([
        _partialProjectionChoice(
          'projection.checkout.control',
          'slot.checkout.completed',
        ),
      ]);
      final choices = Map<String, Object?>.from(json['choices']! as Map)
        ..['primaryBindingSelection'] = const {
          'kind': 'serverDefault',
          'resolvedExactRef': {
            'metricBindingId': 'metric-binding.completed-checkout',
          },
        };
      json['choices'] = choices;

      expect(
        () => ExperimentDraftViewV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('keeps proprietary candidate types outside the public schema', () {
      final source = _experimentAuthoringSourceFile().readAsStringSync();

      for (final name in const <String>{
        'ExperimentAuthoringResolvedCandidateV1',
        'FullCandidatePublicationRefV1',
        'familyReference',
        'fullBasePublication',
        'fullOutputPublication',
      }) {
        expect(source, isNot(contains(name)), reason: name);
      }
    });

    test('freezes an independent canonical request literal', () {
      const expected = '{"correlationId":"correlation-validate-1",'
          '"kind":"experimentAuthoringRequest",'
          '"operation":"validateDraft",'
          '"payload":{"draftId":"experiment-draft-checkout",'
          '"draftRevisionId":"experiment-draft-checkout.v3",'
          '"expectedCas":"draft-cas-3"},"schemaVersion":1}';
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'validateDraft',
          correlationId: 'correlation-validate-1',
          payload: _draftBinding(),
        ),
      );

      expect(request.canonicalBytes, orderedEquals(utf8.encode(expected)));
      expect(
        ExperimentAuthoringRequestV1.fromCanonicalBytes(utf8.encode(expected))
            .canonicalBytes,
        orderedEquals(utf8.encode(expected)),
      );
    });
  });

  group('analysis selection', () {
    test('pins the public statistical defaults value and strict wire', () {
      const defaults = ExperimentStatisticalDefaultsV1();

      expect(defaults.toJson(), _statisticalDefaults());
      expect(
        utf8.decode(defaults.canonicalBytes),
        '{"alpha":{"denominator":20,"numerator":1},'
        '"kind":"experimentStatisticalDefaultsV1",'
        '"margin":{"denominator":100,"numerator":1},'
        '"power":{"denominator":5,"numerator":4}}',
      );
      expect(
        ExperimentStatisticalDefaultsV1.fromCanonicalBytes(
          defaults.canonicalBytes,
        ).canonicalBytes,
        orderedEquals(defaults.canonicalBytes),
      );

      for (final invalid in <Map<String, Object?>>[
        {..._statisticalDefaults(), 'alpha': _rational(1, 10)},
        {..._statisticalDefaults(), 'power': _rational(9, 10)},
        {
          ..._statisticalDefaults(),
          'margin': _rational(1, 50),
        },
        {..._statisticalDefaults()}..remove('alpha'),
        {..._statisticalDefaults(), 'extra': true},
        {..._statisticalDefaults(), 'schemaVersion': 1},
        {..._statisticalDefaults(), 'target': _target()},
        {..._statisticalDefaults(), 'defaultsId': 'defaults.other'},
        {..._statisticalDefaults(), 'policyId': 'policy.defaults'},
        {..._statisticalDefaults(), 'revisionId': 'defaults.v2'},
        {..._statisticalDefaults(), 'ordinal': 2},
        {
          ..._statisticalDefaults(),
          'reference': const {'kind': 'exactRef'},
        },
        {..._statisticalDefaults(), 'dependency': _digest('0')},
        {..._statisticalDefaults(), 'adapter': 'adapter.defaults'},
        {..._statisticalDefaults(), 'resolver': 'resolver.defaults'},
        {
          ..._statisticalDefaults(),
          'source': const {'kind': 'catalog'},
        },
      ]) {
        expect(
          () => ExperimentStatisticalDefaultsV1.fromJson(invalid),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('pins the public randomized-unit default value and strict wire', () {
      const defaults = ExperimentRandomizedUnitDefaultsV1();
      const json = {
        'kind': 'experimentRandomizedUnitDefaultsV1',
        'randomizedUnitKind': 'installation',
      };

      expect(defaults.toJson(), json);
      expect(
        utf8.decode(defaults.canonicalBytes),
        '{"kind":"experimentRandomizedUnitDefaultsV1",'
        '"randomizedUnitKind":"installation"}',
      );
      expect(
        ExperimentRandomizedUnitDefaultsV1.fromCanonicalBytes(
          defaults.canonicalBytes,
        ).canonicalBytes,
        orderedEquals(defaults.canonicalBytes),
      );
      final resolved = ExperimentRandomizedUnitSelectionV1.fromJson(
        const {
          'kind': 'serverDefault',
          'resolvedValue': 'installation',
          'source': json,
        },
        path: 'randomizedUnitSelection',
      );
      expect(
        resolved.resolvedValue,
        ExperimentRandomizedUnitKindV1.installation,
      );
      expect(resolved.source?.toJson(), json);

      for (final invalid in <Map<String, Object?>>[
        {...json, 'randomizedUnitKind': 'assignmentSession'},
        {...json, 'extra': true},
        {...json, 'target': _target()},
        {...json, 'revisionId': 'randomized-unit-defaults.v1'},
      ]) {
        expect(
          () => ExperimentRandomizedUnitDefaultsV1.fromJson(invalid),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('keeps measure-only and fixed-horizon choices distinct', () {
      final measureOnly = ExperimentAnalysisSelectionV1.fromJson(const {
        'kind': 'measureOnly',
      });
      final fixedHorizon = ExperimentAnalysisSelectionV1.fromJson({
        'kind': 'fixedHorizonNArmRate',
        'planningSelection': _planningSelection(),
      });

      expect(measureOnly, isA<ExperimentMeasureOnlySelectionV1>());
      expect(fixedHorizon, isA<ExperimentFixedHorizonNArmRateSelectionV1>());
      expect(measureOnly.toJson(), const {'kind': 'measureOnly'});
      expect(fixedHorizon.toJson(), {
        'kind': 'fixedHorizonNArmRate',
        'planningSelection': _planningSelection(),
      });
    });

    test('pins direct inputs and safe resolved planning choices', () {
      final selection = ExperimentNArmPlanningSelectionV1.fromJson(
        _planningSelection(),
      );

      expect(selection.referenceArmId.value, 'arm.control');
      expect(selection.direction.wireName, 'higherIsBetter');
      expect(selection.expectedBaseline.toJson(), {
        'denominator': 10,
        'numerator': 1,
      });
      expect(selection.minimumDetectableEffect.toJson(), {
        'denominator': 50,
        'numerator': 1,
      });
      expect(
        selection.practicalSuperiorityMarginChoice.toJson(),
        _resolvedDefaultChoice(_rational(1, 100)),
      );
      expect(
        selection.alphaChoice.toJson(),
        _resolvedDefaultChoice(_rational(1, 20)),
      );
      expect(
        selection.primaryTargetPowerChoice.toJson(),
        _resolvedDefaultChoice(_rational(4, 5)),
      );
      expect(selection.enrollmentCap, 12000);
      expect(selection.followUpDurationMicros, 86400000000);
      expect(selection.maximumEnrollmentDurationMicros, 1209600000000);
      expect(selection.outcomeGracePeriodMicros, 172800000000);
      expect(
        selection.allocationWeights.map((weight) => weight.toJson()),
        [
          {'armId': 'arm.control', 'relativeWeight': 1},
          {'armId': 'arm.variant', 'relativeWeight': 1},
        ],
      );
      expect(
        ExperimentNArmPlanningSelectionV1.fromCanonicalBytes(
          selection.canonicalBytes,
        ).canonicalBytes,
        orderedEquals(selection.canonicalBytes),
      );
      _expectNoSensitiveKeys(selection.toJson());
    });

    test('closes resolved planning cross-field domains', () {
      final invalid = <(String, Map<String, Object?>)>[
        (
          'higher direction leaves probability domain',
          {
            ..._planningSelection(),
            'expectedBaseline': _rational(99, 100),
            'minimumDetectableEffect': _rational(1, 50),
          },
        ),
        (
          'lower direction leaves probability domain',
          {
            ..._planningSelection(),
            'direction': 'lowerIsBetter',
            'expectedBaseline': _rational(1, 100),
            'minimumDetectableEffect': _rational(1, 50),
          },
        ),
        (
          'margin reaches planned effect',
          {
            ..._planningSelection(explicit: true),
            'minimumDetectableEffect': _rational(1, 50),
            'practicalSuperiorityMarginChoice':
                _explicitChoice(_rational(1, 50)),
          },
        ),
        (
          'guardrail harm boundary reaches one',
          {
            ..._planningSelection(),
            'guardrails': [
              {
                ...(_planningSelection()['guardrails']! as List).single
                    as Map<String, Object?>,
                'expectedReferenceRate': _rational(99, 100),
                'harmMargin': _rational(1, 100),
              },
            ],
          },
        ),
      ];
      for (final entry in invalid) {
        expect(
          () => ExperimentNArmPlanningSelectionV1.fromJson(entry.$2),
          throwsA(isA<CanonicalFormatException>()),
          reason: entry.$1,
        );
      }
    });

    test('orients guardrail harm margins around the reference rate', () {
      Map<String, Object?> withGuardrail({
        required String adverseDirection,
        required int baselineNumerator,
      }) {
        final selection = _planningSelection();
        final guardrail = Map<String, Object?>.from(
          (selection['guardrails']! as List).single as Map,
        )
          ..['adverseDirection'] = adverseDirection
          ..['expectedReferenceRate'] = _rational(baselineNumerator, 100)
          ..['harmMargin'] = _rational(1, 100);
        selection['guardrails'] = [guardrail];
        return selection;
      }

      for (final vector in <(String, int, int)>[
        ('higherIsWorse', 98, 99),
        ('lowerIsWorse', 2, 1),
      ]) {
        expect(
          () => ExperimentNArmPlanningSelectionV1.fromJson(
            withGuardrail(
              adverseDirection: vector.$1,
              baselineNumerator: vector.$2,
            ),
          ),
          returnsNormally,
          reason: '${vector.$1} just inside the open domain',
        );
        expect(
          () => ExperimentNArmPlanningSelectionV1.fromJson(
            withGuardrail(
              adverseDirection: vector.$1,
              baselineNumerator: vector.$3,
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: '${vector.$1} at the open-domain boundary',
        );
      }
    });

    test('accepts only closed safe-read planning choice branches', () {
      final explicit = ExperimentNArmPlanningSelectionV1.fromJson(
        _planningSelection(explicit: true),
      );
      expect(
        explicit.practicalSuperiorityMarginChoice.toJson(),
        _explicitChoice(_rational(1, 100)),
      );

      final invalidChoices = <Map<String, Object?>>[
        {
          'kind': 'serverDefault',
          'resolvedValue': _rational(1, 50),
          'source': _statisticalDefaults(),
        },
        {
          'kind': 'serverDefault',
          'resolvedValue': _rational(1, 100),
          'source': {
            ..._statisticalDefaults(),
            'alpha': _rational(1, 10),
          },
        },
        {
          ..._explicitChoice(_rational(1, 100)),
          'source': _statisticalDefaults(),
        },
      ];
      for (final choice in invalidChoices) {
        expect(
          () => ExperimentNArmPlanningSelectionV1.fromJson({
            ..._planningSelection(),
            'practicalSuperiorityMarginChoice': choice,
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: choice.toString(),
        );
      }

      for (final invalid in <(String, Map<String, Object?>)>[
        (
          'alphaChoice',
          _resolvedDefaultChoice(_rational(1, 10)),
        ),
        (
          'primaryTargetPowerChoice',
          _resolvedDefaultChoice(_rational(9, 10)),
        ),
      ]) {
        expect(
          () => ExperimentNArmPlanningSelectionV1.fromJson({
            ..._planningSelection(),
            invalid.$1: invalid.$2,
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.$1,
        );
      }
    });

    test('mutation accepts only unresolved default or explicit values', () {
      for (final planning in <Map<String, Object?>>[
        _planningMutationSelection(),
        _planningMutationSelection(explicit: true),
      ]) {
        final request = ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-planning-choice',
            idempotencyKey: 'idempotency-planning-choice',
            payload: {
              ..._draftBinding(),
              'replacement': _fixedHorizonMutationChoices(planning),
            },
          ),
        );
        expect(
          (request.payload['replacement']! as Map)['analysisSelection'],
          {'kind': 'fixedHorizonNArmRate', 'planningSelection': planning},
        );
      }

      for (final invalidChoice in <Map<String, Object?>>[
        {
          'kind': 'serverDefault',
          'resolvedValue': _rational(1, 100),
        },
        {'kind': 'serverDefault', 'source': _statisticalDefaults()},
        {
          ..._explicitChoice(_rational(1, 100)),
          'source': _statisticalDefaults(),
        },
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-invalid-planning-choice',
              idempotencyKey: 'idempotency-invalid-planning-choice',
              payload: {
                ..._draftBinding(),
                'replacement': _fixedHorizonMutationChoices({
                  ..._planningMutationSelection(),
                  'practicalSuperiorityMarginChoice': invalidChoice,
                }),
              },
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalidChoice.toString(),
        );
      }

      for (final oldField in const [
        'alpha',
        'direction',
        'power',
        'practicalSuperiorityMargin',
      ]) {
        final planning = _planningMutationSelection()
          ..[oldField] = _rational(1, 20);
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-old-planning-field',
              idempotencyKey: 'idempotency-old-planning-field',
              payload: {
                ..._draftBinding(),
                'replacement': _fixedHorizonMutationChoices(planning),
              },
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: oldField,
        );
      }

      final adapterOwned = _planningMutationSelection()
        ..['registeredAdapterSelection'] =
            _planningSelection()['registeredAdapterSelection'];
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-adapter-owned-field',
            idempotencyKey: 'idempotency-adapter-owned-field',
            payload: {
              ..._draftBinding(),
              'replacement': _fixedHorizonMutationChoices(adapterOwned),
            },
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );

      for (final requiredField in const [
        'expectedBaseline',
        'minimumDetectableEffect',
        'enrollmentCap',
        'followUpDurationMicros',
        'maximumEnrollmentDurationMicros',
        'outcomeGracePeriodMicros',
      ]) {
        final planning = _planningMutationSelection()..remove(requiredField);
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-missing-planning-input',
              idempotencyKey: 'idempotency-missing-planning-input',
              payload: {
                ..._draftBinding(),
                'replacement': _fixedHorizonMutationChoices(planning),
              },
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: requiredField,
        );
      }
    });

    test('mutation rejects invalid planning values and arm allocations', () {
      final invalidPlanningSelections = <(String, Map<String, Object?>)>[
        (
          'zero baseline',
          {
            ..._planningMutationSelection(),
            'expectedBaseline': _rational(0, 1),
          },
        ),
        (
          'unit baseline',
          {
            ..._planningMutationSelection(),
            'expectedBaseline': _rational(1, 1),
          },
        ),
        (
          'baseline above one',
          {
            ..._planningMutationSelection(),
            'expectedBaseline': _rational(11, 10),
          },
        ),
        (
          'zero minimum detectable effect',
          {
            ..._planningMutationSelection(),
            'minimumDetectableEffect': _rational(0, 1),
          },
        ),
        (
          'zero explicit margin',
          {
            ..._planningMutationSelection(),
            'practicalSuperiorityMarginChoice':
                _explicitChoice(_rational(0, 1)),
          },
        ),
        (
          'unsupported explicit alpha',
          {
            ..._planningMutationSelection(),
            'alphaChoice': _explicitChoice(_rational(1, 10)),
          },
        ),
        (
          'unsupported explicit power',
          {
            ..._planningMutationSelection(),
            'primaryTargetPowerChoice': _explicitChoice(_rational(3, 4)),
          },
        ),
        (
          'zero enrollment cap',
          {..._planningMutationSelection(), 'enrollmentCap': 0},
        ),
        (
          'zero follow-up duration',
          {..._planningMutationSelection(), 'followUpDurationMicros': 0},
        ),
        (
          'zero maximum enrollment duration',
          {
            ..._planningMutationSelection(),
            'maximumEnrollmentDurationMicros': 0,
          },
        ),
        (
          'negative outcome grace period',
          {..._planningMutationSelection(), 'outcomeGracePeriodMicros': -1},
        ),
        (
          'zero allocation weight',
          {
            ..._planningMutationSelection(),
            'allocationWeights': const [
              {'armId': 'arm.control', 'relativeWeight': 0},
              {'armId': 'arm.variant', 'relativeWeight': 1},
            ],
          },
        ),
        (
          'allocation weight above limit',
          {
            ..._planningMutationSelection(),
            'allocationWeights': const [
              {'armId': 'arm.control', 'relativeWeight': 101},
              {'armId': 'arm.variant', 'relativeWeight': 1},
            ],
          },
        ),
        (
          'zero guardrail reference rate',
          {
            ..._planningMutationSelection(),
            'guardrails': [
              {
                ...(_planningMutationSelection()['guardrails']! as List).single
                    as Map<String, Object?>,
                'expectedReferenceRate': _rational(0, 1),
              },
            ],
          },
        ),
        (
          'unsupported guardrail power',
          {
            ..._planningMutationSelection(),
            'guardrails': [
              {
                ...(_planningMutationSelection()['guardrails']! as List).single
                    as Map<String, Object?>,
                'targetPower': _rational(3, 4),
              },
            ],
          },
        ),
        (
          'margin reaches planned effect',
          {
            ..._planningMutationSelection(explicit: true),
            'minimumDetectableEffect': _rational(1, 50),
            'practicalSuperiorityMarginChoice':
                _explicitChoice(_rational(1, 50)),
          },
        ),
        (
          'duplicate allocation arm',
          {
            ..._planningMutationSelection(),
            'allocationWeights': const [
              {'armId': 'arm.control', 'relativeWeight': 1},
              {'armId': 'arm.control', 'relativeWeight': 1},
            ],
          },
        ),
        (
          'unallocated reference arm',
          {
            ..._planningMutationSelection(),
            'referenceArmId': 'arm.unallocated',
          },
        ),
      ];

      for (final invalid in invalidPlanningSelections) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-invalid-planning-value',
              idempotencyKey: 'idempotency-invalid-planning-value',
              payload: {
                ..._draftBinding(),
                'replacement': _fixedHorizonMutationChoices(invalid.$2),
              },
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.$1,
        );
      }
    });

    test('derives mutation direction from the exact primary metric', () {
      for (final invalid in <(String, Map<String, Object?>)>[
        (
          'higherIsBetter',
          {
            ..._planningMutationSelection(),
            'expectedBaseline': _rational(99, 100),
            'minimumDetectableEffect': _rational(1, 50),
          },
        ),
        (
          'lowerIsBetter',
          {
            ..._planningMutationSelection(),
            'expectedBaseline': _rational(1, 100),
            'minimumDetectableEffect': _rational(1, 50),
          },
        ),
        ('none', _planningMutationSelection()),
      ]) {
        final replacement = _incompleteDraftMutationChoices(
          planningSelection: invalid.$2,
          primaryBindingSelection: const {
            'kind': 'exactRef',
            'exactRef': {
              'metricBindingId': 'metric-binding.completed-checkout',
            },
          },
          metricDefinitionSelection: {
            'kind': 'exactRef',
            'exactRef': _metricDefinitionReference(direction: invalid.$1),
          },
        );
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-derived-${invalid.$1}',
              idempotencyKey: 'idempotency-derived-${invalid.$1}',
              payload: {..._draftBinding(), 'replacement': replacement},
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.$1,
        );
      }
    });

    test('derives mutation guardrail direction from its exact metric', () {
      for (final invalid in <(String, int)>[
        ('higherIsBetter', 1),
        ('lowerIsBetter', 99),
      ]) {
        final planning = _planningMutationSelection();
        planning['guardrails'] = [
          {
            ...(_planningMutationSelection()['guardrails']! as List).single
                as Map<String, Object?>,
            'expectedReferenceRate': _rational(invalid.$2, 100),
            'harmMargin': _rational(1, 100),
          },
        ];
        final replacement = _incompleteDraftMutationChoices(
          planningSelection: planning,
          metricDefinitionSelection: {
            'kind': 'exactRef',
            'exactRef': _metricDefinitionReference(direction: invalid.$1),
          },
        );
        replacement['guardrails'] = const [
          {
            'guardrailId': 'guardrail.checkout-errors',
            'kind': 'experimentDraftGuardrailChoice',
            'metricBindingId': 'metric-binding.completed-checkout',
          },
        ];
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'replaceDraft',
              correlationId: 'correlation-guardrail-${invalid.$1}',
              idempotencyKey: 'idempotency-guardrail-${invalid.$1}',
              payload: {..._draftBinding(), 'replacement': replacement},
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.$1,
        );
      }
    });

    test('rejects planner-owned values in the public selection', () {
      for (final key in [
        'certifiedScales',
        'certificate',
        'designRevisionId',
        'experimentEpochId',
        'plannerRuntime',
      ]) {
        expect(
          () => ExperimentNArmPlanningSelectionV1.fromJson({
            ..._planningSelection(),
            key: 'not-admitted',
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: key,
        );
      }
    });
  });

  group('resolved draft references', () {
    test('keeps server-default provenance strict and branch-specific', () {
      final sources = <Map<String, Object?>>[
        _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'audience.installed',
          authorityRevisionId: 'audience.installed.v1',
          digestDigit: 'a',
        ),
        _publicationCandidateDefaultSource(
          _exactCandidate(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
        ),
        _installedProjectionDefaultSource(
          'projection.checkout.control.v1',
          'd',
        ),
      ];

      for (final source in sources) {
        expect(
          ExperimentResolvedDefaultSourceV1.fromJson(
            source,
            path: 'source',
          ).toJson(),
          source,
        );
      }

      final policyDefault = {
        'kind': 'serverDefault',
        'resolvedExactRef': _policyReference('audience.installed'),
        'source': sources.first,
      };
      final policy = ExperimentPolicySelectionV1.fromJson(
        policyDefault,
        path: 'policy',
      );
      expect(policy.source, isA<ExperimentCanonicalAuthorityDefaultSourceV1>());
      expect(policy.toJson(), policyDefault);

      final surfaceDefault = {
        'kind': 'serverDefault',
        'resolvedExactRef': _surfaceReference(
          'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        ),
        'source': sources[1],
      };
      final surface = ExperimentSurfaceSelectionV1.fromJson(
        surfaceDefault,
        path: 'surface',
      );
      expect(
        surface.source,
        isA<ExperimentPublicationCandidateDefaultSourceV1>(),
      );

      for (final invalid in <Map<String, Object?>>[
        Map<String, Object?>.from(policyDefault)..remove('source'),
        {
          'kind': 'exactRef',
          'resolvedExactRef': _policyReference('audience.installed'),
          'source': sources.first,
        },
        {'kind': 'unselected', 'source': sources.first},
        {
          ...policyDefault,
          'source': _canonicalAuthorityDefaultSource(
            authorityKind: 'metricDefinition',
            authorityId: 'audience.installed',
            authorityRevisionId: 'audience.installed.v1',
            digestDigit: 'a',
          ),
        },
      ]) {
        expect(
          () => ExperimentPolicySelectionV1.fromJson(
            invalid,
            path: 'policy',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }

      for (final invalidSource in <Map<String, Object?>>[
        {...sources.first, 'unexpected': true},
        {...sources.first, 'authorityKind': 'randomizedUnitPolicy'},
        {...sources[1]}..remove('candidate'),
        {...sources[2], 'projectionId': 'projection.checkout.control'},
      ]) {
        expect(
          () => ExperimentResolvedDefaultSourceV1.fromJson(
            invalidSource,
            path: 'source',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalidSource.toString(),
        );
      }
    });

    test('requires resolved default sources to name selected authorities', () {
      void expectRejected(Map<String, Object?> choices) {
        expect(
          () => ExperimentDraftViewV1.fromJson({
            ..._draftView(),
            'choices': choices,
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: choices.toString(),
        );
      }

      Map<String, Object?> pointCandidate(String artifactDigest) => {
            ..._exactCandidate(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
            'treatmentOrigin': {
              'basePublicationContext': {
                'artifactGraphHash': _digest(artifactDigest),
                'kind': 'exactSurfaceContext',
                'measurementManifestHash': _digest('4'),
                'surfaceReference': _surfaceReference('surface.checkout.v3'),
              },
              'kind': 'pointSubtree',
              'loci': [
                {
                  'locusId': 'locus.checkout.submit',
                  'pointLineageCanonicalHash': _digest('5'),
                  'presentedPointLineageId': 'point-lineage.checkout.submit',
                },
              ],
            },
          };

      for (final source in <Map<String, Object?>>[
        _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentEligibilityPolicy',
          authorityId: 'audience.installed',
          authorityRevisionId: 'audience.installed.v2',
          digestDigit: 'a',
        ),
        _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'audience.other',
          authorityRevisionId: 'audience.installed.v2',
          digestDigit: 'a',
        ),
        _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'audience.installed',
          authorityRevisionId: 'audience.installed.v3',
          digestDigit: 'a',
        ),
        _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'audience.installed',
          authorityRevisionId: 'audience.installed.v2',
          digestDigit: 'b',
        ),
      ]) {
        final choices = _draftChoices()
          ..['assignmentAudienceSelection'] = {
            'kind': 'serverDefault',
            'resolvedExactRef': const {
              'policyId': 'audience.installed',
              'revisionId': 'audience.installed.v2',
              'semanticDigest': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
            'source': source,
          };
        expectRejected(choices);
      }

      for (final source in <Map<String, Object?>>[
        _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'audience.installed',
          authorityRevisionId: 'audience.installed.v2',
          digestDigit: 'a',
        ),
        _publicationCandidateDefaultSource(
          _exactCandidate('surface.catalog.v4'),
        ),
        _publicationCandidateDefaultSource(
          _exactCandidate(
            'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
          ),
        ),
      ]) {
        final choices = _draftChoices()
          ..['memberNoTreatment'] = {
            'kind': 'serverDefault',
            'resolvedExactRef': _exactCandidate(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
            'source': source,
          };
        expectRejected(choices);
      }

      final pointChoices = _draftChoices()
        ..['memberNoTreatment'] = {
          'kind': 'serverDefault',
          'resolvedExactRef': pointCandidate('3'),
          'source': _publicationCandidateDefaultSource(pointCandidate('6')),
        };
      expectRejected(pointChoices);

      final rootChoices = _draftChoices()
        ..['rootSurfaceSelection'] = {
          'kind': 'serverDefault',
          'resolvedExactRef': _surfaceReference(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
          'source': _publicationCandidateDefaultSource(
            _exactCandidate(
              'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
            ),
          ),
        };
      expectRejected(rootChoices);

      Map<String, Object?> choicesWithMetricDefinitionSource(
        Map<String, Object?> source,
      ) {
        final choices = _draftChoices();
        final bindings = List<Map<String, Object?>>.from(
          choices['metricBindings']! as List,
        );
        final binding = Map<String, Object?>.from(bindings.first)
          ..['metricDefinitionChoice'] = {
            'kind': 'serverDefault',
            'resolvedExactRef': _metricDefinitionReference(),
            'source': source,
          };
        bindings[0] = binding;
        choices['metricBindings'] = bindings;
        return choices;
      }

      for (final source in <Map<String, Object?>>[
        _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'metric.completed-checkout',
          authorityRevisionId: 'metric.completed-checkout.v2',
          digestDigit: '1',
        ),
        _canonicalAuthorityDefaultSource(
          authorityKind: 'metricDefinition',
          authorityId: 'metric.other',
          authorityRevisionId: 'metric.completed-checkout.v2',
          digestDigit: '1',
        ),
        _canonicalAuthorityDefaultSource(
          authorityKind: 'metricDefinition',
          authorityId: 'metric.completed-checkout',
          authorityRevisionId: 'metric.completed-checkout.v3',
          digestDigit: '1',
        ),
        _canonicalAuthorityDefaultSource(
          authorityKind: 'metricDefinition',
          authorityId: 'metric.completed-checkout',
          authorityRevisionId: 'metric.completed-checkout.v2',
          digestDigit: '2',
        ),
      ]) {
        expectRejected(choicesWithMetricDefinitionSource(source));
      }

      Map<String, Object?> choicesWithProjectionSource(
        Map<String, Object?> source,
      ) {
        final choices = _draftChoices();
        final bindings = List<Map<String, Object?>>.from(
          choices['metricBindings']! as List,
        );
        final binding = Map<String, Object?>.from(bindings.first);
        final sets = List<Map<String, Object?>>.from(
          binding['armProjectionSets']! as List,
        );
        final set = Map<String, Object?>.from(sets.first);
        final selectedChoice = Map<String, Object?>.from(
          set['installedProjectionSetChoice']! as Map,
        );
        set['installedProjectionSetChoice'] = {
          'kind': 'serverDefault',
          'resolvedExactRef': selectedChoice['resolvedExactRef'],
          'source': source,
        };
        sets[0] = set;
        binding['armProjectionSets'] = sets;
        bindings[0] = binding;
        choices['metricBindings'] = bindings;
        return choices;
      }

      for (final source in <Map<String, Object?>>[
        _canonicalAuthorityDefaultSource(
          authorityKind: 'metricDefinition',
          authorityId: 'metric.completed-checkout',
          authorityRevisionId: 'metric.completed-checkout.v2',
          digestDigit: '1',
        ),
        _installedProjectionDefaultSource(
          'projection.metric-binding.completed-checkout.control.v2',
          '1',
        ),
        {
          ..._installedProjectionDefaultSource(
            'projection.metric-binding.completed-checkout.control.v1',
            '1',
          ),
          'canonicalDigest': _digest('2'),
        },
        {
          ..._installedProjectionDefaultSource(
            'projection.metric-binding.completed-checkout.control.v1',
            '1',
          ),
          'semanticDigest': _digest('2'),
        },
      ]) {
        expectRejected(choicesWithProjectionSource(source));
      }
    });

    test('preserves exact whole-surface and point-subtree origins', () {
      final wholeJson = {
        ..._exactCandidate(
          'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        ),
        'treatmentOrigin': const {
          'kind': 'wholeSurface',
          'locusIds': ['locus.checkout.body'],
        },
      };
      final whole = ExperimentExactCandidateV1.fromJson(
        wholeJson,
        path: 'candidate',
      );
      expect(
        (whole.treatmentOrigin as ExperimentWholeSurfaceTreatmentOriginV1)
            .locusIds
            .map((value) => value.value),
        ['locus.checkout.body'],
      );
      expect(whole.toJson(), wholeJson);

      final pointJson = {
        ..._exactCandidate(
          'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
        ),
        'treatmentOrigin': {
          'basePublicationContext': {
            'artifactGraphHash': _digest('3'),
            'kind': 'exactSurfaceContext',
            'measurementManifestHash': _digest('4'),
            'surfaceReference': _surfaceReference(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
          },
          'kind': 'pointSubtree',
          'loci': [
            {
              'locusId': 'locus.checkout.submit',
              'pointLineageCanonicalHash': _digest('6'),
              'presentedPointLineageId': 'point-lineage.checkout.submit',
            },
            {
              'locusId': 'locus.checkout.total',
              'pointLineageCanonicalHash': _digest('5'),
              'presentedPointLineageId': 'point-lineage.checkout.total',
            },
          ],
        },
      };
      final point = ExperimentExactCandidateV1.fromJson(
        pointJson,
        path: 'candidate',
      );
      final pointOrigin =
          point.treatmentOrigin as ExperimentPointSubtreeTreatmentOriginV1;
      expect(pointOrigin.loci, hasLength(2));
      expect(
        pointOrigin
            .basePublicationContext.surfaceReference.surfaceRevisionId.value,
        'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
      );
      expect(pointOrigin.toJson(), pointJson['treatmentOrigin']);

      final maximumPointLoci = List<Object?>.generate(
        1024,
        (index) {
          final suffix = index.toString().padLeft(4, '0');
          return {
            'locusId': 'locus.checkout.$suffix',
            'pointLineageCanonicalHash': _digest('6'),
            'presentedPointLineageId': 'point-lineage.checkout.$suffix',
          };
        },
      );
      final maximumPoint = ExperimentExactCandidateV1.fromJson(
        {
          ..._exactCandidate(
            'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
          ),
          'treatmentOrigin': {
            ...(pointJson['treatmentOrigin']! as Map<String, Object?>),
            'loci': maximumPointLoci,
          },
        },
        path: 'candidate',
      );
      expect(
        (maximumPoint.treatmentOrigin
                as ExperimentPointSubtreeTreatmentOriginV1)
            .loci,
        hasLength(1024),
      );

      final invalidOrigins = <Map<String, Object?>>[
        const {'kind': 'wholeSurface', 'locusId': 'locus.checkout'},
        const {
          'kind': 'wholeSurface',
          'locusIds': ['locus.checkout', 'locus.checkout'],
        },
        const {
          'kind': 'wholeSurface',
          'locusIds': ['locus.checkout.footer', 'locus.checkout.body'],
        },
        const {'kind': 'wholeSurface', 'locusIds': <Object?>[]},
        {
          ...(pointJson['treatmentOrigin']! as Map<String, Object?>),
          'loci': [
            ...maximumPointLoci,
            {
              'locusId': 'locus.checkout.1024',
              'pointLineageCanonicalHash': _digest('6'),
              'presentedPointLineageId': 'point-lineage.checkout.1024',
            },
          ],
        },
        {
          ...(pointJson['treatmentOrigin']! as Map<String, Object?>),
          'basePublicationContext': {
            ...((pointJson['treatmentOrigin']!
                    as Map<String, Object?>)['basePublicationContext']!
                as Map<String, Object?>),
            'publicationAuthorityRef': 'not-public',
          },
        },
        {
          ...(pointJson['treatmentOrigin']! as Map<String, Object?>),
          'loci': [
            ...((pointJson['treatmentOrigin']! as Map<String, Object?>)['loci']!
                    as List<Object?>)
                .reversed,
          ],
        },
        {
          ...(pointJson['treatmentOrigin']! as Map<String, Object?>),
          'loci': [
            ...((pointJson['treatmentOrigin']! as Map<String, Object?>)['loci']!
                as List<Object?>),
            ((pointJson['treatmentOrigin']! as Map<String, Object?>)['loci']!
                    as List<Object?>)
                .first,
          ],
        },
      ];
      for (final origin in invalidOrigins) {
        expect(
          () => ExperimentExactCandidateV1.fromJson(
            {
              ..._exactCandidate(
                'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
              ),
              'treatmentOrigin': origin,
            },
            path: 'candidate',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: origin.toString(),
        );
      }
    });

    test('retains full no-treatment and member-holdout candidates', () {
      final partialJson = _resolvedPartialDraftChoices()
        ..['memberHoldouts'] = [
          {
            'candidateSelection': {
              'kind': 'exactRef',
              'resolvedExactRef': _exactCandidate(
                'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
              ),
            },
            'holdoutId': 'holdout.checkout.members',
            'kind': 'experimentDraftMemberHoldoutChoice',
            'label': 'Unexposed members',
          },
        ];
      final partial = ExperimentResolvedPartialDraftChoicesV1.fromJson(
        partialJson,
      );
      expect(partial.memberHoldouts.single.label, 'Unexposed members');
      expect(
        partial
            .memberHoldouts.single.candidateSelection.resolvedExactRef!.label,
        'Checkout candidate',
      );
      expect(
        partial.memberNoTreatment.resolvedExactRef!.label,
        'Checkout candidate',
      );
      expect(partial.toJson(), partialJson);

      final completeJson = _draftChoices()
        ..['memberHoldouts'] = [
          {
            'candidate': _exactCandidate(
              'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
            ),
            'holdoutId': 'holdout.checkout.members',
            'kind': 'experimentDraftMemberHoldoutChoice',
            'label': 'Unexposed members',
          },
        ];
      final complete = ExperimentDraftChoicesV1.fromJson(completeJson);
      expect(complete.memberHoldouts.single.label, 'Unexposed members');
      expect(
        complete.memberHoldouts.single.candidate.label,
        'Checkout candidate',
      );

      final replacement = _incompleteDraftMutationChoices()
        ..['memberHoldouts'] = [
          {
            'candidateSelection': {
              'kind': 'exactRef',
              'exactRef': _exactCandidate(
                'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
              ),
            },
            'holdoutId': 'holdout.checkout.members',
            'kind': 'experimentDraftMemberHoldoutChoice',
            'label': 'Unexposed members',
          },
        ];
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-member-holdout-1',
            idempotencyKey: 'idempotency-member-holdout-1',
            payload: {..._draftBinding(), 'replacement': replacement},
          ),
        ),
        returnsNormally,
      );

      final invalidPartial = _resolvedPartialDraftChoices()
        ..['memberHoldouts'] = [
          {
            'candidateSelection': {
              'kind': 'exactRef',
              'resolvedExactRef': _surfaceReference(
                'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
              ),
            },
            'holdoutId': 'holdout.checkout.members',
            'kind': 'experimentDraftMemberHoldoutChoice',
            'label': 'Unexposed members',
          },
        ];
      expect(
        () => ExperimentResolvedPartialDraftChoicesV1.fromJson(invalidPartial),
        throwsA(isA<CanonicalFormatException>()),
      );

      final partialWithWeight = _resolvedPartialDraftChoices()
        ..['memberHoldouts'] = [
          {
            'candidateSelection': {
              'kind': 'exactRef',
              'resolvedExactRef': _exactCandidate(
                'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
              ),
            },
            'holdoutId': 'holdout.checkout.members',
            'kind': 'experimentDraftMemberHoldoutChoice',
            'label': 'Unexposed members',
            'relativeWeight': 1,
          },
        ];
      expect(
        () => ExperimentResolvedPartialDraftChoicesV1.fromJson(
          partialWithWeight,
        ),
        throwsA(isA<CanonicalFormatException>()),
      );

      final completeWithWeight = _draftChoices()
        ..['memberHoldouts'] = [
          {
            'candidate': _exactCandidate(
              'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
            ),
            'holdoutId': 'holdout.checkout.members',
            'kind': 'experimentDraftMemberHoldoutChoice',
            'label': 'Unexposed members',
            'relativeWeight': 1,
          },
        ];
      expect(
        () => ExperimentDraftChoicesV1.fromJson(completeWithWeight),
        throwsA(isA<CanonicalFormatException>()),
      );

      final mutationWithWeight = _incompleteDraftMutationChoices()
        ..['memberHoldouts'] = [
          {
            'candidateSelection': {
              'kind': 'exactRef',
              'exactRef': _exactCandidate(
                'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
              ),
            },
            'holdoutId': 'holdout.checkout.members',
            'kind': 'experimentDraftMemberHoldoutChoice',
            'label': 'Unexposed members',
            'relativeWeight': 1,
          },
        ];
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-holdout-weight-1',
            idempotencyKey: 'idempotency-holdout-weight-1',
            payload: {..._draftBinding(), 'replacement': mutationWithWeight},
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );

      for (final noTreatment in <Map<String, Object?>>[
        {
          'kind': 'exactRef',
          'resolvedExactRef': _surfaceReference(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
        },
        {
          'kind': 'serverDefault',
          'resolvedExactRef': _surfaceReference(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
          'source': _publicationCandidateDefaultSource(
            _exactCandidate(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
          ),
        },
      ]) {
        expect(
          () => ExperimentResolvedPartialDraftChoicesV1.fromJson(
            _resolvedPartialDraftChoices()..['memberNoTreatment'] = noTreatment,
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: noTreatment.toString(),
        );
      }
    });

    test('closes resolved guardrail inputs and adapter provenance', () {
      final planning = ExperimentNArmPlanningSelectionV1.fromJson(
        _planningSelection(),
      );
      final guardrail = planning.guardrails.single;
      expect(guardrail.guardrailId.value, 'guardrail.checkout-errors');
      expect(guardrail.adverseDirection.wireName, 'higherIsWorse');
      expect(guardrail.expectedReferenceRate.toJson(), _rational(1, 50));
      expect(guardrail.harmMargin.toJson(), _rational(1, 100));
      expect(guardrail.targetPower.toJson(), _rational(4, 5));
      expect(
        planning.registeredAdapterSelection.resolvedExactRef!.adapterId.value,
        'adapter.rate',
      );
      expect(
        planning.registeredAdapterSelection.source,
        isA<ExperimentCanonicalAuthorityDefaultSourceV1>(),
      );

      final mutationPlanning = _planningMutationSelection();
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-guardrail-inputs-1',
            idempotencyKey: 'idempotency-guardrail-inputs-1',
            payload: {
              ..._draftBinding(),
              'replacement': _fixedHorizonMutationChoices(mutationPlanning),
            },
          ),
        ),
        returnsNormally,
      );

      final invalidAdapterSelections = <Map<String, Object?>>[
        const {'kind': 'unselected'},
        {
          'kind': 'exactRef',
          'resolvedExactRef': {
            'adapterId': 'adapter.rate',
            'revisionId': 'adapter.rate.v2',
            'semanticHash': _digest('8'),
          },
        },
        {
          ...(_planningSelection()['registeredAdapterSelection']!
              as Map<String, Object?>),
        }..remove('source'),
        {
          ...(_planningSelection()['registeredAdapterSelection']!
              as Map<String, Object?>),
          'source': _canonicalAuthorityDefaultSource(
            authorityKind: 'metricDefinition',
            authorityId: 'adapter.rate',
            authorityRevisionId: 'adapter.rate.v2',
            digestDigit: '8',
          ),
        },
        {
          ...(_planningSelection()['registeredAdapterSelection']!
              as Map<String, Object?>),
          'source': _canonicalAuthorityDefaultSource(
            authorityKind: 'registeredInferenceAdapter',
            authorityId: 'adapter.other',
            authorityRevisionId: 'adapter.rate.v2',
            digestDigit: '8',
          ),
        },
        {
          ...(_planningSelection()['registeredAdapterSelection']!
              as Map<String, Object?>),
          'source': _canonicalAuthorityDefaultSource(
            authorityKind: 'registeredInferenceAdapter',
            authorityId: 'adapter.rate',
            authorityRevisionId: 'adapter.rate.v3',
            digestDigit: '8',
          ),
        },
        {
          ...(_planningSelection()['registeredAdapterSelection']!
              as Map<String, Object?>),
          'source': _canonicalAuthorityDefaultSource(
            authorityKind: 'registeredInferenceAdapter',
            authorityId: 'adapter.rate',
            authorityRevisionId: 'adapter.rate.v2',
            digestDigit: '9',
          ),
        },
      ];
      for (final adapterSelection in invalidAdapterSelections) {
        expect(
          () => ExperimentNArmPlanningSelectionV1.fromJson({
            ..._planningSelection(),
            'registeredAdapterSelection': adapterSelection,
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: adapterSelection.toString(),
        );
      }

      final choicesWithDirectionMismatch = _draftChoices();
      final analysis = Map<String, Object?>.from(
        choicesWithDirectionMismatch['analysisSelection']! as Map,
      );
      final mismatchedPlanning = Map<String, Object?>.from(
        analysis['planningSelection']! as Map,
      );
      mismatchedPlanning['guardrails'] = [
        for (final value in mismatchedPlanning['guardrails']! as List)
          {
            ...(value as Map<String, Object?>),
            'adverseDirection': 'lowerIsWorse',
          },
      ];
      analysis['planningSelection'] = mismatchedPlanning;
      choicesWithDirectionMismatch['analysisSelection'] = analysis;
      expect(
        () => ExperimentDraftChoicesV1.fromJson(choicesWithDirectionMismatch),
        throwsA(isA<CanonicalFormatException>()),
      );

      final mutationWithDirection = _planningMutationSelection();
      mutationWithDirection['guardrails'] = [
        for (final value in mutationWithDirection['guardrails']! as List)
          {
            ...(value as Map<String, Object?>),
            'adverseDirection': 'higherIsWorse',
          },
      ];
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-derived-direction-1',
            idempotencyKey: 'idempotency-derived-direction-1',
            payload: {
              ..._draftBinding(),
              'replacement': _fixedHorizonMutationChoices(
                mutationWithDirection,
              ),
            },
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('retains complete metric closure and resolved choices', () {
      final choices = ExperimentDraftChoicesV1.fromJson(_draftChoices());
      final primary = choices.metricBindings.first;
      expect(primary.label, 'Completed checkout');
      expect(primary.armProjectionSets, hasLength(2));
      expect(
        primary.armProjectionSets.first.installedProjectionSetChoice.kind,
        'exactRef',
      );
      expect(
        primary.armProjectionSets.first.resolvedMembers,
        primary.armProjectionSets.first.installedProjectionSetChoice
            .resolvedExactRef!.members,
      );
      expect(
        choices.primaryBindingSelection.kind,
        'exactRef',
      );
      expect(
        choices.rootSurfaceSelection.source,
        isA<ExperimentPublicationCandidateDefaultSourceV1>(),
      );

      for (final invalid in <Map<String, Object?>>[
        _draftChoices()
          ..['rootSurfaceSelection'] = {
            'kind': 'serverDefault',
            'resolvedExactRef': _surfaceReference(
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
            ),
          },
        _draftChoices()
          ..['primaryBindingSelection'] = const {
            'kind': 'exactRef',
            'resolvedExactRef': {
              'metricBindingId': 'metric-binding.completed-checkout',
            },
            'source': {'kind': 'not-admitted'},
          },
        _draftChoices()
          ..['primaryBindingSelection'] = const {
            'kind': 'serverDefault',
            'resolvedExactRef': {
              'metricBindingId': 'metric-binding.completed-checkout',
            },
          },
      ]) {
        expect(
          () => ExperimentDraftChoicesV1.fromJson(invalid),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }

      final mutation = _incompleteDraftMutationChoices(
        rootSurfaceSelection: const {'kind': 'serverDefault'},
      );
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-root-default-1',
            idempotencyKey: 'idempotency-root-default-1',
            payload: {..._draftBinding(), 'replacement': mutation},
          ),
        ),
        returnsNormally,
      );
      expect(
        () => ExperimentAuthoringRequestV1.fromJson(
          _request(
            operation: 'replaceDraft',
            correlationId: 'correlation-root-resolved-default-1',
            idempotencyKey: 'idempotency-root-resolved-default-1',
            payload: {
              ..._draftBinding(),
              'replacement': _incompleteDraftMutationChoices(
                rootSurfaceSelection: {
                  'kind': 'serverDefault',
                  'source': _publicationCandidateDefaultSource(
                    _exactCandidate(
                      'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
                    ),
                  ),
                },
              ),
            },
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });
  });

  group('bounded response projections', () {
    test('requires bounded discovery paging input', () {
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'discoverTargetsAndCapabilities',
          correlationId: 'correlation-discover-page-1',
          payload: const {'pageCursor': 'cursor', 'pageSize': 1},
        ),
      );
      expect(request.payload, const {'pageCursor': 'cursor', 'pageSize': 1});

      for (final payload in <Map<String, Object?>>[
        const {},
        const {'pageSize': 0},
        const {'pageSize': 101},
        const {'pageCursor': '', 'pageSize': 1},
        {'pageCursor': 'x' * 4097, 'pageSize': 1},
        const {'pageSize': 1, 'unexpected': true},
      ]) {
        expect(
          () => ExperimentAuthoringRequestV1.fromJson(
            _request(
              operation: 'discoverTargetsAndCapabilities',
              correlationId: 'correlation-discover-page-invalid',
              payload: payload,
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: payload.toString(),
        );
      }
    });

    test('discovery exposes exact Project-free capabilities and actions', () {
      final discovery = ExperimentTargetDiscoveryV1.fromJson(_discovery());

      expect(discovery.target.toJson(), _target());
      expect(discovery.organizationLabel, 'Example organization');
      expect(discovery.appLabel, 'Storefront');
      expect(discovery.environmentLabel, 'Production');
      expect(discovery.nextPageCursor, isNull);
      expect(discovery.surfaceCapabilities, hasLength(1));
      final surface = discovery.surfaceCapabilities.single;
      expect(
        surface.treatmentOrigins,
        [
          isA<ExperimentWholeSurfaceTreatmentOriginV1>(),
          isA<ExperimentPointSubtreeTreatmentOriginV1>(),
        ],
      );
      for (final origin in surface.treatmentOrigins) {
        final candidate = surface.exactCandidateFor(origin);
        expect(candidate.label, surface.label);
        expect(candidate.surfaceReference, surface.surfaceReference);
        expect(candidate.treatmentOrigin, origin);
      }
      expect(discovery.metricCapabilities, hasLength(2));
      expect(
        discovery.metricCapabilities.map((metric) => metric.direction.wireName),
        ['higherIsBetter', 'none'],
      );
      final installedMetric = surface.installedMetricCapabilities.single;
      expect(installedMetric.availability.isAvailable, isTrue);
      final projectionSet = installedMetric.installedProjectionSets.first;
      expect(
        projectionSet.metricBindingReference.metricBindingId.value,
        'metric-binding.completed-checkout',
      );
      expect(
        projectionSet.members.single.projectionReference.toJson(),
        _slotProjectionReference('projection.checkout.control.v1', '1'),
      );

      final replacement = _incompleteDraftMutationChoices(
        projectionSelection: {
          'exactRef': projectionSet.toJson(),
          'kind': 'exactRef',
        },
      );
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'replaceDraft',
          correlationId: 'correlation-discovery-projection-choice',
          idempotencyKey: 'idempotency-discovery-projection-choice',
          payload: {..._draftBinding(), 'replacement': replacement},
        ),
      );
      final storedReplacement = request.payload['replacement']! as Map;
      final storedBinding =
          (storedReplacement['metricBindings']! as List).single as Map;
      final storedSet =
          (storedBinding['armProjectionSets']! as List).single as Map;
      expect(
        (storedSet['installedProjectionSetChoice']! as Map)['exactRef'],
        projectionSet.toJson(),
      );
      expect(
        discovery.metricCapabilities
            .map(
              (metric) => (
                metric.metricDefinitionId.value,
                metric.metricDefinitionRevisionId.value,
                metric.metricDefinitionSemanticDigest.hex,
              ),
            )
            .toList(),
        [
          (
            'metric.completed-checkout',
            'metric.completed-checkout.v2',
            _digest('1'),
          ),
          ('metric.order-value', 'metric.order-value.v1', _digest('2')),
        ],
      );
      expect(
        discovery.actionAvailability.map((entry) => entry.action.wireName),
        ExperimentActionV1.values.map((action) => action.wireName),
      );
      _expectNoSensitiveKeys(discovery.toJson());

      final directionlessMetric =
          ExperimentExactMetricDefinitionReferenceV1.fromJson(
        _metricDefinitionReference(direction: 'none'),
        path: 'metric',
      );
      expect(directionlessMetric.direction, ExperimentMetricDirectionV1.none);
      expect(
        directionlessMetric.metricDefinitionId.value,
        'metric.completed-checkout',
      );
      expect(
        () => ExperimentExactMetricDefinitionReferenceV1.fromJson(
          _metricDefinitionReference(direction: 'unknown'),
          path: 'metric',
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      for (final invalid in <Map<String, Object?>>[
        _metricDefinitionReference()..remove('metricDefinitionId'),
        {..._metricDefinitionReference(), 'unexpectedMetricDefinitionId': true},
      ]) {
        expect(
          () => ExperimentExactMetricDefinitionReferenceV1.fromJson(
            invalid,
            path: 'metric',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
      expect(
        () => ExperimentTargetDiscoveryV1.fromJson({
          ..._discovery(),
          'metricCapabilities': [
            Map<String, Object?>.from(
              (_discovery()['metricCapabilities']! as List).first as Map,
            )..remove('direction'),
          ],
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      for (final invalid in <Map<String, Object?>>[
        Map<String, Object?>.from(
          (_discovery()['metricCapabilities']! as List).first as Map,
        )..remove('metricDefinitionId'),
        {
          ...Map<String, Object?>.from(
            (_discovery()['metricCapabilities']! as List).first as Map,
          ),
          'unexpectedMetricDefinitionId': true,
        },
      ]) {
        expect(
          () => ExperimentTargetDiscoveryV1.fromJson({
            ..._discovery(),
            'metricCapabilities': [invalid],
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
      expect(
        () => ExperimentTargetDiscoveryV1.fromJson({
          ..._discovery(),
          'metricCapabilities': [
            {
              ...Map<String, Object?>.from(
                (_discovery()['metricCapabilities']! as List).first as Map,
              ),
              'projectionCapabilities': <Object?>[],
            },
          ],
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      final surfaceJson = Map<String, Object?>.from(
        (_discovery()['surfaceCapabilities']! as List).single as Map,
      );
      final installedMetrics = List<Map<String, Object?>>.from(
        surfaceJson['installedMetricCapabilities']! as List,
      );
      final installedMetricJson = Map<String, Object?>.from(
        installedMetrics.first,
      );
      final groups = List<Map<String, Object?>>.from(
        installedMetricJson['installedProjectionSets']! as List,
      );
      final group = Map<String, Object?>.from(groups.first)
        ..['projectionChoices'] = <Object?>[];
      groups[0] = group;
      installedMetricJson['installedProjectionSets'] = groups;
      installedMetrics[0] = installedMetricJson;
      surfaceJson['installedMetricCapabilities'] = installedMetrics;
      expect(
        () => ExperimentTargetDiscoveryV1.fromJson({
          ..._discovery(),
          'surfaceCapabilities': [surfaceJson],
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('closes installed metric availability and complete projection groups',
        () {
      final groupA = _installedProjectionSetCapability(
        metricBindingId: 'metric-binding.completed-checkout',
        projectionSetId: 'projection-set.checkout.a',
        projectionRevisionId: 'projection.checkout.a.v1',
        slotId: 'slot.checkout.a',
        digestDigit: '1',
      );
      final groupB = _installedProjectionSetCapability(
        metricBindingId: 'metric-binding.completed-checkout',
        projectionSetId: 'projection-set.checkout.b',
        projectionRevisionId: 'projection.checkout.b.v1',
        slotId: 'slot.checkout.b',
        digestDigit: '2',
      );
      final available = _installedMetricCapability(
        metricDefinitionId: 'metric.completed-checkout',
        metricDefinitionRevisionId: 'metric.completed-checkout.v2',
        metricDefinitionSemanticDigestDigit: '1',
        installedProjectionSets: [groupA, groupB],
      );
      final unavailable = _installedMetricCapability(
        metricDefinitionId: 'metric.completed-checkout',
        metricDefinitionRevisionId: 'metric.completed-checkout.v2',
        metricDefinitionSemanticDigestDigit: '1',
        installedProjectionSets: const [],
      );

      for (final invalid in <Map<String, Object?>>[
        {
          ...available,
          'installedProjectionSets': [groupA, groupA],
        },
        {
          ...available,
          'installedProjectionSets': [groupB, groupA],
        },
        {
          ...available,
          'availability': const {
            'kind': 'unavailable',
            'reasonCode': 'metric.installedProjectionUnavailable',
          },
        },
        {
          ...unavailable,
          'availability': const {'kind': 'available'},
        },
        {
          ...unavailable,
          'availability': const {
            'kind': 'unavailable',
            'reasonCode': 'metric.presentationUnavailable',
          },
        },
        {...available, 'unexpected': true},
      ]) {
        expect(
          () => ExperimentInstalledMetricCapabilityV1.fromJson(
            invalid,
            path: 'installedMetric',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }

      final memberA = _installedProjectionSetMember(
        projectionRevisionId: 'projection.checkout.members.a.v1',
        slotId: 'slot.checkout.members.a',
        digestDigit: '3',
      );
      final memberB = _installedProjectionSetMember(
        projectionRevisionId: 'projection.checkout.members.b.v1',
        slotId: 'slot.checkout.members.b',
        digestDigit: '4',
      );
      final completeGroup = _installedProjectionSetCapability(
        metricBindingId: 'metric-binding.completed-checkout',
        projectionSetId: 'projection-set.checkout.members',
        projectionRevisionId: 'projection.checkout.members.a.v1',
        slotId: 'slot.checkout.members.a',
        digestDigit: '3',
        members: [memberA, memberB],
      );
      for (final invalid in <Map<String, Object?>>[
        {
          ...completeGroup,
          'members': [memberB, memberA],
        },
        {
          ...completeGroup,
          'members': [memberA, memberA],
        },
        Map<String, Object?>.from(completeGroup)..remove('members'),
        {...completeGroup, 'projectionChoices': const <Object?>[]},
      ]) {
        expect(
          () => ExperimentInstalledProjectionSetCapabilityV1.fromJson(
            invalid,
            path: 'installedProjectionSet',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }

      final rate = Map<String, Object?>.from(
        (_discovery()['metricCapabilities']! as List).first as Map,
      );
      final unsupported = Map<String, Object?>.from(
        (_discovery()['metricCapabilities']! as List).last as Map,
      );
      for (final invalid in <Map<String, Object?>>[
        {...rate, 'analysisChoices': const <Object?>[]},
        {
          ...rate,
          'availability': const {
            'kind': 'unavailable',
            'reasonCode': 'metric.presentationUnavailable',
          },
        },
        {
          ...unsupported,
          'analysisChoices': const ['measureOnly'],
        },
        {
          ...unsupported,
          'availability': const {'kind': 'available'},
        },
      ]) {
        expect(
          () => ExperimentMetricCapabilityV1.fromJson(
            invalid,
            path: 'metric',
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test(
      'requires ordered exact treatment origins for each surface capability',
      () {
        final capability = _surfaceCapability(
          _mintedSurfaceRevisionId('surface.capability.v1'),
        );
        final decoded = ExperimentSurfaceCapabilityV1.fromJson(
          capability,
          path: 'surfaceCapability',
        );
        final unavailable = ExperimentTreatmentOriginV1.fromJson(
          const {
            'kind': 'wholeSurface',
            'locusIds': ['locus.unavailable'],
          },
          path: 'unavailableOrigin',
        );
        expect(
          () => decoded.exactCandidateFor(unavailable),
          throwsA(isA<ArgumentError>()),
        );

        final origins = capability['treatmentOrigins']! as List<Object?>;
        for (final invalid in <Object?>[
          const ['wholeSurface'],
          const [],
          [origins[1], origins[0]],
          [origins[0], origins[0]],
          [origins[1]],
        ]) {
          expect(
            () => ExperimentSurfaceCapabilityV1.fromJson(
              {...capability, 'treatmentOrigins': invalid},
              path: 'surfaceCapability',
            ),
            throwsA(isA<CanonicalFormatException>()),
            reason: invalid.toString(),
          );
        }
      },
    );

    test('one 1024-locus surface capability fits a discovery result', () {
      final capability = _maximumSurfaceCapability(pointCount: 1024);
      final result = {
        'correlationId': 'c' * 4096,
        'kind': 'accepted',
        'operation': 'discoverTargetsAndCapabilities',
        'response': {
          ..._discovery(),
          'metricCapabilities': const <Object?>[],
          'nextPageCursor': 'n' * 4096,
          'surfaceCapabilities': [capability],
        },
        'schemaVersion': 1,
      };
      final bytes = CanonicalJsonCodec.encode(result);
      expect(
        bytes.length,
        lessThanOrEqualTo(experimentAuthoringMaximumResultBytes),
      );
      expect(
        ExperimentAuthoringResultV1.fromCanonicalBytes(bytes),
        isA<ExperimentAuthoringAcceptedV1>(),
      );
      expect(
        () => ExperimentSurfaceCapabilityV1.fromJson(
          _maximumSurfaceCapability(pointCount: 1025),
          path: 'surfaceCapability',
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test(
      'one surface retains 1024 complete installed projection sets within the result bound',
      () {
        final capability = _maximumSurfaceCapability(pointCount: 1024);
        final projectionSets = List<Map<String, Object?>>.generate(
          1024,
          (index) {
            final suffix = index.toString().padLeft(4, '0');
            return _installedProjectionSetCapability(
              metricBindingId: 'metric-binding.completed-checkout',
              projectionSetId: 'projection-set.checkout.$suffix',
              projectionRevisionId: 'projection.checkout.$suffix.a.v1',
              slotId: 'slot.checkout.$suffix.a',
              digestDigit: '1',
              members: [
                _installedProjectionSetMember(
                  projectionRevisionId: 'projection.checkout.$suffix.a.v1',
                  slotId: 'slot.checkout.$suffix.a',
                  digestDigit: '1',
                ),
                _installedProjectionSetMember(
                  projectionRevisionId: 'projection.checkout.$suffix.b.v1',
                  slotId: 'slot.checkout.$suffix.b',
                  digestDigit: '2',
                ),
              ],
            );
          },
        );
        capability['installedMetricCapabilities'] = [
          _installedMetricCapability(
            metricDefinitionId: 'metric.completed-checkout',
            metricDefinitionRevisionId: 'metric.completed-checkout.v2',
            metricDefinitionSemanticDigestDigit: '1',
            installedProjectionSets: projectionSets,
          ),
        ];
        final response = {
          ..._discovery(),
          'metricCapabilities': const <Object?>[],
          'surfaceCapabilities': [capability],
        };
        final bytes = CanonicalJsonCodec.encode({
          'correlationId': 'c' * 4096,
          'kind': 'accepted',
          'operation': 'discoverTargetsAndCapabilities',
          'response': response,
          'schemaVersion': 1,
        });

        expect(
          bytes.length,
          lessThanOrEqualTo(experimentAuthoringMaximumResultBytes),
        );
        final decoded = ExperimentTargetDiscoveryV1.fromJson(response);
        final installedMetric = decoded
            .surfaceCapabilities.single.installedMetricCapabilities.single;
        expect(installedMetric.installedProjectionSets, hasLength(1024));
        expect(
          installedMetric.installedProjectionSets
              .every((entry) => entry.members.length == 2),
          isTrue,
        );
        expect(
          ExperimentAuthoringResultV1.fromCanonicalBytes(bytes),
          isA<ExperimentAuthoringAcceptedV1>(),
        );

        expect(
          () => ExperimentSurfaceCapabilityV1.fromJson(
            {
              ...capability,
              'installedMetricCapabilities': [
                _installedMetricCapability(
                  metricDefinitionId: 'metric.completed-checkout',
                  metricDefinitionRevisionId: 'metric.completed-checkout.v2',
                  metricDefinitionSemanticDigestDigit: '1',
                  installedProjectionSets: [
                    ...projectionSets,
                    _installedProjectionSetCapability(
                      metricBindingId: 'metric-binding.completed-checkout',
                      projectionSetId: 'projection-set.checkout.1024',
                      projectionRevisionId: 'projection.checkout.1024.a.v1',
                      slotId: 'slot.checkout.1024.a',
                      digestDigit: '3',
                    ),
                  ],
                ),
              ],
            },
            path: 'surfaceCapability',
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      },
    );

    test('requires a nullable bounded discovery continuation cursor', () {
      final continued = ExperimentTargetDiscoveryV1.fromJson({
        ..._discovery(),
        'nextPageCursor': 'cursor-4',
      });
      expect(continued.nextPageCursor, 'cursor-4');

      for (final response in <Map<String, Object?>>[
        Map<String, Object?>.from(_discovery())..remove('nextPageCursor'),
        {..._discovery(), 'nextPageCursor': ''},
        {..._discovery(), 'nextPageCursor': 'x' * 4097},
      ]) {
        expect(
          () => ExperimentTargetDiscoveryV1.fromJson(response),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('caps the combined discovery page at 100 entries', () {
      final exactPage = ExperimentTargetDiscoveryV1.fromJson({
        ..._discovery(),
        'metricCapabilities': List<Object?>.generate(
          98,
          (index) => {
            ...Map<String, Object?>.from(
              (_discovery()['metricCapabilities']! as List).first as Map,
            ),
            'metricDefinitionRevisionId': 'metric.page.$index.v1',
          },
        ),
      });
      expect(
        exactPage.namedEnvironments.length +
            exactPage.surfaceCapabilities.length +
            exactPage.metricCapabilities.length,
        100,
      );

      expect(
        () => ExperimentTargetDiscoveryV1.fromJson({
          ..._discovery(),
          'metricCapabilities': List<Object?>.generate(
            101,
            (_) => Map<String, Object?>.from(
              (_discovery()['metricCapabilities']! as List).first as Map,
            ),
          ),
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('admits authoring results larger than one MiB', () {
      final response = {
        'correlationId': 'correlation-results-large',
        'kind': 'accepted',
        'operation': 'readExperimentResults',
        'response': {
          ..._results(),
          'structuredCopyKeys': List<String>.generate(
            256,
            (index) {
              final prefix = 'key.${index.toString().padLeft(3, '0')}.';
              return '$prefix${'x' * (4096 - prefix.length)}';
            },
          ),
        },
        'schemaVersion': 1,
      };
      final bytes = CanonicalJsonCodec.encode(response);
      expect(bytes.length, greaterThan(1024 * 1024));
      expect(
        ExperimentAuthoringResultV1.fromCanonicalBytes(bytes),
        isA<ExperimentAuthoringAcceptedV1>(),
      );
    });

    test('admits a full replace draft larger than 512 KiB', () {
      final replacement = _incompleteDraftMutationChoices();
      final arms = (replacement['arms']! as List<Object?>)
          .map((value) => Map<String, Object?>.from(value! as Map))
          .toList();
      for (final arm in arms) {
        arm['candidateSelection'] = {
          'exactRef': _largePointSubtreeCandidate(),
          'kind': 'exactRef',
        };
      }
      replacement['arms'] = arms;
      final bytes = CanonicalJsonCodec.encode(
        _request(
          operation: 'replaceDraft',
          correlationId: 'correlation-large-replace-draft',
          idempotencyKey: 'idempotency-large-replace-draft',
          payload: {..._draftBinding(), 'replacement': replacement},
        ),
      );

      expect(bytes.length, greaterThan(512 * 1024));
      expect(
        bytes.length,
        lessThanOrEqualTo(experimentAuthoringMaximumRequestBytes),
      );
      expect(
        ExperimentAuthoringRequestV1.fromCanonicalBytes(bytes).operation,
        ExperimentAuthoringOperationV1.replaceDraft,
      );
    });

    test('draft view carries exact identity, CAS, choices, and completeness',
        () {
      final draft = ExperimentDraftViewV1.fromJson(_draftView());

      expect(draft.target.toJson(), _target());
      expect(draft.experimentId.value, 'experiment.checkout');
      expect(draft.draftId.value, 'experiment-draft-checkout');
      expect(draft.draftRevisionId.value, 'experiment-draft-checkout.v3');
      expect(draft.expectedCas, 'draft-cas-3');
      expect(draft.revisionOrdinal, 3);
      expect(draft.semanticDigest.hex, _digest('b'));
      expect(draft.choices.arms, hasLength(2));
      expect(draft.completeness.kind.wireName, 'complete');
      expect(draft.conflicts, isEmpty);
      _expectNoSensitiveKeys(draft.toJson());
    });

    test('validation reports typed issues and a safe planning preview', () {
      final validation = ExperimentValidationViewV1.fromJson(_validation());

      expect(validation.draftBinding.toJson(), _draftBinding());
      expect(validation.issues.single.code.wireName, 'guardrailUnavailable');
      expect(
        validation.capabilityReasons.single.code.wireName,
        'metricReadUnavailable',
      );
      expect(validation.planningPreview, isNotNull);
      expect(validation.planningPreview!.feasibility.wireName, 'feasible');
      expect(validation.planningPreview!.plannedTotalEnrollment, 10000);
      expect(validation.planningPreview!.plannedPerArmEnrollment, {
        'arm.control': 5000,
        'arm.variant': 5000,
      });
      _expectNoSensitiveKeys(validation.toJson());
    });

    test('capability reason codes retain their exact wire spellings', () {
      const codes = [
        'surfaceUnavailable',
        'metricReadUnavailable',
        'metricPresentationUnavailable',
        'statisticalAnalysisUnavailable',
        'statisticalCountNumeratorUnsupported',
      ];

      expect(
        ExperimentCapabilityReasonCodeV1.values.map((code) => code.wireName),
        codes,
      );
      for (final code in codes) {
        final json = <String, Object?>{
          'code': code,
          'kind': 'experimentCapabilityReason',
          'referenceId': 'metric.checkout.v1',
        };
        final reason = ExperimentCapabilityReasonV1.fromJson(
          json,
          path: 'capabilityReason',
        );

        expect(reason.code.wireName, code);
        expect(reason.toJson(), json);
      }
      expect(
        () => ExperimentCapabilityReasonV1.fromJson(
          const {
            'code': 'unsupported',
            'kind': 'experimentCapabilityReason',
            'referenceId': 'metric.checkout.v1',
          },
          path: 'capabilityReason',
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('planning preview freezes only the safe certified projection', () {
      final preview = ExperimentNArmPlanningPreviewV1.fromJson(
        _planningPreview(),
      );

      expect(preview.reviewedSelection.toJson(), _planningSelection());
      expect(preview.planningIntentDigest.hex, _digest('2'));
      expect(preview.allocationAuthorityDigest.hex, _digest('3'));
      expect(preview.certifiedScales, {
        'allocationScale': '1000000',
        'effectScale': '1000000000',
      });
      expect(preview.plannerIdentityDigest!.hex, _digest('4'));
      expect(preview.resultDigest!.hex, _digest('5'));
      expect(preview.plannedFollowUpDurationMicros, 86400000000);
      _expectNoSensitiveKeys(preview.toJson());
    });

    test('feasible planning previews close enrollment keys over allocation',
        () {
      final preview = _planningPreview()
        ..['plannedPerArmEnrollment'] = const {
          'arm.control': 5000,
          'arm.other': 5000,
        };

      expect(
        () => ExperimentNArmPlanningPreviewV1.fromJson(preview),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('planning failure previews preserve only common evidence', () {
      for (final feasibility in ['infeasible', 'indeterminate']) {
        final json = _planningFailurePreview(feasibility);
        final preview = ExperimentNArmPlanningPreviewV1.fromJson(json);

        expect(preview.feasibility.wireName, feasibility);
        expect(preview.reviewedSelection.toJson(), _planningSelection());
        expect(preview.planningIntentDigest.hex, _digest('2'));
        expect(preview.allocationAuthorityDigest.hex, _digest('3'));
        expect(preview.plannedPerArmEnrollment, isNull);
        expect(preview.plannedTotalEnrollment, isNull);
        expect(preview.certifiedScales, isNull);
        expect(preview.plannedFollowUpDurationMicros, isNull);
        expect(preview.plannedMaximumEnrollmentDurationMicros, isNull);
        expect(preview.plannerIdentityDigest, isNull);
        expect(preview.resultDigest, isNull);
        expect(preview.toJson(), json);

        final decoded = ExperimentNArmPlanningPreviewV1.fromJson(
          decodeCanonicalObject(preview.canonicalBytes),
        );
        expect(decoded.toJson(), json);
        expect(
          decoded.canonicalBytes,
          orderedEquals(preview.canonicalBytes),
        );
      }
    });

    test('planning failure previews reject certified result values', () {
      final feasible = _planningPreview();
      for (final feasibility in ['infeasible', 'indeterminate']) {
        for (final key in [
          'certifiedScales',
          'plannedFollowUpDurationMicros',
          'plannedMaximumEnrollmentDurationMicros',
          'plannedPerArmEnrollment',
          'plannedTotalEnrollment',
          'plannerIdentityDigest',
          'resultDigest',
        ]) {
          expect(
            () => ExperimentNArmPlanningPreviewV1.fromJson({
              ..._planningFailurePreview(feasibility),
              key: feasible[key],
            }),
            throwsA(isA<CanonicalFormatException>()),
            reason: '$feasibility.$key',
          );
        }
      }
    });

    test('planning previews require their common evidence', () {
      for (final json in [
        _planningPreview(),
        _planningFailurePreview('infeasible'),
        _planningFailurePreview('indeterminate'),
      ]) {
        for (final key in [
          'allocationAuthorityDigest',
          'feasibility',
          'planningIntentDigest',
          'reviewedSelection',
        ]) {
          expect(
            () => ExperimentNArmPlanningPreviewV1.fromJson(
              Map<String, Object?>.from(json)..remove(key),
            ),
            throwsA(isA<CanonicalFormatException>()),
            reason: '${json['feasibility']}.$key',
          );
        }
      }
    });

    test('feasible planning previews require valid certified result values',
        () {
      for (final key in [
        'certifiedScales',
        'plannedFollowUpDurationMicros',
        'plannedMaximumEnrollmentDurationMicros',
        'plannedPerArmEnrollment',
        'plannedTotalEnrollment',
        'plannerIdentityDigest',
        'resultDigest',
      ]) {
        expect(
          () => ExperimentNArmPlanningPreviewV1.fromJson(
            Map<String, Object?>.from(_planningPreview())..remove(key),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: key,
        );
      }

      for (final invalid in <(String, Object?)>[
        (
          'certifiedScales',
          const {'allocationScale': '0', 'effectScale': '1000000000'},
        ),
        ('plannedFollowUpDurationMicros', -1),
        ('plannedMaximumEnrollmentDurationMicros', 0),
        ('plannedPerArmEnrollment', const <String, Object?>{}),
        ('plannedTotalEnrollment', 0),
        ('plannerIdentityDigest', 'invalid'),
        ('resultDigest', 'invalid'),
      ]) {
        expect(
          () => ExperimentNArmPlanningPreviewV1.fromJson({
            ..._planningPreview(),
            invalid.$1: invalid.$2,
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.$1,
        );
      }
    });

    test('review reference is a bounded locator rather than authority', () {
      final reference = ExperimentReviewReferenceV1.fromJson(
        _reviewReference(),
      );
      const expected = '{"kind":"experimentReviewReference",'
          '"recordDigest":"6666666666666666666666666666666666666666666666666666666666666666",'
          '"reviewId":"experiment-review-checkout-3",'
          '"schemaVersion":1}';

      expect(reference.reviewId.value, 'experiment-review-checkout-3');
      expect(reference.recordDigest.hex, _digest('6'));
      expect(reference.canonicalBytes, orderedEquals(utf8.encode(expected)));
      expect(
        ExperimentReviewReferenceV1.fromCanonicalBytes(utf8.encode(expected))
            .canonicalBytes,
        orderedEquals(utf8.encode(expected)),
      );
      _expectNoSensitiveKeys(reference.toJson());
    });

    test('review exposes the exact configuration and consequences', () {
      final review = ExperimentReviewViewV1.fromJson(_review());

      expect(review.draftBinding.toJson(), _draftBinding());
      expect(review.configuration.toJson(), _draftChoices());
      expect(review.planningPreview, isNotNull);
      expect(review.reviewReference.toJson(), _reviewReference());
      expect(review.recordDigest.hex, _digest('6'));
      expect(review.projectionDigest.hex, _digest('7'));
      expect(review.issuedAtMicros, 1788091200000000);
      _expectNoSensitiveKeys(review.toJson());
    });

    test('accepted activation exposes strict Live read correlation', () {
      final activation = ExperimentActivationAcceptedViewV1.fromJson(
        _activation(),
      );

      expect(activation.target.toJson(), _target());
      expect(activation.experimentId.value, 'experiment.checkout');
      expect(activation.activationOrdinal, 7);
      expect(activation.receiptDigest.hex, _digest('c'));
      expect(activation.liveReadReference.target.toJson(), _target());
      expect(
        activation.liveReadReference.experimentId,
        activation.experimentId,
      );
      expect(
        activation.liveReadReference.activationOrdinal,
        activation.activationOrdinal,
      );
      expect(
        activation.liveReadReference.receiptDigest,
        activation.receiptDigest,
      );
      _expectNoSensitiveKeys(activation.toJson());
    });

    test('lifecycle accepted views require the matching epoch shape', () {
      expect(
        ExperimentLifecycleStateV1.values.map((state) => state.wireName),
        ['active', 'paused', 'concluded'],
      );
      final views = <String, Map<String, Object?>>{
        'paused': _lifecycleAccepted(
          lifecycleState: 'paused',
          lifecycleOrdinal: 9,
        ),
        'active': _lifecycleAccepted(
          lifecycleState: 'active',
          lifecycleOrdinal: 10,
        ),
        'concluded': _lifecycleAccepted(
          lifecycleState: 'concluded',
          lifecycleOrdinal: 11,
        ),
      };

      for (final entry in views.entries) {
        final view = ExperimentLifecycleAcceptedViewV1.fromJson(entry.value);
        expect(view.lifecycleState.wireName, entry.key);
        expect(view.target.toJson(), _target());
        expect(view.experimentId.value, 'experiment.checkout');
        expect(view.transitionedAtMicros, 1788091300000000);
        expect(view.toJson(), entry.value);
        if (entry.key == 'active') {
          expect(view.experimentEpochId?.value, 'experiment.checkout.epoch.8');
        } else {
          expect(view.experimentEpochId, isNull);
        }
        _expectNoSensitiveKeys(view.toJson());
      }

      final active = views['active']!;
      final paused = views['paused']!;
      final concluded = views['concluded']!;
      for (final invalid in <Map<String, Object?>>[
        for (final key in active.keys)
          Map<String, Object?>.from(active)..remove(key),
        Map<String, Object?>.from(active)..remove('experimentEpochId'),
        {...paused, 'experimentEpochId': 'experiment.checkout.epoch.8'},
        {...concluded, 'experimentEpochId': 'experiment.checkout.epoch.8'},
        {...active, 'experimentId': 7},
        {...active, 'target': 'target'},
        {...active, 'receiptDigest': 7},
        {...active, 'lifecycleOrdinal': 0},
        {...active, 'lifecycleOrdinal': '10'},
        {...active, 'lifecycleOrdinal': 9007199254740992},
        {...active, 'transitionedAtMicros': 0},
        {...active, 'transitionedAtMicros': '1788091300000000'},
        {...active, 'transitionedAtMicros': 9007199254740992},
        {...active, 'lifecycleState': 'unknown'},
        {...active, 'unexpected': true},
      ]) {
        expect(
          () => ExperimentLifecycleAcceptedViewV1.fromJson(invalid),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('lists draft and activated entries under one target', () {
      final emptyJson = {
        ..._listView(),
        'experiments': <Object?>[],
        'nextPageCursor': null,
      };
      final empty = ExperimentListViewV1.fromJson(emptyJson);
      expect(empty.experiments, isEmpty);
      expect(empty.nextPageCursor, isNull);

      final draftStates = [
        _draftSummary(
          experimentId: 'experiment.draft-incomplete',
          draftId: 'experiment-draft-incomplete',
          draftRevisionId: 'experiment-draft-incomplete.v1',
          controlPlaneOrdinal: 1,
          complete: false,
        ),
        _draftSummary(
          experimentId: 'experiment.draft-incomplete-archived',
          draftId: 'experiment-draft-incomplete-archived',
          draftRevisionId: 'experiment-draft-incomplete-archived.v2',
          controlPlaneOrdinal: 2,
          complete: false,
          archived: true,
        ),
        _draftSummary(
          experimentId: 'experiment.draft-complete',
          draftId: 'experiment-draft-complete',
          draftRevisionId: 'experiment-draft-complete.v4',
          controlPlaneOrdinal: 4,
        ),
        _draftSummary(
          experimentId: 'experiment.draft-complete-archived',
          draftId: 'experiment-draft-complete-archived',
          draftRevisionId: 'experiment-draft-complete-archived.v5',
          controlPlaneOrdinal: 5,
          archived: true,
        ),
      ];
      final mixedJson = {
        ..._listView(),
        'experiments': [...draftStates, _summary()],
      };
      final mixed = ExperimentListViewV1.fromJson(mixedJson);

      expect(mixed.experiments, hasLength(5));
      expect(
        mixed.experiments.take(4),
        everyElement(isA<ExperimentDraftSummaryV1>()),
      );
      expect(mixed.experiments.last, isA<ExperimentSummaryV1>());
      expect(mixed.toJson(), mixedJson);
      final decoded = ExperimentListViewV1.fromJson(
        decodeCanonicalObject(mixed.canonicalBytes),
      );
      expect(decoded.canonicalBytes, orderedEquals(mixed.canonicalBytes));
      _expectNoSensitiveKeys(mixed.toJson());
    });

    test('draft summaries close identity, time, and availability', () {
      final valid = _draftSummary();
      for (final key in valid.keys) {
        expect(
          () => ExperimentListViewV1.fromJson({
            ..._listView(),
            'experiments': [Map<String, Object?>.from(valid)..remove(key)],
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: key,
        );
      }

      for (final invalid in <Map<String, Object?>>[
        {...valid, 'controlPlaneOrdinal': 0},
        {...valid, 'createdAtMicros': 0},
        {...valid, 'archivedAtMicros': 1788091199999999},
        {...valid, 'label': ''},
        {
          ...valid,
          'liveState': const {
            'kind': 'unavailable',
            'reasonCode': 'activated',
          },
        },
        {
          ...valid,
          'liveState': const {
            'kind': 'available',
            'reasonCode': 'notActivated',
          },
        },
        {
          ...valid,
          'liveState': const {
            'kind': 'unavailable',
            'reasonCode': 'notActivated',
            'unexpected': true,
          },
        },
        for (final key in [
          'activationOrdinal',
          'inferenceReference',
          'liveReadReference',
          'receiptDigest',
        ])
          {...valid, key: key == 'activationOrdinal' ? 1 : 'not-admitted'},
      ]) {
        expect(
          () => ExperimentListViewV1.fromJson({
            ..._listView(),
            'experiments': [invalid],
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }

      final otherTarget = _draftSummary(target: _otherTarget());
      expect(
        () => ExperimentListViewV1.fromJson({
          ..._listView(),
          'experiments': [otherTarget],
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentListViewV1.fromJson({
          ..._listView(),
          'experiments': [
            _draftSummary(),
            _summary(),
          ],
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentListViewV1.fromJson({
          ..._listView(),
          'experiments': [
            {...valid, 'kind': 'experimentUnknownSummary'},
          ],
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('draft details correlate their summary and revision', () {
      final json = _draftDetail();
      final view = ExperimentReadViewV1.fromJson(json);

      expect(view, isA<ExperimentDraftDetailV1>());
      final draftDetail = view as ExperimentDraftDetailV1;
      expect(draftDetail.summary.controlPlaneOrdinal, 12);
      expect(draftDetail.draft.revisionOrdinal, 3);
      expect(
        draftDetail.summary.controlPlaneOrdinal,
        isNot(draftDetail.draft.revisionOrdinal),
      );
      expect(view.toJson(), json);
      final decoded = ExperimentReadViewV1.fromJson(
        decodeCanonicalObject(view.canonicalBytes),
      );
      expect(decoded.canonicalBytes, orderedEquals(view.canonicalBytes));

      final validSummary = _draftSummary();
      for (final summary in <Map<String, Object?>>[
        {...validSummary, 'target': _otherTarget()},
        {...validSummary, 'experimentId': 'experiment.other'},
        {...validSummary, 'draftId': 'experiment-draft-other'},
        {...validSummary, 'draftRevisionId': 'experiment-draft-checkout.v4'},
        {...validSummary, 'label': 'Other label'},
        {
          ...validSummary,
          'completeness': const {
            'kind': 'incomplete',
            'missingFieldPaths': ['analysisSelection'],
          },
        },
      ]) {
        expect(
          () => ExperimentReadViewV1.fromJson(
            _draftDetail(summary: summary),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: summary.toString(),
        );
      }

      for (final key in json.keys) {
        expect(
          () => ExperimentReadViewV1.fromJson(
            Map<String, Object?>.from(json)..remove(key),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: key,
        );
      }
      expect(
        () => ExperimentReadViewV1.fromJson({...json, 'unexpected': true}),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('activated details retain their exact canonical representation', () {
      final json = _detail();
      final direct = ExperimentDetailV1.fromJson(json);
      final dispatched = ExperimentReadViewV1.fromJson(json);

      expect(dispatched, isA<ExperimentDetailV1>());
      expect(direct.toJson(), json);
      expect(
        dispatched.canonicalBytes,
        orderedEquals(CanonicalJsonCodec.encode(json)),
      );
      expect(direct.canonicalBytes, orderedEquals(dispatched.canonicalBytes));

      expect(
        () => ExperimentReadViewV1.fromJson({
          ...json,
          'kind': 'experimentUnknownDetail',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('list, detail, results, and archive retain separate lifecycle state',
        () {
      for (final lifecycleState in ['active', 'paused', 'concluded']) {
        final summaryJson = _summary(lifecycleState: lifecycleState);
        final list = ExperimentListViewV1.fromJson({
          ..._listView(),
          'experiments': [summaryJson],
        });
        final summary = ExperimentSummaryV1.fromJson(summaryJson);
        final detail = ExperimentDetailV1.fromJson(
          _detail(lifecycleState: lifecycleState),
        );
        final results = ExperimentResultsViewV1.fromJson(
          _results(lifecycleState: lifecycleState),
        );

        expect(list.experiments.single.toJson(), summary.toJson());
        expect(list.nextPageCursor, 'cursor-4');
        expect(summary.lifecycleState.wireName, lifecycleState);
        expect(results.lifecycleState.wireName, lifecycleState);
        expect(summary.integrityState.wireName, 'verified');
        expect(summary.controlPlaneOrdinal, 10);
        expect(summary.controlPlaneOrdinal, isNot(summary.lifecycleOrdinal));
        expect(summary.archivedAtMicros, isNull);
        expect(summary.pendingDraft.kind.wireName, 'none');
        expect(summary.inferenceReference.kind.wireName, 'unavailable');
        expect(detail.summary.toJson(), summary.toJson());
        expect(detail.arms, hasLength(2));
        for (final value in [
          list.toJson(),
          summary.toJson(),
          detail.toJson(),
          results.toJson(),
        ]) {
          _expectNoSensitiveKeys(value);
        }
      }

      final archived = ExperimentSummaryV1.fromJson(
        _summary(archived: true),
      );
      expect(archived.lifecycleState.wireName, 'active');
      expect(archived.lifecycleOrdinal, 8);
      expect(archived.controlPlaneOrdinal, 11);
      expect(archived.archivedAtMicros, 1788091300000000);

      expect(
        () => ExperimentSummaryV1.fromJson({
          ..._summary(),
          'integrityState': 'unavailable',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );

      for (final unsupported in ['live', 'archived', 'integrityUnavailable']) {
        expect(
          () => ExperimentSummaryV1.fromJson(
            _summary(lifecycleState: unsupported),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: unsupported,
        );
        expect(
          () => ExperimentResultsViewV1.fromJson(
            _results(lifecycleState: unsupported),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: unsupported,
        );
      }
    });

    test('keeps lifecycle state when accepted presentation is unavailable', () {
      for (final lifecycleState in ['active', 'paused', 'concluded']) {
        final summaryJson = _integrityUnavailableSummary(
          lifecycleState: lifecycleState,
        );
        final list = ExperimentListViewV1.fromJson({
          ..._listView(),
          'experiments': [summaryJson],
        });
        final summary =
            list.experiments.single as ExperimentIntegrityUnavailableSummaryV1;
        expect(summary.integrityState.wireName, 'unavailable');
        expect(summary.lifecycleState.wireName, lifecycleState);
        expect(summary.experimentId.value, 'experiment.checkout');
        expect(summary.toJson(), summaryJson);
        expect(summaryJson, isNot(containsPair('label', anything)));
        expect(
          ExperimentListEntryV1.fromJson(
            decodeCanonicalObject(summary.canonicalBytes),
          ).canonicalBytes,
          orderedEquals(summary.canonicalBytes),
        );

        final detailJson = {
          'kind': 'experimentIntegrityUnavailableDetail',
          'schemaVersion': 1,
          'summary': summaryJson,
        };
        final detail = ExperimentReadViewV1.fromJson(detailJson);
        expect(detail, isA<ExperimentIntegrityUnavailableDetailV1>());
        expect(detail.toJson(), detailJson);
        expect(
          ExperimentReadViewV1.fromJson(
            decodeCanonicalObject(detail.canonicalBytes),
          ).canonicalBytes,
          orderedEquals(detail.canonicalBytes),
        );
      }

      final archived = ExperimentIntegrityUnavailableSummaryV1.fromJson(
        _integrityUnavailableSummary(archived: true, lifecycleState: 'paused'),
      );
      expect(archived.lifecycleState, ExperimentLifecycleStateV1.paused);
      expect(archived.archivedAtMicros, 1788091300000000);
      expect(archived.controlPlaneOrdinal, 11);

      final summaryJson = _integrityUnavailableSummary();
      final detailJson = {
        'kind': 'experimentIntegrityUnavailableDetail',
        'schemaVersion': 1,
        'summary': summaryJson,
      };

      for (final invalid in <Map<String, Object?>>[
        {...summaryJson, 'integrityState': 'verified'},
        {...summaryJson, 'label': 'Invented presentation'},
        {...summaryJson, 'unexpected': true},
        {...summaryJson, 'lifecycleState': 'finished'},
        Map<String, Object?>.from(summaryJson)..remove('lifecycleState'),
        Map<String, Object?>.from(summaryJson)..remove('acceptedAtMicros'),
      ]) {
        expect(
          () => ExperimentListViewV1.fromJson({
            ..._listView(),
            'experiments': [invalid],
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
      expect(
        () => ExperimentReadViewV1.fromJson({
          ...detailJson,
          'label': 'Invented presentation',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );

      final mixedJson = {
        ..._listView(),
        'experiments': [
          summaryJson,
          _draftSummary(
            experimentId: 'experiment.pending',
            draftId: 'experiment-draft-pending',
            draftRevisionId: 'experiment-draft-pending.v1',
          ),
        ],
      };
      final mixed = ExperimentListViewV1.fromJson(mixedJson);
      expect(
        mixed.experiments.first,
        isA<ExperimentIntegrityUnavailableSummaryV1>(),
      );
      expect(mixed.experiments.last, isA<ExperimentDraftSummaryV1>());
      expect(
        mixed.experiments.last.toJson(),
        isNot(containsPair('lifecycleState', anything)),
      );
      expect(
        () => ExperimentListViewV1.fromJson({
          ...mixedJson,
          'integrityState': 'unavailable',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentListEntryV1.fromJson({
          ..._draftSummary(),
          'lifecycleState': 'active',
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('results expose approved statistics and structured copy only', () {
      final results = ExperimentResultsViewV1.fromJson(_results());

      expect(results.analysis.wireName, 'fixedHorizonNArmRate');
      expect(results.lifecycleState.wireName, 'active');
      expect(results.availability.kind.wireName, 'available');
      expect(results.armResults, hasLength(2));
      expect(results.guardrailOutcomes, hasLength(1));
      expect(results.structuredCopyKeys, [
        'experiment.result.noDecision',
        'experiment.result.guardrailWithinBound',
      ]);
      _expectNoSensitiveKeys(results.toJson());
    });

    test('results keep every non-result state explicit and closed', () {
      const states = [
        'insufficientEvidence',
        'capabilityUnavailable',
        'indeterminate',
        'privacyRestricted',
        'interrupted',
      ];

      for (final state in states) {
        final json = {
          ..._results(),
          'armResults': <Object?>[],
          'availability': {
            'kind': state,
            'reasonCode': 'experiment.results.$state',
          },
          'guardrailOutcomes': <Object?>[],
          'structuredCopyKeys': ['experiment.results.$state'],
        };
        final results = ExperimentResultsViewV1.fromJson(json);
        expect(results.availability.kind.wireName, state);
        expect(results.armResults, isEmpty);
        _expectNoSensitiveKeys(results.toJson());
      }

      expect(
        () => ExperimentResultsViewV1.fromJson({
          ..._results(),
          'availability': const {
            'kind': 'winner',
            'reasonCode': 'unapproved',
          },
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });
  });

  group('accepted and refused results', () {
    test('accepted responses decode by their exact operation', () {
      final responses = <String, Map<String, Object?>>{
        'discoverTargetsAndCapabilities': _discovery(),
        'openDraft': _draftView(),
        'readDraft': _draftView(),
        'resolveDraft': _draftView(),
        'replaceDraft': _draftView(),
        'copyDraftToTarget': _draftView(),
        'validateDraft': _validation(),
        'reviewDraft': _review(),
        'activateDraft': _activation(),
        'pauseExperiment': _lifecycleAccepted(
          lifecycleState: 'paused',
          lifecycleOrdinal: 9,
        ),
        'resumeExperiment': _lifecycleAccepted(
          lifecycleState: 'active',
          lifecycleOrdinal: 10,
        ),
        'concludeExperiment': _lifecycleAccepted(
          lifecycleState: 'concluded',
          lifecycleOrdinal: 11,
        ),
        'listExperiments': _listView(),
        'readExperiment': _detail(),
        'readExperimentResults': _results(),
        'setExperimentArchived': _detail(archived: true),
      };

      for (final entry in responses.entries) {
        final result = ExperimentAuthoringResultV1.fromJson({
          'correlationId': 'correlation-result-1',
          'kind': 'accepted',
          'operation': entry.key,
          'response': entry.value,
          'schemaVersion': 1,
        });
        expect(result, isA<ExperimentAuthoringAcceptedV1>());
        expect(result.operation.wireName, entry.key);
        expect(
          ExperimentAuthoringResultV1.fromCanonicalBytes(
            result.canonicalBytes,
          ).canonicalBytes,
          orderedEquals(result.canonicalBytes),
        );
        _expectNoSensitiveKeys(result.toJson());
      }
    });

    test('keeps activation receipts and experiment results on distinct routes',
        () {
      final mismatches = <String, Map<String, Object?>>{
        'activateDraft': _results(),
        'readExperimentResults': _activation(),
        'pauseExperiment': _lifecycleAccepted(
          lifecycleState: 'active',
          lifecycleOrdinal: 10,
        ),
        'resumeExperiment': _lifecycleAccepted(
          lifecycleState: 'paused',
          lifecycleOrdinal: 9,
        ),
        'concludeExperiment': _lifecycleAccepted(
          lifecycleState: 'paused',
          lifecycleOrdinal: 9,
        ),
      };

      for (final mismatch in mismatches.entries) {
        expect(
          () => ExperimentAuthoringResultV1.fromJson({
            'correlationId': 'correlation-route-${mismatch.key}',
            'kind': 'accepted',
            'operation': mismatch.key,
            'response': mismatch.value,
            'schemaVersion': 1,
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: mismatch.key,
        );
      }
    });

    test('read operations accept either activated or draft details', () {
      for (final operation in ['readExperiment', 'setExperimentArchived']) {
        for (final response in <Map<String, Object?>>[
          _detail(archived: operation == 'setExperimentArchived'),
          _draftDetail(
            summary: _draftSummary(
              archived: operation == 'setExperimentArchived',
            ),
          ),
        ]) {
          final result = ExperimentAuthoringResultV1.fromJson({
            'correlationId': 'correlation-read-branch-1',
            'kind': 'accepted',
            'operation': operation,
            'response': response,
            'schemaVersion': 1,
          });
          final accepted = result as ExperimentAuthoringAcceptedV1;

          expect(accepted.response, isA<ExperimentReadViewV1>());
          expect(accepted.response.toJson(), response);
        }

        expect(
          () => ExperimentAuthoringResultV1.fromJson({
            'correlationId': 'correlation-unknown-read-branch-1',
            'kind': 'accepted',
            'operation': operation,
            'response': const {
              'kind': 'experimentUnknownDetail',
              'schemaVersion': 1,
            },
            'schemaVersion': 1,
          }),
          throwsA(isA<CanonicalFormatException>()),
          reason: operation,
        );
      }
    });

    test('refusal discriminators are complete and preserve correlation', () {
      const codes = [
        'validationBlocked',
        'staleDraft',
        'staleHead',
        'notActive',
        'alreadyPaused',
        'notPaused',
        'alreadyConcluded',
        'concluded',
        'staleLifecycleOrdinal',
        'reviewMissing',
        'reviewStale',
        'reviewBindingMismatch',
        'ownershipConflict',
        'deniedAction',
        'targetMismatch',
        'incompatibleReference',
        'capabilityUnavailable',
        'statisticalCountNumeratorUnsupported',
        'replayRebinding',
        'backendUnavailable',
        'integrityFailure',
        'transportUnknownOutcome',
      ];

      expect(
        ExperimentAuthoringRefusalCodeV1.values.map((code) => code.wireName),
        codes,
      );
      for (final code in codes) {
        final json = <String, Object?>{
          'correlationId': 'correlation-refusal-$code',
          'kind': 'refused',
          'operation': 'activateDraft',
          'refusal': {
            'code': code,
            'kind': 'experimentAuthoringRefusal',
            'messageKey': 'experiment.authoring.$code',
            'retryable': code == 'backendUnavailable' ||
                code == 'transportUnknownOutcome',
            'schemaVersion': 1,
          },
          'schemaVersion': 1,
        };
        final result = ExperimentAuthoringResultV1.fromJson(json);

        expect(result, isA<ExperimentAuthoringRefusedV1>());
        final refused = result as ExperimentAuthoringRefusedV1;
        expect(refused.correlationId, 'correlation-refusal-$code');
        expect(refused.refusal.code.wireName, code);
        expect(refused.toJson(), json);
        expect(
          ExperimentAuthoringResultV1.fromCanonicalBytes(
            result.canonicalBytes,
          ).toJson(),
          json,
        );
      }
    });

    test('freezes an independent canonical refusal literal', () {
      const expected = '{"correlationId":"correlation-refusal-stale",'
          '"kind":"refused","operation":"activateDraft",'
          '"refusal":{"code":"staleDraft",'
          '"kind":"experimentAuthoringRefusal",'
          '"messageKey":"experiment.authoring.staleDraft",'
          '"retryable":false,"schemaVersion":1},"schemaVersion":1}';
      final result = ExperimentAuthoringResultV1.fromCanonicalBytes(
        utf8.encode(expected),
      );

      expect(result, isA<ExperimentAuthoringRefusedV1>());
      expect(result.canonicalBytes, orderedEquals(utf8.encode(expected)));
    });

    test('rejects unknown result and refusal discriminators', () {
      final values = <Map<String, Object?>>[
        {
          'correlationId': 'correlation-unknown-1',
          'kind': 'unknown',
          'operation': 'activateDraft',
          'schemaVersion': 1,
        },
        for (final code in const [
          'unknown',
          'reviewMissingUnknown',
          'reviewStaleUnknown',
          'reviewBindingMismatchUnknown',
          'statisticalCountNumeratorUnsupportedUnknown',
        ])
          {
            'correlationId': 'correlation-unknown-$code',
            'kind': 'refused',
            'operation': 'activateDraft',
            'refusal': {
              'code': code,
              'kind': 'experimentAuthoringRefusal',
              'messageKey': 'experiment.authoring.$code',
              'retryable': false,
              'schemaVersion': 1,
            },
            'schemaVersion': 1,
          },
      ];
      for (final json in values) {
        expect(
          () => ExperimentAuthoringResultV1.fromJson(json),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('closes every accepted response branch and result version', () {
      for (final entry in _acceptedResponses().entries) {
        final valid = {
          'correlationId': 'correlation-closed-${entry.key}',
          'kind': 'accepted',
          'operation': entry.key,
          'response': entry.value,
          'schemaVersion': 1,
        };
        for (final invalid in <Map<String, Object?>>[
          {...valid, 'unexpected': true},
          {...valid, 'schemaVersion': 2},
          {
            ...valid,
            'response': {...entry.value, 'unexpected': true},
          },
          {
            ...valid,
            'response': const {
              'kind': 'unknownResponse',
              'schemaVersion': 1,
            },
          },
        ]) {
          expect(
            () => ExperimentAuthoringResultV1.fromJson(invalid),
            throwsA(isA<CanonicalFormatException>()),
            reason: '${entry.key}: $invalid',
          );
        }
      }
    });

    test('names the target on every accepted response that has one', () {
      // Two operations answer about a draft's content rather than a target.
      const targetFree = {'validateDraft', 'reviewDraft'};
      final responses = _acceptedResponses();
      expect(
        responses.keys.toSet(),
        {for (final o in ExperimentAuthoringOperationV1.values) o.wireName},
        reason: 'every operation needs an accepted response here',
      );
      final expected = TargetCoordinate.fromJson(_target());
      for (final entry in responses.entries) {
        final result = ExperimentAuthoringResultV1.fromJson({
          'correlationId': 'correlation-target-${entry.key}',
          'kind': 'accepted',
          'operation': entry.key,
          'response': entry.value,
          'schemaVersion': 1,
        });
        final response = (result as ExperimentAuthoringAcceptedV1).response;
        if (targetFree.contains(entry.key)) {
          expect(
            entry.value.containsKey('target'),
            isFalse,
            reason: '${entry.key} must expose a target it starts naming',
          );
          expect(
            response,
            isNot(isA<ExperimentTargetBoundViewV1>()),
            reason: '${entry.key} answers about content, not a target',
          );
          continue;
        }
        expect(
          response,
          isA<ExperimentTargetBoundViewV1>(),
          reason: '${entry.key} carries a target and must expose it',
        );
        expect(
          (response as ExperimentTargetBoundViewV1).target,
          expected,
          reason: '${entry.key} must name the target it was resolved against',
        );
      }
    });

    test('a replacement may omit an arm a binding does not name', () {
      final base = _draftChoices();
      final binding = (base['metricBindings']! as List<Object?>).first!
          as Map<String, Object?>;
      final sets = binding['armProjectionSets']! as List<Object?>;
      final planning = Map<String, Object?>.from(
        (base['analysisSelection']!
                as Map<String, Object?>)['planningSelection']!
            as Map<String, Object?>,
      );

      // A third arm, added but not yet named by the binding.
      final complete = {
        ...base,
        'analysisSelection': {
          'kind': 'fixedHorizonNArmRate',
          'planningSelection': {
            ...planning,
            'allocationWeights': [
              ...planning['allocationWeights']! as List<Object?>,
              const {'armId': 'arm.added', 'relativeWeight': 1},
            ],
          },
        },
        'arms': [
          ...base['arms']! as List<Object?>,
          _armChoice(
            'arm.added',
            'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
          ),
        ],
      };

      Map<String, Object?> withSets(List<Object?> replacementSets) => {
            ...complete,
            'metricBindings': [
              {...binding, 'armProjectionSets': replacementSets},
              ...(base['metricBindings']! as List<Object?>).skip(1),
            ],
          };

      // An arm with no entry is the arm that takes what its siblings measure.
      final missing = withSets(sets);
      expect(
        () => ExperimentDraftChoicesV1.fromJson(missing),
        throwsA(isA<CanonicalFormatException>()),
        reason: 'what the platform returns still covers every arm',
      );
      expect(
        ExperimentDraftChoicesV1.fromJson(
          missing,
          asReplacement: true,
        ).metricBindings.first.armProjectionSets,
        hasLength(sets.length),
      );

      // An id the draft does not have, and a repeated id, are still refused.
      for (final invalid in <List<Object?>>[
        [
          ...sets,
          {
            ...sets.first! as Map<String, Object?>,
            'stableArmId': 'arm.not-in-this-draft',
          },
        ],
        [...sets, sets.first],
      ]) {
        expect(
          () => ExperimentDraftChoicesV1.fromJson(
            withSets(invalid),
            asReplacement: true,
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('keeps refused results strict for every operation', () {
      for (final operation in ExperimentAuthoringOperationV1.values) {
        final valid = {
          'correlationId': 'correlation-refused-${operation.wireName}',
          'kind': 'refused',
          'operation': operation.wireName,
          'refusal': const {
            'code': 'staleDraft',
            'kind': 'experimentAuthoringRefusal',
            'messageKey': 'experiment.authoring.staleDraft',
            'retryable': false,
            'schemaVersion': 1,
          },
          'schemaVersion': 1,
        };
        final result = ExperimentAuthoringResultV1.fromJson(valid);
        _expectNoSensitiveKeys(result.toJson());

        for (final invalid in <Map<String, Object?>>[
          {...valid, 'schemaVersion': 2},
          {
            ...valid,
            'refusal': {
              ...(valid['refusal']! as Map<String, Object?>),
              'unexpected': true,
            },
          },
        ]) {
          expect(
            () => ExperimentAuthoringResultV1.fromJson(invalid),
            throwsA(isA<CanonicalFormatException>()),
            reason: '${operation.wireName}: $invalid',
          );
        }
      }
    });
  });

  group('strict bounded codecs', () {
    test('bounds result correlation, refusal text, and response cursors', () {
      final accepted = {
        'correlationId': 'correlation-result-bounds-1',
        'kind': 'accepted',
        'operation': 'listExperiments',
        'response': _listView(),
        'schemaVersion': 1,
      };
      final refused = {
        'correlationId': 'correlation-refusal-bounds-1',
        'kind': 'refused',
        'operation': 'listExperiments',
        'refusal': const {
          'code': 'backendUnavailable',
          'kind': 'experimentAuthoringRefusal',
          'messageKey': 'experiment.authoring.backendUnavailable',
          'retryable': true,
          'schemaVersion': 1,
        },
        'schemaVersion': 1,
      };

      for (final invalid in <Map<String, Object?>>[
        {...accepted, 'correlationId': 'x' * 4097},
        {
          ...accepted,
          'response': {..._listView(), 'nextPageCursor': 'x' * 4097},
        },
        {...refused, 'correlationId': 'x' * 4097},
        {
          ...refused,
          'refusal': {
            ...(refused['refusal']! as Map<String, Object?>),
            'messageKey': 'x' * 4097,
          },
        },
      ]) {
        expect(
          () => ExperimentAuthoringResultV1.fromJson(invalid),
          throwsA(isA<CanonicalFormatException>()),
          reason: invalid.toString(),
        );
      }
    });

    test('requires byte-exact canonical results for both result branches', () {
      final values = <Map<String, Object?>>[
        {
          'correlationId': 'correlation-canonical-accepted-1',
          'kind': 'accepted',
          'operation': 'activateDraft',
          'response': _activation(),
          'schemaVersion': 1,
        },
        {
          'correlationId': 'correlation-canonical-refused-1',
          'kind': 'refused',
          'operation': 'activateDraft',
          'refusal': const {
            'code': 'staleDraft',
            'kind': 'experimentAuthoringRefusal',
            'messageKey': 'experiment.authoring.staleDraft',
            'retryable': false,
            'schemaVersion': 1,
          },
          'schemaVersion': 1,
        },
      ];

      for (final value in values) {
        final canonical = CanonicalJsonCodec.encode(value);
        expect(
          ExperimentAuthoringResultV1.fromCanonicalBytes(canonical)
              .canonicalBytes,
          orderedEquals(canonical),
        );
        expect(
          () => ExperimentAuthoringResultV1.fromCanonicalBytes([
            0x20,
            ...canonical,
          ]),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('rejects unknown properties at every public boundary', () {
      final decoders = <void Function(Map<String, Object?>)>[
        (json) => ExperimentAuthoringRequestV1.fromJson(json),
        (json) => ExperimentAuthoringResultV1.fromJson(json),
        (json) => ExperimentTargetDiscoveryV1.fromJson(json),
        (json) => ExperimentDraftViewV1.fromJson(json),
        (json) => ExperimentValidationViewV1.fromJson(json),
        (json) => ExperimentNArmPlanningPreviewV1.fromJson(json),
        (json) => ExperimentReviewViewV1.fromJson(json),
        (json) => ExperimentActivationAcceptedViewV1.fromJson(json),
        (json) => ExperimentListViewV1.fromJson(json),
        (json) => ExperimentSummaryV1.fromJson(json),
        (json) => ExperimentReadViewV1.fromJson(json),
        (json) => ExperimentResultsViewV1.fromJson(json),
      ];
      final values = [
        _minimalRequest('discoverTargetsAndCapabilities'),
        {
          'correlationId': 'correlation-result-2',
          'kind': 'accepted',
          'operation': 'discoverTargetsAndCapabilities',
          'response': _discovery(),
          'schemaVersion': 1,
        },
        _discovery(),
        _draftView(),
        _validation(),
        _planningPreview(),
        _review(),
        _activation(),
        _listView(),
        _summary(),
        _detail(),
        _results(),
      ];

      for (var index = 0; index < decoders.length; index++) {
        expect(
          () => decoders[index]({...values[index], 'unexpected': true}),
          throwsA(isA<CanonicalFormatException>()),
          reason: values[index]['kind'] as String?,
        );
      }

      final nestedRequest = _minimalRequest('readDraft');
      expect(
        () => ExperimentAuthoringRequestV1.fromJson({
          ...nestedRequest,
          'payload': {
            ...(nestedRequest['payload']! as Map<String, Object?>),
            'unexpected': true,
          },
        }),
        throwsA(isA<CanonicalFormatException>()),
      );

      expect(
        () => ExperimentTargetDiscoveryV1.fromJson({
          ..._discovery(),
          'target': {..._target(), 'unexpected': true},
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentDraftViewV1.fromJson({
          ..._draftView(),
          'choices': {..._draftChoices(), 'unexpected': true},
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentNArmPlanningPreviewV1.fromJson({
          ..._planningPreview(),
          'reviewedSelection': {
            ..._planningSelection(),
            'unexpected': true,
          },
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentAuthoringResultV1.fromJson({
          'correlationId': 'correlation-result-3',
          'kind': 'refused',
          'operation': 'activateDraft',
          'refusal': const {
            'code': 'staleDraft',
            'kind': 'experimentAuthoringRefusal',
            'messageKey': 'experiment.authoring.staleDraft',
            'retryable': false,
            'schemaVersion': 1,
            'unexpected': true,
          },
          'schemaVersion': 1,
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('enforces canonical byte ceilings before materializing input', () {
      expect(experimentAuthoringMaximumRequestBytes, 16 * 1024 * 1024);
      expect(experimentAuthoringMaximumResultBytes, 16 * 1024 * 1024);

      final oversizedRequest = CanonicalJsonCodec.encode({
        ..._minimalRequest('discoverTargetsAndCapabilities'),
        'correlationId': 'x' * experimentAuthoringMaximumRequestBytes,
      });
      final oversizedResult = CanonicalJsonCodec.encode({
        'correlationId': 'x' * experimentAuthoringMaximumResultBytes,
        'kind': 'accepted',
        'operation': 'discoverTargetsAndCapabilities',
        'response': _discovery(),
        'schemaVersion': 1,
      });

      expect(
        () => ExperimentAuthoringRequestV1.fromCanonicalBytes(
          oversizedRequest,
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentAuthoringResultV1.fromCanonicalBytes(oversizedResult),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('rejects unsupported versions and alternate JSON spellings', () {
      expect(
        () => ExperimentAuthoringRequestV1.fromJson({
          ..._minimalRequest('discoverTargetsAndCapabilities'),
          'schemaVersion': 2,
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentReviewReferenceV1.fromJson({
          ..._reviewReference(),
          'schemaVersion': 2,
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentAuthoringRequestV1.fromCanonicalBytes(
          utf8.encode(' ${jsonEncode(
            _minimalRequest(
              'discoverTargetsAndCapabilities',
            ),
          )}'),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('bounds arm, issue, and list collections', () {
      expect(
        () => ExperimentDraftViewV1.fromJson({
          ..._draftView(),
          'choices': {
            ..._draftChoices(),
            'arms': List<Object?>.generate(
              17,
              (index) => _armChoice('arm.$index', 'surface.$index.v1'),
            ),
          },
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      final discovery = ExperimentTargetDiscoveryV1.fromJson({
        ..._discovery(),
        'surfaceCapabilities': List<Object?>.generate(
          97,
          (index) => _surfaceCapability(
            _mintedSurfaceRevisionId('surface.$index.v1'),
          ),
        ),
      });
      expect(
        discovery.surfaceCapabilities,
        hasLength(97),
      );
      expect(
        () => ExperimentValidationViewV1.fromJson({
          ..._validation(),
          'issues': List<Object?>.generate(
            257,
            (index) => {
              'code': 'guardrailUnavailable',
              'fieldPath': 'guardrails[$index]',
              'kind': 'experimentValidationIssue',
              'messageKey': 'experiment.validation.guardrailUnavailable',
            },
          ),
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentListViewV1.fromJson({
          ..._listView(),
          'experiments': List<Object?>.filled(101, _summary()),
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    });
  });

  group('an exact surface reference names what Restage minted', () {
    Map<String, Object?> reference(String surfaceId, String revisionId) =>
        <String, Object?>{
          'kind': 'exactSurfaceReference',
          'surfaceId': surfaceId,
          'surfaceRevisionId': revisionId,
        };

    test('the minted pair is admitted', () {
      final decoded = ExperimentExactSurfaceReferenceV1.fromJson(
        reference(
          _mintedSurfaceId('surface.checkout'),
          _mintedSurfaceRevisionId('surface.checkout.v4'),
        ),
      );

      expect(
        isMintedMeasurementIdentity(
          decoded.surfaceId.value,
          kMintedSurfaceIdPrefix,
        ),
        isTrue,
      );
      expect(
        isMintedMeasurementIdentity(
          decoded.surfaceRevisionId.value,
          kMintedSurfaceRevisionIdPrefix,
        ),
        isTrue,
      );
    });

    test('a slug is refused where a minted identity belongs', () {
      // A slug is what an author calls a surface. Nothing joins on it, so a
      // reference carrying one names no surface the platform can find.
      expect(
        () => ExperimentExactSurfaceReferenceV1.fromJson(
          reference(
            'checkout',
            _mintedSurfaceRevisionId('surface.checkout.v4'),
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => ExperimentExactSurfaceReferenceV1.fromJson(
          reference(_mintedSurfaceId('surface.checkout'), 'checkout.v4'),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('the prefix alone is not an identity', () {
      // A truncated digest, a digest that is not lowercase hexadecimal, and
      // the bare prefix all read as minted to a prefix check alone.
      for (final surfaceId in <String>[
        kMintedSurfaceIdPrefix,
        '${kMintedSurfaceIdPrefix}9f2c',
        '$kMintedSurfaceIdPrefix${'g' * 64}',
        '$kMintedSurfaceIdPrefix${'a' * 65}',
      ]) {
        expect(
          () => ExperimentExactSurfaceReferenceV1.fromJson(
            reference(
              surfaceId,
              _mintedSurfaceRevisionId('surface.checkout.v4'),
            ),
          ),
          throwsA(isA<CanonicalFormatException>()),
          reason: surfaceId,
        );
      }
    });
  });

  group('draft choices project onto the mutation vocabulary', () {
    void expectAdmitted(Map<String, Object?> replacement, String correlation) {
      final request = ExperimentAuthoringRequestV1.fromJson(
        _request(
          operation: 'replaceDraft',
          correlationId: correlation,
          idempotencyKey: 'idempotency-$correlation',
          payload: {..._draftBinding(), 'replacement': replacement},
        ),
      );
      expect(request.payload['replacement'], replacement);
      expect(
        _containsKeyFragment(request.toJson(), 'resolvedExactRef'),
        isFalse,
      );
      expect(_containsKeyFragment(request.toJson(), 'resolvedValue'), isFalse);
      expect(
        _containsKeyFragment(request.toJson(), 'resolvedMembers'),
        isFalse,
      );
      expect(_containsKeyFragment(request.toJson(), 'source'), isFalse);
      expect(
        _containsKeyFragment(request.toJson(), 'registeredAdapterSelection'),
        isFalse,
      );
      expect(
        _containsKeyFragment(request.toJson(), 'adverseDirection'),
        isFalse,
      );
    }

    test('complete choices are admitted as a replacement', () {
      expectAdmitted(
        ExperimentDraftChoicesV1.fromJson(_draftChoices())
            .toMutationChoicesJson(),
        'correlation-complete-projection-1',
      );
    });

    test('resolved partial choices are admitted as a replacement', () {
      expectAdmitted(
        ExperimentResolvedPartialDraftChoicesV1.fromJson(
          _resolvedPartialDraftChoices(),
        ).toMutationChoicesJson(),
        'correlation-partial-projection-1',
      );
    });

    test('zero choices are admitted as a replacement', () {
      expectAdmitted(
        ExperimentResolvedPartialDraftChoicesV1.fromJson(
          _resolvedPartialDraftChoices(zero: true),
        ).toMutationChoicesJson(),
        'correlation-zero-projection-1',
      );
    });

    test('a projection carries the selection kinds the author chose', () {
      final projected = ExperimentDraftChoicesV1.fromJson(_draftChoices())
          .toMutationChoicesJson();

      expect(
        projected['assignmentAudienceSelection'],
        const {'kind': 'serverDefault'},
      );
      expect(
        projected['assignmentEligibilitySelection'],
        {
          'exactRef': (_draftChoices()['assignmentEligibilitySelection']!
              as Map<String, Object?>)['resolvedExactRef'],
          'kind': 'exactRef',
        },
      );
      expect(
        projected['randomizedUnitSelection'],
        const {'kind': 'explicitValue', 'value': 'installation'},
      );
      expect(projected['subjectSelection'], const {'kind': 'subjectless'});
      expect(projected['kind'], 'experimentDraftChoices');
    });

    test('an arm carries its stable id, weight and candidate', () {
      final projected = ExperimentDraftChoicesV1.fromJson(_draftChoices())
          .toMutationChoicesJson();
      final arm =
          (projected['arms']! as List<Object?>).first! as Map<String, Object?>;

      expect(arm['stableArmId'], 'arm.control');
      expect(arm['relativeWeight'], 1);
      expect(arm['kind'], 'experimentDraftArmChoice');
      expect(
        (arm['candidateSelection']! as Map<String, Object?>)['kind'],
        'exactRef',
      );
    });
  });
}

Map<String, Object?> _request({
  required String operation,
  required String correlationId,
  required Map<String, Object?> payload,
  String? idempotencyKey,
}) =>
    {
      'correlationId': correlationId,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      'kind': 'experimentAuthoringRequest',
      'operation': operation,
      'payload': payload,
      'schemaVersion': 1,
    };

Map<String, Object?> _minimalRequest(String operation) {
  switch (operation) {
    case 'discoverTargetsAndCapabilities':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        payload: const {'pageSize': 100},
      );
    case 'openDraft':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: const {},
      );
    case 'readDraft':
    case 'validateDraft':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        payload: _draftBinding(),
      );
    case 'resolveDraft':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        payload: const {'draftId': 'draft-9f2c'},
      );
    case 'replaceDraft':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: {
          ..._draftBinding(),
          'replacement': _incompleteDraftMutationChoices(),
        },
      );
    case 'copyDraftToTarget':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: {
          'sourceDraft': _draftBinding(),
          'sourceTarget': _target(),
        },
      );
    case 'reviewDraft':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: _draftBinding(),
      );
    case 'activateDraft':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: {
          ..._draftBinding(),
          'reviewReference': _reviewReference(),
        },
      );
    case 'pauseExperiment':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: const {
          'expectedLifecycleOrdinal': 8,
          'experimentId': 'experiment.checkout',
        },
      );
    case 'resumeExperiment':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: const {
          'expectedLifecycleOrdinal': 9,
          'experimentId': 'experiment.checkout',
        },
      );
    case 'concludeExperiment':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: const {
          'expectedLifecycleOrdinal': 10,
          'experimentId': 'experiment.checkout',
        },
      );
    case 'listExperiments':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        payload: const {'pageSize': 50},
      );
    case 'readExperiment':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        payload: const {'experimentId': 'experiment.checkout'},
      );
    case 'readExperimentResults':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        payload: {
          'activationOrdinal': 7,
          'experimentId': 'experiment.checkout',
          'resultDigest': _digest('9'),
        },
      );
    case 'setExperimentArchived':
      return _request(
        operation: operation,
        correlationId: 'correlation-minimal-1',
        idempotencyKey: 'idempotency-minimal-1',
        payload: const {
          'archived': true,
          'expectedControlPlaneOrdinal': 8,
          'experimentId': 'experiment.checkout',
        },
      );
    default:
      throw StateError('Unknown semantic operation');
  }
}

Map<String, Object?> _draftBinding() => const {
      'draftId': 'experiment-draft-checkout',
      'draftRevisionId': 'experiment-draft-checkout.v3',
      'expectedCas': 'draft-cas-3',
    };

Map<String, Object?> _target() => const {
      'appId': 23,
      'environmentTargetId': 31,
      'kind': 'targetCoordinate',
      'namedEnvironmentId': 37,
      'organizationId': 11,
      'runtimePlane': 'live',
      'schemaVersion': 1,
    };

Map<String, Object?> _otherTarget() => {
      ..._target(),
      'environmentTargetId': 32,
    };

Map<String, Object?> _surfaceReference(
  String revisionId, {
  String surfaceName = 'surface.checkout',
}) =>
    {
      'kind': 'exactSurfaceReference',
      'surfaceId': _mintedSurfaceId(surfaceName),
      'surfaceRevisionId': revisionId,
    };

Map<String, Object?> _exactCandidate(String revisionId) => {
      'kind': 'exactCandidate',
      'label': 'Checkout candidate',
      'surfaceReference': _surfaceReference(revisionId),
      'treatmentOrigin': const {
        'kind': 'wholeSurface',
        'locusIds': ['locus.checkout'],
      },
    };

Map<String, Object?> _largePointSubtreeCandidate() {
  final locusPadding = 'a' * 115;
  final lineagePadding = 'a' * 109;
  return {
    'kind': 'exactCandidate',
    'label': 'Large complete candidate',
    'surfaceReference': _surfaceReference(
      'surface-revision.v1.b1805f2d0a0fc67603555afcd37bc0f96734ad5f5cbee91e45456fea0af3d1dd',
    ),
    'treatmentOrigin': {
      'basePublicationContext': {
        'artifactGraphHash': _digest('3'),
        'kind': 'exactSurfaceContext',
        'measurementManifestHash': _digest('4'),
        'surfaceReference': _surfaceReference(
          'surface-revision.v1.b1960277217db54b0cd99afa5a86489092cc6e65df7a49fd507100c565fe894b',
        ),
      },
      'kind': 'pointSubtree',
      'loci': List<Object?>.generate(1024, (index) {
        final ordinal = index.toString().padLeft(4, '0');
        return {
          'locusId': 'locus.$ordinal.$locusPadding',
          'pointLineageCanonicalHash': _digest('6'),
          'presentedPointLineageId': 'point-lineage.$ordinal.$lineagePadding',
        };
      }),
    },
  };
}

Map<String, Object?> _canonicalAuthorityDefaultSource({
  required String authorityKind,
  required String authorityId,
  required String authorityRevisionId,
  required String digestDigit,
}) =>
    {
      'authorityId': authorityId,
      'authorityKind': authorityKind,
      'authorityRevisionId': authorityRevisionId,
      'canonicalDigest': _digest(digestDigit),
      'kind': 'canonicalAuthority',
      'semanticDigest': _digest(digestDigit),
    };

Map<String, Object?> _publicationCandidateDefaultSource(
  Map<String, Object?> candidate,
) =>
    {'candidate': candidate, 'kind': 'publicationCandidate'};

Map<String, Object?> _installedProjectionDefaultSource(
  String projectionRevisionId,
  String digestDigit,
) =>
    {
      'canonicalDigest': _digest(digestDigit),
      'kind': 'installedProjection',
      'projectionRevisionId': projectionRevisionId,
      'semanticDigest': _digest(digestDigit),
    };

Map<String, Object?> _slotProjectionReference(
  String projectionRevisionId,
  String digestDigit,
) =>
    {
      'canonicalDigest': _digest(digestDigit),
      'projectionRevisionId': projectionRevisionId,
      'semanticDigest': _digest(digestDigit),
    };

Map<String, Object?> _surfaceCapability(String revisionId) => {
      'analysisChoices': ['measureOnly', 'fixedHorizonNArmRate'],
      'deliverySurfaceType': 'general',
      'installedMetricCapabilities': [
        _installedMetricCapability(
          metricDefinitionId: 'metric.completed-checkout',
          metricDefinitionRevisionId: 'metric.completed-checkout.v2',
          metricDefinitionSemanticDigestDigit: '1',
          installedProjectionSets: [
            _installedProjectionSetCapability(
              metricBindingId: 'metric-binding.completed-checkout',
              projectionSetId: 'projection-set.completed-checkout.control',
              projectionRevisionId: 'projection.checkout.control.v1',
              slotId: 'slot.checkout.completed',
              digestDigit: '1',
            ),
            _installedProjectionSetCapability(
              metricBindingId: 'metric-binding.completed-checkout',
              projectionSetId: 'projection-set.completed-checkout.variant',
              projectionRevisionId: 'projection.checkout.variant.v1',
              slotId: 'slot.checkout.completed',
              digestDigit: '2',
            ),
          ],
        ),
      ],
      'kind': 'experimentSurfaceCapability',
      'label': 'Published surface',
      'surfaceReference': _surfaceReference(revisionId),
      'treatmentOrigins': [
        {
          'kind': 'wholeSurface',
          'locusIds': ['locus.$revisionId.whole'],
        },
        {
          'basePublicationContext': {
            'artifactGraphHash': _digest('3'),
            'kind': 'exactSurfaceContext',
            'measurementManifestHash': _digest('4'),
            'surfaceReference': _surfaceReference(
              _mintedSurfaceRevisionId('$revisionId.base'),
            ),
          },
          'kind': 'pointSubtree',
          'loci': [
            {
              'locusId': 'locus.$revisionId.point',
              'pointLineageCanonicalHash': _digest('5'),
              'presentedPointLineageId': 'lineage.$revisionId.point',
            },
          ],
        },
      ],
    };

Map<String, Object?> _maximumSurfaceCapability({required int pointCount}) {
  // A surface identity has one shape and one length, so the ceiling this
  // capability probes is carried by the identifiers that are still free.
  final surfaceId = _mintedSurfaceId('maximum');
  final revisionId = _mintedSurfaceRevisionId('maximum');
  final baseSurfaceId = _mintedSurfaceId('maximum-base');
  final baseRevisionId = _mintedSurfaceRevisionId('maximum-base');
  return {
    'analysisChoices': ['measureOnly'],
    'deliverySurfaceType': _maximumIdentifier('delivery.'),
    'installedMetricCapabilities': <Object?>[],
    'kind': 'experimentSurfaceCapability',
    'label': 'l' * 4096,
    'surfaceReference': {
      'kind': 'exactSurfaceReference',
      'surfaceId': surfaceId,
      'surfaceRevisionId': revisionId,
    },
    'treatmentOrigins': [
      {
        'kind': 'wholeSurface',
        'locusIds': [_maximumIdentifier('whole-locus.')],
      },
      {
        'basePublicationContext': {
          'artifactGraphHash': _digest('3'),
          'kind': 'exactSurfaceContext',
          'measurementManifestHash': _digest('4'),
          'surfaceReference': {
            'kind': 'exactSurfaceReference',
            'surfaceId': baseSurfaceId,
            'surfaceRevisionId': baseRevisionId,
          },
        },
        'kind': 'pointSubtree',
        'loci': List<Object?>.generate(pointCount, (index) {
          final suffix = index.toString().padLeft(4, '0');
          return {
            'locusId': _maximumIdentifier('locus.$suffix.'),
            'pointLineageCanonicalHash': _digest('6'),
            'presentedPointLineageId': _maximumIdentifier(
              'point-lineage.$suffix.',
            ),
          };
        }),
      },
    ],
  };
}

String _maximumIdentifier(String prefix) =>
    '$prefix${'a' * (128 - prefix.length)}';

/// A surface identity in the shape the platform mints, named for its fixture.
String _mintedSurfaceId(String name) =>
    '$kMintedSurfaceIdPrefix${_nameDigest(name)}';

/// A surface-revision identity in the shape the platform mints.
String _mintedSurfaceRevisionId(String name) =>
    '$kMintedSurfaceRevisionIdPrefix${_nameDigest(name)}';

String _nameDigest(String name) => sha256.convert(utf8.encode(name)).toString();

Map<String, Object?> _installedProjectionSetMember({
  required String projectionRevisionId,
  required String slotId,
  required String digestDigit,
}) =>
    {
      'kind': 'experimentInstalledProjectionSetMember',
      'projectionReference': _slotProjectionReference(
        projectionRevisionId,
        digestDigit,
      ),
      'slotId': slotId,
    };

Map<String, Object?> _installedProjectionSetCapability({
  required String metricBindingId,
  required String projectionSetId,
  required String projectionRevisionId,
  required String slotId,
  required String digestDigit,
  List<Map<String, Object?>>? members,
}) {
  final resolvedMembers = members ??
      [
        _installedProjectionSetMember(
          projectionRevisionId: projectionRevisionId,
          slotId: slotId,
          digestDigit: digestDigit,
        ),
      ];
  return {
    'compatibilityProofReference': {
      'canonicalDigest': _digest(digestDigit),
      'compatibilityProofRevisionId': 'proof.$projectionSetId.v1',
      'semanticDigest': _digest(digestDigit),
    },
    'kind': 'experimentInstalledProjectionSetCapability',
    'label': 'Installed $projectionSetId',
    'members': resolvedMembers,
    'metricBindingReference': {
      'canonicalDigest': _digest(digestDigit),
      'metricBindingId': metricBindingId,
      'metricBindingRevisionId': '$metricBindingId.v1',
      'semanticDigest': _digest(digestDigit),
    },
    'projectionSetReference': {
      'canonicalDigest': _digest(digestDigit),
      'projectionSetId': projectionSetId,
      'semanticDigest': _digest(digestDigit),
    },
  };
}

Map<String, Object?> _installedMetricCapability({
  required String metricDefinitionId,
  required String metricDefinitionRevisionId,
  required String metricDefinitionSemanticDigestDigit,
  required List<Map<String, Object?>> installedProjectionSets,
}) =>
    {
      'availability': installedProjectionSets.isEmpty
          ? const {
              'kind': 'unavailable',
              'reasonCode': 'metric.installedProjectionUnavailable',
            }
          : const {'kind': 'available'},
      'installedProjectionSets': installedProjectionSets,
      'kind': 'experimentInstalledMetricCapability',
      'metricDefinitionId': metricDefinitionId,
      'metricDefinitionRevisionId': metricDefinitionRevisionId,
      'metricDefinitionSemanticDigest': _digest(
        metricDefinitionSemanticDigestDigit,
      ),
    };

Map<String, Object?> _discovery() => {
      'actionAvailability': [
        for (final action in [
          'experiment.read',
          'experiment.draft.create',
          'experiment.draft.edit',
          'experiment.validate',
          'experiment.activate',
          'experiment.archive',
        ])
          {
            'action': action,
            'available': action != 'experiment.activate',
            'kind': 'experimentActionAvailability',
            if (action == 'experiment.activate')
              'reasonCode': 'experiment.action.requiresAdmin',
          },
      ],
      'appLabel': 'Storefront',
      'environmentLabel': 'Production',
      'kind': 'experimentTargetDiscovery',
      'metricCapabilities': [
        {
          'analysisChoices': ['measureOnly', 'fixedHorizonNArmRate'],
          'availability': const {'kind': 'available'},
          'direction': 'higherIsBetter',
          'kind': 'experimentMetricCapability',
          'label': 'Completed checkout',
          'metricDefinitionId': 'metric.completed-checkout',
          'metricDefinitionRevisionId': 'metric.completed-checkout.v2',
          'metricDefinitionSemanticDigest': _digest('1'),
          'metricKind': 'rate',
        },
        {
          'analysisChoices': <Object?>[],
          'availability': const {
            'kind': 'unavailable',
            'reasonCode': 'metric.presentationUnavailable',
          },
          'direction': 'none',
          'kind': 'experimentMetricCapability',
          'label': 'Order value',
          'metricDefinitionId': 'metric.order-value',
          'metricDefinitionRevisionId': 'metric.order-value.v1',
          'metricDefinitionSemanticDigest': _digest('2'),
          'metricKind': 'distribution',
        },
      ],
      'namedEnvironments': const [
        {
          'kind': 'experimentNamedEnvironmentOption',
          'label': 'Production',
          'namedEnvironmentId': 37,
          'selected': true,
        },
      ],
      'organizationLabel': 'Example organization',
      'nextPageCursor': null,
      'runtimePlanes': const [
        {
          'kind': 'experimentRuntimePlaneOption',
          'label': 'Sandbox',
          'runtimePlane': 'sandbox',
          'selected': false,
        },
        {
          'kind': 'experimentRuntimePlaneOption',
          'label': 'Live',
          'runtimePlane': 'live',
          'selected': true,
        },
      ],
      'schemaVersion': 1,
      'surfaceCapabilities': [
        _surfaceCapability(
          'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        ),
      ],
      'target': _target(),
    };

Map<String, Object?> _armChoice(String armId, String revisionId) => {
      'candidate': {
        ..._exactCandidate(revisionId),
        'label': armId == 'arm.control' ? 'Current' : 'Updated',
      },
      'kind': 'experimentDraftArmChoice',
      'label': armId == 'arm.control' ? 'Control' : 'Variant',
      'relativeWeight': 1,
      'stableArmId': armId,
    };

Map<String, Object?> _draftChoices() => {
      'analysisSelection': {
        'kind': 'fixedHorizonNArmRate',
        'planningSelection': _planningSelection(),
      },
      'arms': [
        _armChoice(
          'arm.control',
          'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        ),
        _armChoice(
          'arm.variant',
          'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
        ),
      ],
      'assignmentAudienceSelection': {
        'kind': 'serverDefault',
        'resolvedExactRef': const {
          'policyId': 'audience.installed',
          'revisionId': 'audience.installed.v2',
          'semanticDigest':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        },
        'source': _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'audience.installed',
          authorityRevisionId: 'audience.installed.v2',
          digestDigit: 'a',
        ),
      },
      'assignmentEligibilitySelection': {
        'kind': 'exactRef',
        'resolvedExactRef': const {
          'policyId': 'eligibility.active',
          'revisionId': 'eligibility.active.v3',
          'semanticDigest':
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        },
      },
      'description': 'Compare two compatible checkout surfaces.',
      'diagnosticBindingIds': <Object?>[],
      'guardrails': [
        const {
          'guardrailId': 'guardrail.checkout-errors',
          'kind': 'experimentDraftGuardrailChoice',
          'metricBindingId': 'metric-binding.checkout-errors',
        },
      ],
      'kind': 'experimentDraftChoices',
      'label': 'Checkout completion',
      'layerHoldoutIds': <Object?>[],
      'memberHoldouts': <Object?>[],
      'memberNoTreatment': {
        'kind': 'serverDefault',
        'resolvedExactRef': _exactCandidate(
          'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        ),
        'source': _publicationCandidateDefaultSource(
          _exactCandidate(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
        ),
      },
      'metricBindings': [
        _completeMetricBinding(
          bindingId: 'metric-binding.completed-checkout',
          label: 'Completed checkout',
          metricId: 'metric.completed-checkout',
          metricRevisionId: 'metric.completed-checkout.v2',
          digestDigit: '1',
        ),
        _completeMetricBinding(
          bindingId: 'metric-binding.checkout-errors',
          label: 'Checkout errors',
          metricId: 'metric.checkout-errors',
          metricRevisionId: 'metric.checkout-errors.v1',
          digestDigit: '2',
          direction: 'lowerIsBetter',
        ),
      ],
      'primaryBindingSelection': {
        'kind': 'exactRef',
        'resolvedExactRef': const {
          'metricBindingId': 'metric-binding.completed-checkout',
        },
      },
      'randomizedUnitSelection': {
        'kind': 'explicitValue',
        'value': 'installation',
      },
      'rootSurfaceSelection': {
        'kind': 'serverDefault',
        'resolvedExactRef': _surfaceReference(
          'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        ),
        'source': _publicationCandidateDefaultSource(
          _exactCandidate(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
        ),
      },
      'subjectSelection': const {'kind': 'subjectless'},
    };

Map<String, Object?> _completeMetricBinding({
  required String bindingId,
  required String label,
  required String metricId,
  required String metricRevisionId,
  required String digestDigit,
  String direction = 'higherIsBetter',
}) =>
    {
      'armProjectionSets': [
        for (final arm in ['control', 'variant'])
          _resolvedArmProjectionSetChoice(
            installedMetricBindingId: 'installed-binding.$bindingId.$arm',
            installedProjectionSetId:
                'installed-projection-set.$bindingId.$arm',
            projectionRevisionId: 'projection.$bindingId.$arm.v1',
            slotId: 'slot.$bindingId',
            stableArmId: 'arm.$arm',
            digestDigit: digestDigit,
          ),
      ],
      'kind': 'experimentDraftMetricBindingChoice',
      'label': label,
      'metricBindingId': bindingId,
      'metricDefinitionChoice': {
        'kind': 'exactRef',
        'resolvedExactRef': {
          'direction': direction,
          'metricDefinitionId': metricId,
          'metricDefinitionRevisionId': metricRevisionId,
          'metricDefinitionSemanticDigest': _digest(digestDigit),
        },
      },
    };

Map<String, Object?> _resolvedArmProjectionSetChoice({
  required String installedMetricBindingId,
  required String installedProjectionSetId,
  required String projectionRevisionId,
  required String slotId,
  required String stableArmId,
  required String digestDigit,
}) {
  final group = _installedProjectionSetCapability(
    metricBindingId: installedMetricBindingId,
    projectionSetId: installedProjectionSetId,
    projectionRevisionId: projectionRevisionId,
    slotId: slotId,
    digestDigit: digestDigit,
  );
  return {
    'installedProjectionSetChoice': {
      'kind': 'exactRef',
      'resolvedExactRef': group,
    },
    'kind': 'experimentDraftArmProjectionSetChoice',
    'resolvedMembers': group['members'],
    'stableArmId': stableArmId,
  };
}

Map<String, Object?> _policyReference(String policyId) => {
      'policyId': policyId,
      'revisionId': '$policyId.v1',
      'semanticDigest': _digest('a'),
    };

Map<String, Object?> _metricDefinitionReference({
  String direction = 'higherIsBetter',
  String metricDefinitionId = 'metric.completed-checkout',
}) =>
    {
      'direction': direction,
      'metricDefinitionId': metricDefinitionId,
      'metricDefinitionRevisionId': 'metric.completed-checkout.v2',
      'metricDefinitionSemanticDigest': _digest('1'),
    };

Map<String, Object?> _resolvedPartialDraftChoices({bool zero = false}) => {
      'analysisSelection': const {'kind': 'unselected'},
      'arms': zero
          ? <Object?>[]
          : [
              {
                'candidateSelection': {
                  'kind': 'exactRef',
                  'resolvedExactRef': {
                    ..._exactCandidate(
                      'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
                    ),
                    'label': 'Current checkout',
                  },
                },
                'kind': 'experimentDraftArmChoice',
                'label': 'Control',
                'relativeWeight': 1,
                'stableArmId': 'arm.control',
              },
            ],
      'assignmentAudienceSelection': {
        'kind': 'serverDefault',
        'resolvedExactRef': _policyReference('audience.installed'),
        'source': _canonicalAuthorityDefaultSource(
          authorityKind: 'assignmentAudiencePolicy',
          authorityId: 'audience.installed',
          authorityRevisionId: 'audience.installed.v1',
          digestDigit: 'a',
        ),
      },
      'assignmentEligibilitySelection': const {'kind': 'unselected'},
      'description': '',
      'diagnosticBindingIds': <Object?>[],
      'guardrails': <Object?>[],
      'kind': 'experimentDraftChoices',
      'label': '',
      'layerHoldoutIds': <Object?>[],
      'memberHoldouts': <Object?>[],
      'memberNoTreatment': {
        'kind': 'serverDefault',
        'resolvedExactRef': _exactCandidate(
          'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        ),
        'source': _publicationCandidateDefaultSource(
          _exactCandidate(
            'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
          ),
        ),
      },
      'metricBindings': zero
          ? <Object?>[]
          : [
              {
                'armProjectionSets': [
                  _resolvedArmProjectionSetChoice(
                    installedMetricBindingId:
                        'installed-binding.completed-checkout.control',
                    installedProjectionSetId:
                        'installed-projection-set.completed-checkout.control',
                    projectionRevisionId: 'projection.checkout.control.v1',
                    slotId: 'slot.checkout.completed',
                    stableArmId: 'arm.control',
                    digestDigit: '1',
                  ),
                ],
                'kind': 'experimentDraftMetricBindingChoice',
                'label': '',
                'metricBindingId': 'metric-binding.completed-checkout',
                'metricDefinitionChoice': {
                  'kind': 'exactRef',
                  'resolvedExactRef': _metricDefinitionReference(),
                },
              },
            ],
      'primaryBindingSelection': zero
          ? const {'kind': 'unselected'}
          : const {
              'kind': 'exactRef',
              'resolvedExactRef': {
                'metricBindingId': 'metric-binding.completed-checkout',
              },
            },
      'randomizedUnitSelection': {
        'kind': 'explicitValue',
        'value': 'installation',
      },
      'rootSurfaceSelection': zero
          ? const {'kind': 'unselected'}
          : {
              'kind': 'serverDefault',
              'resolvedExactRef': _surfaceReference(
                'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
              ),
              'source': _publicationCandidateDefaultSource(
                _exactCandidate(
                  'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
                ),
              ),
            },
      'subjectSelection': const {'kind': 'subjectless'},
    };

Map<String, Object?> _partialProjectionChoice(
  String projectionId,
  String slotId,
) =>
    _installedProjectionSetMember(
      projectionRevisionId: '$projectionId.v1',
      slotId: slotId,
      digestDigit: '1',
    );

Map<String, Object?> _partialDraftViewWithProjections(
  List<Map<String, Object?>> projections,
) {
  final choices = _resolvedPartialDraftChoices();
  final binding = Map<String, Object?>.from(
    (choices['metricBindings']! as List).single as Map,
  );
  final projectionSet = Map<String, Object?>.from(
    (binding['armProjectionSets']! as List).single as Map,
  )..['resolvedMembers'] = projections;
  binding['armProjectionSets'] = [projectionSet];
  choices['metricBindings'] = [binding];
  return {
    ..._draftView(),
    'choices': choices,
    'completeness': const {
      'kind': 'incomplete',
      'missingFieldPaths': ['analysisSelection'],
    },
  };
}

Map<String, Object?> _incompleteDraftMutationChoices({
  Map<String, Object?>? assignmentAudienceSelection,
  Map<String, Object?>? assignmentEligibilitySelection,
  Map<String, Object?>? randomizedUnitSelection,
  Map<String, Object?>? rootSurfaceSelection,
  Map<String, Object?>? memberNoTreatmentSelection,
  Map<String, Object?>? primaryBindingSelection,
  Map<String, Object?>? candidateSelection,
  Map<String, Object?>? metricDefinitionSelection,
  Map<String, Object?>? projectionSelection,
  Map<String, Object?>? subjectSelection,
  Map<String, Object?>? planningSelection,
}) =>
    {
      'analysisSelection': planningSelection == null
          ? const {'kind': 'unselected'}
          : {
              'kind': 'fixedHorizonNArmRate',
              'planningSelection': planningSelection,
            },
      'arms': [
        {
          'candidateSelection':
              candidateSelection ?? const {'kind': 'unselected'},
          'kind': 'experimentDraftArmChoice',
          'label': 'Control',
          'relativeWeight': 1,
          'stableArmId': 'arm.control',
        },
        {
          'candidateSelection': {'kind': 'unselected'},
          'kind': 'experimentDraftArmChoice',
          'label': 'Variant',
          'relativeWeight': 1,
          'stableArmId': 'arm.variant',
        },
      ],
      'assignmentAudienceSelection':
          assignmentAudienceSelection ?? const {'kind': 'serverDefault'},
      'assignmentEligibilitySelection':
          assignmentEligibilitySelection ?? const {'kind': 'unselected'},
      'description': '',
      'diagnosticBindingIds': <Object?>[],
      'guardrails': <Object?>[],
      'kind': 'experimentDraftChoices',
      'label': 'Checkout completion',
      'layerHoldoutIds': <Object?>[],
      'memberHoldouts': <Object?>[],
      'memberNoTreatment':
          memberNoTreatmentSelection ?? const {'kind': 'serverDefault'},
      'metricBindings': [
        {
          'armProjectionSets': [
            {
              'installedProjectionSetChoice':
                  projectionSelection ?? const {'kind': 'unselected'},
              'kind': 'experimentDraftArmProjectionSetChoice',
              'stableArmId': 'arm.control',
            },
          ],
          'kind': 'experimentDraftMetricBindingChoice',
          'label': 'Completed checkout',
          'metricBindingId': 'metric-binding.completed-checkout',
          'metricDefinitionChoice':
              metricDefinitionSelection ?? const {'kind': 'unselected'},
        },
      ],
      'primaryBindingSelection':
          primaryBindingSelection ?? const {'kind': 'unselected'},
      'randomizedUnitSelection':
          randomizedUnitSelection ?? const {'kind': 'serverDefault'},
      'rootSurfaceSelection':
          rootSurfaceSelection ?? const {'kind': 'unselected'},
      'subjectSelection': subjectSelection ?? const {'kind': 'subjectless'},
    };

Map<String, Object?> _mutationChoicesWithInstalledProjectionSets(
  List<Map<String, Object?>> armProjectionSets,
) {
  final choices = _incompleteDraftMutationChoices();
  final binding = Map<String, Object?>.from(
    (choices['metricBindings']! as List).single as Map,
  )..['armProjectionSets'] = armProjectionSets;
  choices['metricBindings'] = [binding];
  return choices;
}

Map<String, Object?> _installedProjectionSetMutationChoice({
  required String stableArmId,
  required Map<String, Object?> exactRef,
}) =>
    {
      'installedProjectionSetChoice': {
        'kind': 'exactRef',
        'exactRef': exactRef,
      },
      'kind': 'experimentDraftArmProjectionSetChoice',
      'stableArmId': stableArmId,
    };

Map<String, Object?> _draftView() => {
      'completeness': const {'kind': 'complete'},
      'conflicts': <Object?>[],
      'choices': _draftChoices(),
      'draftId': 'experiment-draft-checkout',
      'draftRevisionId': 'experiment-draft-checkout.v3',
      'expectedCas': 'draft-cas-3',
      'experimentId': 'experiment.checkout',
      'kind': 'experimentDraftView',
      'revisionOrdinal': 3,
      'schemaVersion': 1,
      'semanticDigest': _digest('b'),
      'target': _target(),
    };

Map<String, Object?> _planningSelection({bool explicit = false}) => {
      'allocationWeights': [
        const {'armId': 'arm.control', 'relativeWeight': 1},
        const {'armId': 'arm.variant', 'relativeWeight': 1},
      ],
      'alphaChoice': explicit
          ? _explicitChoice(_rational(1, 20))
          : _resolvedDefaultChoice(_rational(1, 20)),
      'direction': 'higherIsBetter',
      'enrollmentCap': 12000,
      'expectedBaseline': _rational(1, 10),
      'followUpDurationMicros': 86400000000,
      'guardrails': [
        {
          'adverseDirection': 'higherIsWorse',
          'expectedReferenceRate': _rational(1, 50),
          'guardrailId': 'guardrail.checkout-errors',
          'harmMargin': _rational(1, 100),
          'targetPower': _rational(4, 5),
        },
      ],
      'kind': 'experimentNArmPlanningSelection',
      'maximumEnrollmentDurationMicros': 1209600000000,
      'minimumDetectableEffect': _rational(1, 50),
      'outcomeGracePeriodMicros': 172800000000,
      'primaryTargetPowerChoice': explicit
          ? _explicitChoice(_rational(4, 5))
          : _resolvedDefaultChoice(_rational(4, 5)),
      'practicalSuperiorityMarginChoice': explicit
          ? _explicitChoice(_rational(1, 100))
          : _resolvedDefaultChoice(_rational(1, 100)),
      'referenceArmId': 'arm.control',
      'registeredAdapterSelection': {
        'kind': 'serverDefault',
        'resolvedExactRef': {
          'adapterId': 'adapter.rate',
          'revisionId': 'adapter.rate.v2',
          'semanticHash': _digest('8'),
        },
        'source': _canonicalAuthorityDefaultSource(
          authorityKind: 'registeredInferenceAdapter',
          authorityId: 'adapter.rate',
          authorityRevisionId: 'adapter.rate.v2',
          digestDigit: '8',
        ),
      },
      'schemaVersion': 1,
    };

Map<String, Object?> _planningMutationSelection({bool explicit = false}) {
  final selection = _planningSelection(explicit: explicit)
    ..remove('direction')
    ..remove('registeredAdapterSelection');
  selection['guardrails'] = [
    for (final guardrail in selection['guardrails']! as List)
      Map<String, Object?>.from(guardrail as Map)..remove('adverseDirection'),
  ];
  selection['alphaChoice'] = explicit
      ? _explicitChoice(_rational(1, 20))
      : const {'kind': 'serverDefault'};
  selection['primaryTargetPowerChoice'] = explicit
      ? _explicitChoice(_rational(4, 5))
      : const {'kind': 'serverDefault'};
  selection['practicalSuperiorityMarginChoice'] = explicit
      ? _explicitChoice(_rational(1, 100))
      : const {'kind': 'serverDefault'};
  return selection;
}

Map<String, Object?> _fixedHorizonMutationChoices(
  Map<String, Object?> planning,
) =>
    {
      ..._incompleteDraftMutationChoices(),
      'analysisSelection': {
        'kind': 'fixedHorizonNArmRate',
        'planningSelection': planning,
      },
    };

Map<String, Object?> _statisticalDefaults() => {
      'alpha': _rational(1, 20),
      'kind': 'experimentStatisticalDefaultsV1',
      'margin': _rational(1, 100),
      'power': _rational(4, 5),
    };

Map<String, Object?> _resolvedDefaultChoice(Map<String, Object?> value) => {
      'kind': 'serverDefault',
      'resolvedValue': value,
      'source': _statisticalDefaults(),
    };

Map<String, Object?> _explicitChoice(Map<String, Object?> value) => {
      'kind': 'explicitValue',
      'value': value,
    };

Map<String, Object?> _rational(int numerator, int denominator) => {
      'denominator': denominator,
      'numerator': numerator,
    };

Map<String, Object?> _planningPreview() => {
      'allocationAuthorityDigest': _digest('3'),
      'certifiedScales': const {
        'allocationScale': '1000000',
        'effectScale': '1000000000',
      },
      'feasibility': 'feasible',
      'kind': 'experimentNArmPlanningPreview',
      'plannedFollowUpDurationMicros': 86400000000,
      'plannedMaximumEnrollmentDurationMicros': 1209600000000,
      'plannedPerArmEnrollment': const {
        'arm.control': 5000,
        'arm.variant': 5000,
      },
      'plannedTotalEnrollment': 10000,
      'plannerIdentityDigest': _digest('4'),
      'planningIntentDigest': _digest('2'),
      'resultDigest': _digest('5'),
      'reviewedSelection': _planningSelection(),
      'schemaVersion': 1,
    };

Map<String, Object?> _planningFailurePreview(String feasibility) => {
      'allocationAuthorityDigest': _digest('3'),
      'feasibility': feasibility,
      'kind': 'experimentNArmPlanningPreview',
      'planningIntentDigest': _digest('2'),
      'reviewedSelection': _planningSelection(),
      'schemaVersion': 1,
    };

Map<String, Object?> _validation() => {
      'capabilityReasons': const [
        {
          'code': 'metricReadUnavailable',
          'kind': 'experimentCapabilityReason',
          'referenceId': 'metric.order-value.v1',
        },
      ],
      'draftBinding': _draftBinding(),
      'issues': const [
        {
          'code': 'guardrailUnavailable',
          'fieldPath': 'guardrails[0]',
          'kind': 'experimentValidationIssue',
          'messageKey': 'experiment.validation.guardrailUnavailable',
        },
      ],
      'kind': 'experimentValidationView',
      'planningPreview': _planningPreview(),
      'schemaVersion': 1,
    };

Map<String, Object?> _reviewReference() => {
      'kind': 'experimentReviewReference',
      'recordDigest': _digest('6'),
      'reviewId': 'experiment-review-checkout-3',
      'schemaVersion': 1,
    };

Map<String, Object?> _review() => {
      'configuration': _draftChoices(),
      'consequences': const [
        {
          'code': 'manualPromotionOnly',
          'kind': 'experimentReviewConsequence',
          'messageKey': 'experiment.review.manualPromotionOnly',
        },
        {
          'code': 'noInterimLooks',
          'kind': 'experimentReviewConsequence',
          'messageKey': 'experiment.review.noInterimLooks',
        },
      ],
      'draftBinding': _draftBinding(),
      'issuedAtMicros': 1788091200000000,
      'kind': 'experimentReviewView',
      'planningPreview': _planningPreview(),
      'projectionDigest': _digest('7'),
      'recordDigest': _digest('6'),
      'reviewReference': _reviewReference(),
      'schemaVersion': 1,
    };

Map<String, Object?> _liveReadReference() => {
      'activationOrdinal': 7,
      'experimentId': 'experiment.checkout',
      'kind': 'experimentLiveReadReference',
      'receiptDigest': _digest('c'),
      'target': _target(),
    };

Map<String, Object?> _activation() => {
      'activationOrdinal': 7,
      'experimentEpochId': 'experiment.checkout.epoch.7',
      'experimentId': 'experiment.checkout',
      'experimentRevisionId': 'experiment.checkout.v7',
      'immutablePublicationDigest': _digest('d'),
      'kind': 'experimentActivationAcceptedView',
      'lifecycleOrdinal': 8,
      'liveReadReference': _liveReadReference(),
      'receiptDigest': _digest('c'),
      'schemaVersion': 1,
      'target': _target(),
    };

Map<String, Object?> _lifecycleAccepted({
  required String lifecycleState,
  required int lifecycleOrdinal,
}) =>
    {
      if (lifecycleState == 'active')
        'experimentEpochId': 'experiment.checkout.epoch.8',
      'experimentId': 'experiment.checkout',
      'kind': 'experimentLifecycleAcceptedView',
      'lifecycleOrdinal': lifecycleOrdinal,
      'lifecycleState': lifecycleState,
      'receiptDigest': _digest('c'),
      'schemaVersion': 1,
      'target': _target(),
      'transitionedAtMicros': 1788091300000000,
    };

Map<String, Object?> _summary({
  bool archived = false,
  String lifecycleState = 'active',
}) =>
    {
      'acceptedAtMicros': 1788091201000000,
      'activationOrdinal': 7,
      'archivedAtMicros': archived ? 1788091300000000 : null,
      'controlPlaneOrdinal': archived ? 11 : 10,
      'experimentId': 'experiment.checkout',
      'inferenceReference': const {
        'kind': 'unavailable',
        'reasonCode': 'experiment.inference.pending',
      },
      'integrityState': 'verified',
      'kind': 'experimentSummary',
      'label': 'Checkout completion',
      'lifecycleOrdinal': 8,
      'lifecycleState': lifecycleState,
      'liveReadReference': _liveReadReference(),
      'pendingDraft': const {'kind': 'none'},
      'schemaVersion': 1,
      'target': _target(),
    };

Map<String, Object?> _integrityUnavailableSummary({
  bool archived = false,
  String lifecycleState = 'active',
}) {
  final summary = _summary(archived: archived, lifecycleState: lifecycleState)
    ..['integrityState'] = 'unavailable'
    ..['kind'] = 'experimentIntegrityUnavailableSummary'
    ..remove('label');
  return summary;
}

Map<String, Object?> _draftSummary({
  String experimentId = 'experiment.checkout',
  String draftId = 'experiment-draft-checkout',
  String draftRevisionId = 'experiment-draft-checkout.v3',
  int controlPlaneOrdinal = 12,
  bool complete = true,
  bool archived = false,
  String? label,
  Map<String, Object?>? target,
}) =>
    {
      'archivedAtMicros': archived ? 1788091300000000 : null,
      'completeness': complete
          ? const {'kind': 'complete'}
          : const {
              'kind': 'incomplete',
              'missingFieldPaths': ['analysisSelection'],
            },
      'controlPlaneOrdinal': controlPlaneOrdinal,
      'createdAtMicros': 1788091200000000,
      'draftId': draftId,
      'draftRevisionId': draftRevisionId,
      'experimentId': experimentId,
      'kind': 'experimentDraftSummary',
      'label': label ?? (complete ? 'Checkout completion' : ''),
      'liveState': const {
        'kind': 'unavailable',
        'reasonCode': 'notActivated',
      },
      'schemaVersion': 1,
      'target': target ?? _target(),
    };

Map<String, Object?> _listView() => {
      'experiments': [_summary()],
      'kind': 'experimentListView',
      'nextPageCursor': 'cursor-4',
      'schemaVersion': 1,
      'target': _target(),
    };

Map<String, Object?> _detail({
  bool archived = false,
  String lifecycleState = 'active',
}) =>
    {
      'arms': const [
        {
          'kind': 'experimentArmDetail',
          'label': 'Control',
          'relativeWeight': 1,
          'stableArmId': 'arm.control',
          'surfaceRevisionId':
              'surface-revision.v1.bf52ce6e8d6a0ea45d1f4c6680a8cf340c02f1f2f25449c37e221d472647d281',
        },
        {
          'kind': 'experimentArmDetail',
          'label': 'Variant',
          'relativeWeight': 1,
          'stableArmId': 'arm.variant',
          'surfaceRevisionId':
              'surface-revision.v1.7d3075e37f279dc1bfc10615efd7f342804f3c7140c1a412b3be04591e07fef1',
        },
      ],
      'description': 'Compare two compatible checkout surfaces.',
      'kind': 'experimentDetail',
      'schemaVersion': 1,
      'summary': _summary(
        archived: archived,
        lifecycleState: lifecycleState,
      ),
    };

Map<String, Map<String, Object?>> _acceptedResponses() => {
      'discoverTargetsAndCapabilities': _discovery(),
      'openDraft': _draftView(),
      'readDraft': _draftView(),
      'resolveDraft': _draftView(),
      'replaceDraft': _draftView(),
      'copyDraftToTarget': _draftView(),
      'validateDraft': _validation(),
      'reviewDraft': _review(),
      'activateDraft': _activation(),
      'pauseExperiment': _lifecycleAccepted(
        lifecycleState: 'paused',
        lifecycleOrdinal: 9,
      ),
      'resumeExperiment': _lifecycleAccepted(
        lifecycleState: 'active',
        lifecycleOrdinal: 10,
      ),
      'concludeExperiment': _lifecycleAccepted(
        lifecycleState: 'concluded',
        lifecycleOrdinal: 11,
      ),
      'listExperiments': _listView(),
      'readExperiment': _detail(),
      'readExperimentResults': _results(),
      'setExperimentArchived': _detail(archived: true),
    };

Map<String, Object?> _draftDetail({
  Map<String, Object?>? summary,
  Map<String, Object?>? draft,
}) =>
    {
      'draft': draft ?? _draftView(),
      'kind': 'experimentDraftDetail',
      'schemaVersion': 1,
      'summary': summary ?? _draftSummary(),
    };

Map<String, Object?> _results({String lifecycleState = 'active'}) => {
      'analysis': 'fixedHorizonNArmRate',
      'armResults': const [
        {
          'admittedCount': 5000,
          'effect': {'denominator': 1, 'numerator': 0},
          'interval': {
            'lower': {'denominator': 1000, 'numerator': 87},
            'upper': {'denominator': 1000, 'numerator': 113},
          },
          'kind': 'experimentArmResult',
          'observedCount': 5000,
          'rate': {'denominator': 10, 'numerator': 1},
          'stableArmId': 'arm.control',
          'successCount': 500,
        },
        {
          'admittedCount': 5000,
          'effect': {'denominator': 1000, 'numerator': 5},
          'interval': {
            'lower': {'denominator': 1000, 'numerator': -8},
            'upper': {'denominator': 1000, 'numerator': 18},
          },
          'kind': 'experimentArmResult',
          'observedCount': 5000,
          'rate': {'denominator': 1000, 'numerator': 105},
          'stableArmId': 'arm.variant',
          'successCount': 525,
        },
      ],
      'availability': const {'kind': 'available'},
      'designDigest': _digest('e'),
      'epochDigest': _digest('f'),
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
      'lifecycleState': lifecycleState,
      'resultDigest': _digest('9'),
      'schemaVersion': 1,
      'structuredCopyKeys': const [
        'experiment.result.noDecision',
        'experiment.result.guardrailWithinBound',
      ],
      'target': _target(),
    };

String _digest(String character) => character * 64;

File _experimentAuthoringSourceFile() => File.fromUri(
      _measurementSchemaPackageDirectory().uri.resolve(
            'lib/src/experiment_authoring.dart',
          ),
    );

Directory _measurementSchemaPackageDirectory() {
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = Directory.fromUri(
      directory.uri.resolve('packages/restage_measurement_schema/'),
    );
    if (candidate.existsSync()) return candidate;
    if (File.fromUri(directory.uri.resolve('pubspec.yaml')).existsSync() &&
        directory.path.endsWith('restage_measurement_schema')) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate restage_measurement_schema');
    }
    directory = parent;
  }
}

bool _containsKeyFragment(Object? value, String fragment) {
  if (value is List<Object?>) {
    return value.any((entry) => _containsKeyFragment(entry, fragment));
  }
  if (value is! Map<String, Object?>) return false;
  return value.entries.any(
    (entry) =>
        entry.key.contains(fragment) ||
        _containsKeyFragment(entry.value, fragment),
  );
}

void _expectNoSensitiveKeys(
  Object? value, {
  bool request = false,
  String path = r'$',
}) {
  if (value is List<Object?>) {
    for (var index = 0; index < value.length; index++) {
      _expectNoSensitiveKeys(
        value[index],
        request: request,
        path: '$path[$index]',
      );
    }
    return;
  }
  if (value is! Map<String, Object?>) return;

  for (final entry in value.entries) {
    final normalized = entry.key.toLowerCase();
    expect(
      RegExp(
        r'(^|[_-])project(?:$|[_-]|Id$|Slug$|Ref$|Coordinate$|Selector$)|'
        r'Project(?:Id|Slug|Ref|Coordinate|Selector)?$',
      ).hasMatch(entry.key),
      isFalse,
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('credential')),
      reason: '$path.${entry.key}',
    );
    expect(normalized, isNot(contains('secret')), reason: '$path.${entry.key}');
    expect(normalized, isNot(contains('salt')), reason: '$path.${entry.key}');
    if (normalized != 'compatibilityproofreference' &&
        !path.endsWith('.compatibilityProofReference')) {
      expect(
        normalized,
        isNot(contains('proof')),
        reason: '$path.${entry.key}',
      );
    }
    expect(
      normalized,
      isNot(contains('pseudonym')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('canonicalbytes')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('opaquetarget')),
      reason: '$path.${entry.key}',
    );
    expect(normalized, isNot(contains('ittrow')), reason: '$path.${entry.key}');
    expect(
      normalized,
      isNot(contains('allocationscope')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('allocationcapability')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('familyreference')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('fullpublication')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('fullbasepublication')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('fulloutputpublication')),
      reason: '$path.${entry.key}',
    );
    expect(
      normalized,
      isNot(contains('resolvedcandidate')),
      reason: '$path.${entry.key}',
    );
    if (normalized.contains('bytes')) {
      fail('Public JSON contains a byte carrier at $path.${entry.key}');
    }
    if (request) {
      expect(normalized, isNot(equals('target')), reason: '$path.${entry.key}');
      expect(
        normalized,
        isNot(contains('epoch')),
        reason: '$path.${entry.key}',
      );
      expect(normalized, isNot(contains('head')), reason: '$path.${entry.key}');
      expect(
        normalized,
        isNot(contains('receipt')),
        reason: '$path.${entry.key}',
      );
      expect(
        normalized,
        isNot(contains('inference')),
        reason: '$path.${entry.key}',
      );
    }
    _expectNoSensitiveKeys(
      entry.value,
      request: request,
      path: '$path.${entry.key}',
    );
  }
}
