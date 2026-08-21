import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'flow_experiment_test_support.dart';

void main() {
  group('FlowExperimentClientContractV1', () {
    test('exports the frozen V1 wire kind and version', () {
      expect(
        kFlowExperimentClientContractKindV1,
        'flowExperimentClientContract',
      );
      expect(kFlowExperimentContractKind, 'flow');
      expect(
        kFlowExperimentContractKind,
        isNot(kFlowExperimentClientContractKindV1),
      );
      expect(kFlowExperimentClientContractVersionV1, 1);
    });

    test('emits exact compact canonical bytes and domain-separated hash', () {
      final contract = experimentClientContract();
      final canonical = utf8.decode(contract.canonicalBytes);
      final document = contract.documents.single;
      final flowJson = utf8.decode(document.canonicalFlowDocumentBytes);
      final expected = '{"actionBindings":[],"contractVersion":1,'
          '"deliveryMode":"typed","descriptor":{"id":"first_run",'
          '"minClient":3,"version":1},"documents":[{"contentHash":'
          '"${document.contentHash.value}","flowDocument":$flowJson,'
          '"flowId":"first_run","minClient":3,"requiredLibraries":[],'
          '"schemaVersion":1,"surfaceType":"onboarding","version":1}],'
          '"installedCapability":{"builtInCatalogVersion":5,'
          '"installedLibraries":[]},"installedSignals":[],'
          '"kind":"flowExperimentClientContract",'
          '"surfaceType":"onboarding"}';

      expect(canonical, expected);
      expect(canonical, isNot(contains(RegExp(r'\s'))));
      expect(
        contract.contentHash.value,
        'sha256:${crypto.sha256.convert([
              ...utf8.encode(
                'restage.flow-experiment-client-contract.v1\n',
              ),
              ...utf8.encode(expected),
            ])}',
      );
      expect(
        contract.contentHash.value,
        'sha256:315005913d819f1298d05d1cd98645c7'
        '64176aaca6e8805e3b205865ab0edb9a',
      );
    });

    test('round-trips canonical bytes through the strict decoder', () {
      final original = experimentClientContract(
        installedCapability: InstalledCapability(
          builtInCatalogVersion: 7,
          installedLibraries: const [
            // Explicit null is the V1 wire proof for an unversioned library.
            // ignore: avoid_redundant_argument_values
            InstalledLibrary(namespace: 'zeta.widgets', version: null),
            InstalledLibrary(namespace: 'acme.widgets', version: 2),
          ],
        ),
        installedSignals: const ['skip', 'cancel'],
      );

      final decoded =
          FlowExperimentClientContractV1.decode(original.canonicalBytes);

      expect(decoded.canonicalBytes, original.canonicalBytes);
      expect(decoded.contentHash, original.contentHash);
      expect(
        decoded.installedCapability.installedLibraries
            .map((library) => library.namespace),
        ['acme.widgets', 'zeta.widgets'],
      );
      expect(decoded.installedSignals, ['cancel', 'skip']);
    });

    test('sorts semantic arrays independently of input order', () {
      final second = experimentDocumentContract(
        document: experimentDocument(flow: 'alpha_flow'),
      );
      final first = experimentDocumentContract(
        document: experimentDocument(
          flow: 'zeta_flow',
          states: {
            'child': SubFlowState(
              flow: second.flowId,
              version: second.version,
              schemaVersion: second.schemaVersion,
              minClient: second.minClient,
              contentHash: second.contentHash,
              input: const {},
              onComplete: const [],
              defaultBranch: const FlowBranchTarget(target: 'done'),
            ),
            'done': const EndFlowState(result: {'completed': true}),
          },
        ),
      );
      final contract = experimentClientContract(
        descriptor: const FlowExperimentDescriptor(
          id: 'zeta_flow',
          version: 1,
          minClient: 3,
        ),
        documents: [first, second],
        actionBindings: [
          experimentBinding(actionId: 'zeta', actionName: 'zeta'),
          experimentBinding(actionId: 'alpha', actionName: 'alpha'),
        ],
        installedSignals: const ['skip', 'cancel'],
      );

      expect(
        contract.documents.map((document) => document.flowId),
        ['alpha_flow', 'zeta_flow'],
      );
      expect(
        contract.actionBindings.map((binding) => binding.actionId),
        ['alpha', 'zeta'],
      );
      expect(contract.installedSignals, ['cancel', 'skip']);
    });

    test('rejects duplicate object keys before map materialization', () {
      final source = utf8.decode(experimentClientContract().canonicalBytes);
      final duplicate = source.replaceFirst(
          '"contractVersion":1,',
          '"contractVersion":1,'
              '"contractVersion":1,');

      expect(
        () => FlowExperimentClientContractV1.decode(utf8.encode(duplicate)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate object key'),
          ),
        ),
      );
    });

    test('rejects duplicate keys nested inside the flow document', () {
      final source = utf8.decode(experimentClientContract().canonicalBytes);
      final duplicates = [
        source.replaceFirst(
          '"flow":"first_run",',
          '"flow":"first_run","flow":"first_run",',
        ),
        source
            .replaceFirst(
              '"states":{"done":',
              '"states":{"done":',
            )
            .replaceFirst(
              '"kind":"end",',
              '"kind":"end","kind":"end",',
            ),
        source.replaceFirst(
          '"result":{"completed":true}',
          '"result":{"completed":true,"completed":true}',
        ),
      ];

      for (final duplicate in duplicates) {
        expect(
          () => FlowExperimentClientContractV1.decode(utf8.encode(duplicate)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Duplicate object key'),
            ),
          ),
        );
      }
    });

    test('rejects unknown, missing, null, and floating wrapper fields', () {
      final source = utf8.decode(experimentClientContract().canonicalBytes);
      final mutations = [
        source.replaceFirst(
          '"contractVersion":1,',
          '"contractVersion":1,"future":true,',
        ),
        source.replaceFirst('"contractVersion":1,', ''),
        source.replaceFirst('"contractVersion":1', '"contractVersion":null'),
        source.replaceFirst('"contractVersion":1', '"contractVersion":1.0'),
      ];

      for (final mutation in mutations) {
        expect(
          () => FlowExperimentClientContractV1.decode(utf8.encode(mutation)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects malformed UTF-8, BOM, and lone escaped surrogates', () {
      final source = experimentClientContract().canonicalBytes;
      final text = utf8.decode(source);

      expect(
        () => FlowExperimentClientContractV1.decode([
          ...source.take(8),
          0xC3,
          0x28,
          ...source.skip(8),
        ]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => FlowExperimentClientContractV1.decode(
          [0xEF, 0xBB, 0xBF, ...source],
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => FlowExperimentClientContractV1.decode(
          utf8.encode(text.replaceFirst('"first_run"', r'"\uD800"')),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unsupported versions, malformed hashes, and bad domains', () {
      final source = utf8.decode(experimentClientContract().canonicalBytes);
      final mutations = [
        source.replaceFirst('"contractVersion":1', '"contractVersion":2'),
        source.replaceFirst('"schemaVersion":1', '"schemaVersion":2'),
        source.replaceFirst('sha256:', 'md5:'),
        source.replaceFirst('"minClient":3', '"minClient":0'),
      ];

      for (final mutation in mutations) {
        expect(
          () => FlowExperimentClientContractV1.decode(utf8.encode(mutation)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects duplicate semantic identities', () {
      final rootDocument = experimentDocument(
        states: {
          'child': SubFlowState(
            flow: 'profile',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: _placeholderHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final child = experimentDocumentContract(
        document: experimentDocument(flow: 'profile'),
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 1),
        ],
      );
      final root = experimentDocumentContract(
        document: _replaceSubFlowHash(rootDocument, child.contentHash),
      );
      final contract = experimentClientContract(
        documents: [root, child],
        installedCapability: InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [
            InstalledLibrary(namespace: 'acme.widgets', version: 1),
          ],
        ),
        actionBindings: [experimentBinding()],
        installedSignals: const ['skip'],
      );
      final canonical = jsonDecode(utf8.decode(contract.canonicalBytes))
          as Map<String, Object?>;

      Map<String, Object?> copy() => _deepJsonCopy(canonical);
      final mutations = <Map<String, Object?>>[];

      final duplicateDocuments = copy();
      final documents = duplicateDocuments['documents']! as List<Object?>;
      documents.add(_deepJsonCopy(documents.first! as Map<String, Object?>));
      mutations.add(duplicateDocuments);

      final duplicateRequiredLibraries = copy();
      final requiredDocuments =
          duplicateRequiredLibraries['documents']! as List<Object?>;
      final requiredDocument = requiredDocuments[1]! as Map<String, Object?>;
      final requiredLibraries =
          requiredDocument['requiredLibraries']! as List<Object?>;
      requiredLibraries.add(
        _deepJsonCopy(requiredLibraries.first! as Map<String, Object?>),
      );
      mutations.add(duplicateRequiredLibraries);

      final duplicateInstalledLibraries = copy();
      final installed = duplicateInstalledLibraries['installedCapability']!
          as Map<String, Object?>;
      final installedLibraries =
          installed['installedLibraries']! as List<Object?>;
      installedLibraries.add(
        _deepJsonCopy(installedLibraries.first! as Map<String, Object?>),
      );
      mutations.add(duplicateInstalledLibraries);

      final duplicateActions = copy();
      final actions = duplicateActions['actionBindings']! as List<Object?>;
      actions.add(_deepJsonCopy(actions.first! as Map<String, Object?>));
      mutations.add(duplicateActions);

      final duplicateSignals = copy();
      final signals = duplicateSignals['installedSignals']! as List<Object?>;
      signals.add(signals.first);
      mutations.add(duplicateSignals);

      for (final mutation in mutations) {
        expect(
          () => FlowExperimentClientContractV1.decode(
            utf8.encode(jsonEncode(mutation)),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('allows distinct action IDs to share an action name', () {
      final contract = experimentClientContract(
        actionBindings: [
          experimentBinding(
            actionId: 'request_primary',
          ),
          experimentBinding(
            actionId: 'request_secondary',
          ),
        ],
      );

      final decoded =
          FlowExperimentClientContractV1.decode(contract.canonicalBytes);

      expect(
        decoded.actionBindings.map((binding) => binding.actionId),
        ['request_primary', 'request_secondary'],
      );
      expect(
        decoded.actionBindings.map((binding) => binding.actionName).toSet(),
        {'request_notifications'},
      );
    });

    test('rejects a wrapper hash that does not match production flow bytes',
        () {
      final source = utf8.decode(experimentClientContract().canonicalBytes);
      final badHash = 'sha256:${List.filled(64, '0').join()}';
      final mutated = source.replaceFirst(
        RegExp('sha256:[0-9a-f]{64}'),
        badHash,
      );

      expect(
        () => FlowExperimentClientContractV1.decode(utf8.encode(mutated)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects noncanonical whitespace, object keys, and semantic arrays',
        () {
      final contract = experimentClientContract(
        installedSignals: const ['cancel', 'skip'],
      );
      final source = utf8.decode(contract.canonicalBytes);
      final mutations = [
        ' $source',
        source.replaceFirst(
          '{"actionBindings":[],"contractVersion":1,',
          '{"contractVersion":1,"actionBindings":[],',
        ),
        source.replaceFirst(
          '"installedSignals":["cancel","skip"]',
          '"installedSignals":["skip","cancel"]',
        ),
        source.replaceFirst(
          '{"id":"first_run","minClient":3,"version":1}',
          '{"version":1,"minClient":3,"id":"first_run"}',
        ),
      ];

      for (final mutation in mutations) {
        expect(
          () => FlowExperimentClientContractV1.decode(utf8.encode(mutation)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('sorts object keys by unsigned UTF-8 bytes', () {
      final document = experimentDocument(
        states: const {
          'done': EndFlowState(
            result: {
              '\u{10000}': 'supplementary',
              '\uE000': 'bmp',
            },
          ),
        },
      );
      final canonical = utf8.decode(
        experimentClientContract(
          documents: [experimentDocumentContract(document: document)],
        ).canonicalBytes,
      );

      expect(
        canonical.indexOf('\uE000'),
        lessThan(canonical.indexOf('\u{10000}')),
      );
    });

    test('preserves Unicode scalars without normalization', () {
      const nfc = '\u00E9';
      const nfd = 'e\u0301';
      final document = experimentDocument(
        states: const {
          'done': EndFlowState(
            result: {'nfc': nfc, 'nfd': nfd},
          ),
        },
      );
      final contract = experimentClientContract(
        documents: [experimentDocumentContract(document: document)],
      );

      final decoded =
          FlowExperimentClientContractV1.decode(contract.canonicalBytes);
      final result = (decoded.documents.single.flowDocument.states['done']!
              as EndFlowState)
          .result;

      expect(result['nfc'], nfc);
      expect(result['nfd'], nfd);
      expect(result['nfc'], isNot(result['nfd']));
      expect(decoded.canonicalBytes, contract.canonicalBytes);
    });

    test('rejects unknown keys at every nested wrapper level', () {
      final contract = experimentClientContract(
        documents: [
          experimentDocumentContract(
            requiredLibraries: const [
              LibraryRequirement(namespace: 'acme.widgets', minVersion: 1),
            ],
          ),
        ],
        installedCapability: InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [
            InstalledLibrary(namespace: 'acme.widgets', version: 1),
          ],
        ),
        actionBindings: [experimentBinding()],
      );
      final canonical = jsonDecode(utf8.decode(contract.canonicalBytes))
          as Map<String, Object?>;
      Map<String, Object?> copy() => _deepJsonCopy(canonical);
      final mutations = <Map<String, Object?>>[];

      final topLevel = copy()..['future'] = true;
      mutations.add(topLevel);

      final descriptor = copy();
      (descriptor['descriptor']! as Map<String, Object?>)['future'] = true;
      mutations.add(descriptor);

      final document = copy();
      ((document['documents']! as List<Object?>).first!
          as Map<String, Object?>)['future'] = true;
      mutations.add(document);

      final requiredLibrary = copy();
      final requiredDocument = (requiredLibrary['documents']! as List<Object?>)
          .first! as Map<String, Object?>;
      ((requiredDocument['requiredLibraries']! as List<Object?>).first!
          as Map<String, Object?>)['future'] = true;
      mutations.add(requiredLibrary);

      final installedCapability = copy();
      (installedCapability['installedCapability']!
          as Map<String, Object?>)['future'] = true;
      mutations.add(installedCapability);

      final installedLibrary = copy();
      final installed =
          installedLibrary['installedCapability']! as Map<String, Object?>;
      ((installed['installedLibraries']! as List<Object?>).first!
          as Map<String, Object?>)['future'] = true;
      mutations.add(installedLibrary);

      final action = copy();
      ((action['actionBindings']! as List<Object?>).first!
          as Map<String, Object?>)['future'] = true;
      mutations.add(action);

      for (final mutation in mutations) {
        expect(
          () => FlowExperimentClientContractV1.decode(
            utf8.encode(jsonEncode(mutation)),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects invalid and floating integers in every wrapper domain', () {
      final contract = experimentClientContract(
        documents: [
          experimentDocumentContract(
            requiredLibraries: const [
              LibraryRequirement(namespace: 'acme.widgets', minVersion: 1),
            ],
          ),
        ],
        installedCapability: InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [
            InstalledLibrary(namespace: 'acme.widgets', version: 1),
          ],
        ),
        actionBindings: [experimentBinding()],
      );
      final source = utf8.decode(contract.canonicalBytes);
      final integerFields = <String>[
        '"contractVersion":1',
        '"descriptor":{"id":"first_run","minClient":3',
        '"minClient":3,"version":1},"documents"',
        '"flowId":"first_run","minClient":3',
        '"schemaVersion":1',
        '"surfaceType":"onboarding","version":1',
        '"minVersion":1',
        '"builtInCatalogVersion":5',
        '"version":1}]',
        '"contractVersion":1,"idempotent"',
        '"idempotent":false,"minClient":1',
      ];

      for (final field in integerFields) {
        expect(source, contains(field));
        final zero = source.replaceFirst(
          field,
          field.replaceFirst(RegExp(r'\d+'), '0'),
        );
        final floating = source.replaceFirst(
          field,
          field.replaceFirst(RegExp(r'\d+'), '1.5'),
        );
        expect(
          () => FlowExperimentClientContractV1.decode(utf8.encode(zero)),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => FlowExperimentClientContractV1.decode(utf8.encode(floating)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('producer and consumer canonicalization agree for every surface/mode',
        () {
      for (final surface in Surface.values) {
        for (final mode in FlowDeliveryMode.values) {
          final firstDocument = experimentDocument(
            deliveryMode: mode,
            flowState: const {
              'alpha': FlowStateDeclaration(
                type: FlowDataType.string,
                classification: FlowStateClassification.internal,
                defaultValue: 'a',
              ),
              'zeta': FlowStateDeclaration(
                type: FlowDataType.string,
                classification: FlowStateClassification.internal,
                defaultValue: 'z',
              ),
            },
          );
          final reorderedDocument = experimentDocument(
            deliveryMode: mode,
            flowState: const {
              'zeta': FlowStateDeclaration(
                type: FlowDataType.string,
                classification: FlowStateClassification.internal,
                defaultValue: 'z',
              ),
              'alpha': FlowStateDeclaration(
                type: FlowDataType.string,
                classification: FlowStateClassification.internal,
                defaultValue: 'a',
              ),
            },
          );
          final sdkContract = experimentClientContract(
            surfaceType: surface,
            deliveryMode: mode,
            documents: [
              experimentDocumentContract(
                document: firstDocument,
                surfaceType: surface,
                requiredLibraries: const [
                  LibraryRequirement(
                    namespace: 'zeta.widgets',
                    minVersion: 1,
                  ),
                  LibraryRequirement(
                    namespace: 'acme.widgets',
                    minVersion: 1,
                  ),
                ],
              ),
            ],
            installedSignals: const ['skip', 'cancel'],
          );
          final reordered = experimentClientContract(
            surfaceType: surface,
            deliveryMode: mode,
            documents: [
              experimentDocumentContract(
                document: reorderedDocument,
                surfaceType: surface,
                requiredLibraries: const [
                  LibraryRequirement(
                    namespace: 'acme.widgets',
                    minVersion: 1,
                  ),
                  LibraryRequirement(
                    namespace: 'zeta.widgets',
                    minVersion: 1,
                  ),
                ],
              ),
            ],
            installedSignals: const ['cancel', 'skip'],
          );
          final consumerDecoded =
              FlowExperimentClientContractV1.decode(sdkContract.canonicalBytes);

          expect(reordered.canonicalBytes, sdkContract.canonicalBytes);
          expect(consumerDecoded.canonicalBytes, sdkContract.canonicalBytes);
          expect(consumerDecoded.contentHash, sdkContract.contentHash);
        }
      }
    });

    test('preserves semantically ordered arrays inside FlowDocument', () {
      final first = experimentDocument(
        flowState: const {
          'country': FlowStateDeclaration(
            type: FlowDataType.string,
            classification: FlowStateClassification.internal,
            defaultValue: 'US',
          ),
        },
        states: _orderedDecisionStates(reverse: false),
      );
      final reversed = experimentDocument(
        flowState: const {
          'country': FlowStateDeclaration(
            type: FlowDataType.string,
            classification: FlowStateClassification.internal,
            defaultValue: 'US',
          ),
        },
        states: _orderedDecisionStates(reverse: true),
      );
      final firstBytes = experimentClientContract(
        documents: [experimentDocumentContract(document: first)],
      ).canonicalBytes;
      final reversedBytes = experimentClientContract(
        documents: [experimentDocumentContract(document: reversed)],
      ).canonicalBytes;

      expect(firstBytes, isNot(reversedBytes));
      expect(
        utf8.decode(firstBytes).indexOf('"literal":"US"'),
        lessThan(utf8.decode(firstBytes).indexOf('"literal":"CA"')),
      );
      expect(
        utf8.decode(reversedBytes).indexOf('"literal":"CA"'),
        lessThan(utf8.decode(reversedBytes).indexOf('"literal":"US"')),
      );
    });
  });
}

final FlowContentHash _placeholderHash = FlowContentHash.parse(
  'sha256:${List.filled(64, '0').join()}',
);

FlowDocument _replaceSubFlowHash(
  FlowDocument document,
  FlowContentHash hash,
) {
  final states = Map<String, FlowState>.of(document.states);
  final subFlow = states['child']! as SubFlowState;
  states['child'] = SubFlowState(
    flow: subFlow.flow,
    version: subFlow.version,
    schemaVersion: subFlow.schemaVersion,
    minClient: subFlow.minClient,
    contentHash: hash,
    input: subFlow.input,
    onComplete: subFlow.onComplete,
    defaultBranch: subFlow.defaultBranch,
    subFlowUnavailable: subFlow.subFlowUnavailable,
  );
  return document.copyWith(states: states);
}

Map<String, Object?> _deepJsonCopy(Map<String, Object?> source) {
  return jsonDecode(jsonEncode(source)) as Map<String, Object?>;
}

Map<String, FlowState> _orderedDecisionStates({required bool reverse}) {
  const us = FlowBranch(
    when: FlowBranchPredicate(
      fields: {
        'country': EqualsFlowPredicateCondition(
          value: LiteralFlowValueSource(
            type: FlowDataType.string,
            value: 'US',
          ),
        ),
      },
    ),
    target: 'done',
  );
  const ca = FlowBranch(
    when: FlowBranchPredicate(
      fields: {
        'country': EqualsFlowPredicateCondition(
          value: LiteralFlowValueSource(
            type: FlowDataType.string,
            value: 'CA',
          ),
        ),
      },
    ),
    target: 'done',
  );
  return {
    'route': DecisionFlowState(
      branches: reverse ? [ca, us] : [us, ca],
      defaultBranch: const FlowBranchTarget(target: 'done'),
    ),
    'done': const EndFlowState(result: {'completed': true}),
  };
}
