import 'dart:convert';
import 'dart:io';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('FlowDocumentCodec', () {
    test('canonical object keys are sorted recursively', () {
      final canonical = utf8.decode(
        FlowDocumentCodec.encodeCanonicalJson(_generatedProofDocument()),
      );

      expect(canonical, _firstRunCanonicalJson);
    });

    test('pretty JSON is indented and deterministic but not used for hashing',
        () {
      final pretty =
          FlowDocumentCodec.encodePrettyJson(_generatedProofDocument());
      final golden = _readGolden('first_run.flow.json');

      expect(pretty, golden);
      expect(pretty, isNot(_firstRunCanonicalJson));
    });

    test('canonical bytes hash is stable across map insertion order', () {
      final canonical = FlowDocumentCodec.encodeCanonicalJson(
        _generatedProofDocument(),
      );
      final reorderedCanonical = FlowDocumentCodec.encodeCanonicalJson(
        _generatedProofDocumentWithReorderedMaps(),
      );

      expect(reorderedCanonical, canonical);
      expect(
        FlowDocumentCodec.canonicalJsonSha256(
          _generatedProofDocumentWithReorderedMaps(),
        ),
        FlowDocumentCodec.canonicalJsonSha256(_generatedProofDocument()),
      );
      expect(
        FlowDocumentCodec.canonicalJsonSha256(_generatedProofDocument()),
        _firstRunCanonicalHash,
      );
    });

    test('explicit kind is required on every state when decoding JSON', () {
      final json = jsonDecode(_firstRunCanonicalJson) as Map<String, Object?>;
      final states = json['states']! as Map<String, Object?>;
      final welcome = Map<String, Object?>.from(
        states['welcome']! as Map<String, Object?>,
      )..remove('kind');
      json['states'] = {...states, 'welcome': welcome};

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown top-level fields fail closed at decode time', () {
      final json = _firstRunJson();
      json['operationIds'] = ['future_guard'];

      _expectUnsupportedFieldDecodeFailure(json, r'$.operationIds');
    });

    test('unknown screen artifact fields fail closed at decode time', () {
      final json = _firstRunJson();
      _object(_object(json['screenArtifacts'])['welcome'])['predicate'] = true;

      _expectUnsupportedFieldDecodeFailure(
        json,
        r'$.screenArtifacts.welcome.predicate',
      );
    });

    test('unknown screen state fields fail closed at decode time', () {
      final json = _firstRunJson();
      _object(_object(json['states'])['welcome'])['actions'] = ['track'];

      _expectUnsupportedFieldDecodeFailure(json, r'$.states.welcome.actions');
    });

    test('unknown end state fields fail closed at decode time', () {
      final json = _firstRunJson();
      _object(_object(json['states'])['done'])['predicate'] = true;

      _expectUnsupportedFieldDecodeFailure(json, r'$.states.done.predicate');
    });

    test('unknown goto transition fields fail closed at decode time', () {
      final json = _firstRunJson();
      final states = _object(json['states']);
      final welcome = _object(states['welcome']);
      final on = _object(welcome['on']);
      _object(on['next'])['predicate'] = true;

      _expectUnsupportedFieldDecodeFailure(
        json,
        r'$.states.welcome.on.next.predicate',
      );
    });

    test('decodes a document with an action contract and action transition',
        () {
      final json = _firstRunJsonWithAction();

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));
      final contract = decoded.actions['requestNotifications'];
      final transition =
          (decoded.states['welcome']! as ScreenFlowState).on['next'];

      expect(contract, isNotNull);
      expect(contract!.actionName, 'requestNotifications');
      expect(contract.contractVersion, 1);
      expect(
        contract.argsSchemaHash,
        FlowContentHash.parse(_emptyObjectArgsHash),
      );
      expect(
        contract.resultSchemaHash,
        FlowContentHash.parse(_boolResultHash),
      );
      expect(contract.minClient, 3);
      expect(contract.idempotent, false);
      expect(transition, isA<ActionFlowTransition>());
      expect(
        transition,
        isA<ActionFlowTransition>()
            .having((value) => value.action, 'action', 'requestNotifications')
            .having((value) => value.target, 'target', 'permissions')
            .having(
              (value) => value.resultPredicate,
              'resultPredicate',
              isA<BoolEqualsActionResultPredicate>().having(
                (predicate) => predicate.value,
                'value',
                true,
              ),
            ),
      );
    });

    test('decodes action schema ASTs alongside action schema hashes', () {
      final json = _firstRunJsonWithAction();
      final action = _object(_object(json['actions'])['requestNotifications']);
      action['argsSchema'] = {
        'kind': 'object',
        'fields': <String, Object?>{},
      };
      action['argsSchemaHash'] = _emptyObjectArgsHash;
      action['resultSchema'] = {
        'kind': 'object',
        'fields': {
          'granted': {
            'required': true,
            'schema': {'kind': 'bool'},
          },
        },
      };
      action['resultSchemaHash'] = _notificationResultHash;

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));
      final contract = decoded.actions['requestNotifications']!;

      expect(contract.argsSchema, isA<FlowObjectActionSchema>());
      expect(
        contract.resultSchema,
        isA<FlowObjectActionSchema>().having(
          (schema) => schema.fields,
          'fields',
          contains('granted'),
        ),
      );
    });

    test('encodes an action transition with a result predicate', () {
      final document = _firstRunDocument(
        actions: {
          'requestNotifications': const FlowActionContract(
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _emptyArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
          ),
        },
        transition: const ActionFlowTransition(
          action: 'requestNotifications',
          target: 'permissions',
          resultPredicate: BoolEqualsActionResultPredicate(value: true),
        ),
      );

      final json = jsonDecode(
        utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document)),
      ) as Map<String, Object?>;
      final transition = _object(
        _object(_object(_object(json['states'])['welcome'])['on'])['next'],
      );

      expect(transition['type'], 'action');
      expect(
        transition['resultPredicate'],
        {'kind': 'boolEquals', 'value': true},
      );
    });

    test('decodes and encodes Phase 1 documents without actions', () {
      final decoded = FlowDocumentCodec.decodeJson(_phase1CanonicalJson);
      final encoded =
          utf8.decode(FlowDocumentCodec.encodeCanonicalJson(decoded));
      final pretty = FlowDocumentCodec.encodePrettyJson(decoded);

      expect(decoded.actions, isEmpty);
      expect(decoded.flowState, isEmpty);
      expect(decoded.outbound, isEmpty);
      expect(decoded.legacyTerminalResultPassthrough, isTrue);
      expect(encoded, _phase1CanonicalJson);
      expect(pretty, isNot(contains('"actions"')));
      expect(pretty, isNot(contains('"flowState"')));
      expect(pretty, isNot(contains('"outbound"')));
    });

    test('missing flowState and outbound marks terminal passthrough legacy',
        () {
      final json = _firstRunJson()
        ..remove('flowState')
        ..remove('outbound');

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));

      expect(decoded.legacyTerminalResultPassthrough, isTrue);
    });

    test('explicit empty outbound is not legacy terminal passthrough', () {
      final json = _firstRunJson()
        ..remove('flowState')
        ..['outbound'] = <String, Object?>{};

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));

      expect(decoded.outbound.isEmpty, isTrue);
      expect(decoded.legacyTerminalResultPassthrough, isFalse);
    });

    test('explicit empty flowState is not legacy terminal passthrough', () {
      final json = _firstRunJson()
        ..['flowState'] = <String, Object?>{}
        ..remove('outbound');

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));

      expect(decoded.flowState, isEmpty);
      expect(decoded.legacyTerminalResultPassthrough, isFalse);
    });

    test('encoding explicit default-deny empties preserves outbound presence',
        () {
      final document = _firstRunDocument(
        actions: const {},
      );

      final encoded = jsonDecode(FlowDocumentCodec.encodePrettyJson(document))
          as Map<String, Object?>;

      expect(encoded['outbound'], <String, Object?>{});
      expect(encoded.containsKey('flowState'), isFalse);
    });

    test('round-trips flow state and outbound declarations', () {
      final json = _firstRunJson();
      json['flowState'] = _flowStateJson();
      json['outbound'] = _outboundJson();

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));
      final encoded = jsonDecode(
        utf8.decode(FlowDocumentCodec.encodeCanonicalJson(decoded)),
      ) as Map<String, Object?>;
      final terminalRef =
          decoded.outbound.terminalResult.fields['selectedPlan']!.ref;
      final actionArgRef =
          decoded.outbound.actionArgs['submitSurvey']!.fields['diet']!.ref;
      final customEventRef = decoded
          .outbound.customEvents['analyticsTap']!.fields['campaign']!.ref;

      expect(
        decoded.flowState['email'],
        isA<FlowStateDeclaration>().having(
          (declaration) => declaration.classification,
          'classification',
          FlowStateClassification.persistedAccount,
        ),
      );
      expect(
        terminalRef,
        isA<StateFlowOutboundRef>()
            .having((ref) => ref.key, 'key', 'plan')
            .having((ref) => ref.path, 'path', isEmpty),
      );
      expect(
        actionArgRef,
        isA<StateFlowOutboundRef>()
            .having((ref) => ref.key, 'key', 'diet')
            .having((ref) => ref.path, 'path', isEmpty),
      );
      expect(
        customEventRef,
        isA<EventFlowOutboundRef>()
            .having((ref) => ref.key, 'key', 'properties')
            .having((ref) => ref.path, 'path', ['campaign']),
      );
      expect(encoded['flowState'], _flowStateJson());
      expect(encoded['outbound'], _outboundJson());
    });

    test('state declarations alone keep outbound payloads denied by default',
        () {
      final document = _firstRunDocument(flowState: _flowStateDeclarations());
      final encoded = jsonDecode(
        utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document)),
      ) as Map<String, Object?>;

      expect(document.flowState, isNotEmpty);
      expect(document.outbound.isEmpty, isTrue);
      expect(encoded.containsKey('flowState'), isTrue);
      expect(encoded.containsKey('outbound'), isFalse);
    });

    test('outbound state refs require declared flow state keys', () {
      final document = _firstRunDocument(
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'selectedPlan': FlowOutboundField(
                type: FlowDataType.string,
                ref: StateFlowOutboundRef(key: 'missing', path: ['value']),
              ),
            },
          ),
        ),
      );

      expect(
        FlowDocumentValidation.validate(document),
        _containsIssueCode('missingFlowStateDeclaration'),
      );
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(document),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('legacy terminal passthrough cannot carry outbound declarations', () {
      final document = _firstRunDocument(
        flowState: _flowStateDeclarations(),
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'selectedPlan': FlowOutboundField(
                type: FlowDataType.string,
                ref: StateFlowOutboundRef(key: 'plan'),
              ),
            },
          ),
        ),
        legacyTerminalResultPassthrough: true,
      );

      expect(
        FlowDocumentValidation.validate(document),
        _containsIssueCode('invalidLegacyTerminalResultPassthrough'),
      );
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(document),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('outbound state ref type must match declared flow state type', () {
      final document = _firstRunDocument(
        flowState: _flowStateDeclarations(),
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'selectedPlan': FlowOutboundField(
                type: FlowDataType.bool,
                ref: StateFlowOutboundRef(key: 'plan'),
              ),
            },
          ),
        ),
      );

      expect(
        FlowDocumentValidation.validate(document),
        _containsIssueCode('outboundTypeMismatch'),
      );
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(document),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('outbound validation diagnostics identify surface and field', () {
      final document = _firstRunDocument(
        outbound: const FlowOutboundDeclarations(
          actionArgs: {
            'submitSurvey': FlowOutboundPayloadDeclaration(
              fields: {
                'responses..diet': FlowOutboundField(
                  type: FlowDataType.string,
                  ref: EventFlowOutboundRef(key: 'args'),
                ),
              },
            ),
          },
          customEvents: {
            'analyticsTap': FlowOutboundPayloadDeclaration(
              fields: {
                'campaign': FlowOutboundField(
                  type: FlowDataType.string,
                  ref: EventFlowOutboundRef(
                    key: 'properties',
                    path: [''],
                  ),
                ),
              },
            ),
          },
        ),
      );

      final issues = FlowDocumentValidation.validate(document);

      expect(
        issues,
        _containsIssue(
          code: 'invalidIdentifier',
          path: r'$.outbound.actionArgs.submitSurvey.responses..diet',
        ),
      );
      expect(
        issues,
        _containsIssue(
          code: 'invalidIdentifier',
          path: r'$.outbound.customEvents.analyticsTap.fields'
              '.campaign.ref.path[0]',
        ),
      );
    });

    test('malformed outbound refs fail validation', () {
      final document = _firstRunDocument(
        flowState: _flowStateDeclarations(),
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'selectedPlan': FlowOutboundField(
                type: FlowDataType.string,
                ref: StateFlowOutboundRef(key: '*'),
              ),
              'invalidEvent': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'properties', path: ['']),
              ),
            },
          ),
        ),
      );
      final issues = FlowDocumentValidation.validate(document);

      expect(issues, _containsIssueCode('invalidIdentifier'));
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(document),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('invalid flow state declaration types fail closed at decode time', () {
      final nonObjectDeclaration = _firstRunJson()
        ..['flowState'] = {
          'email': 'persistedAccount',
        };
      final nonStringClassification = _firstRunJson()
        ..['flowState'] = {
          'email': {'classification': 7},
        };

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(nonObjectDeclaration)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(nonStringClassification)),
        throwsA(isA<FormatException>()),
      );
    });

    test('explicit null flow state defaults fail closed at decode time', () {
      final json = _firstRunJson()
        ..['flowState'] = {
          'plan': {
            'type': 'string',
            'classification': 'screen',
            'default': null,
          },
        };

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(isA<FormatException>()),
      );
    });

    test('invalid flow state classifications fail closed at decode time', () {
      final json = _firstRunJson()
        ..['flowState'] = {
          'email': {'type': 'string', 'classification': 'secret'},
        };

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported flow state classification "secret"'),
          ),
        ),
      );
    });

    test('unknown outbound surfaces fail closed at decode time', () {
      final json = _firstRunJson()
        ..['outbound'] = {
          'globalEvents': {'refs': <Object?>[]},
        };

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported outbound surface "globalEvents"'),
          ),
        ),
      );
    });

    test('invalid outbound declaration types fail closed at decode time', () {
      final nonListRefs = _firstRunJson()
        ..['outbound'] = {
          'terminalResult': {'fields': 'state.plan.value'},
        };
      final nonStringPathSegment = _firstRunJson()
        ..['outbound'] = {
          'terminalResult': {
            'fields': {
              'selectedPlan': {
                'type': 'string',
                'ref': {
                  'state': 'plan',
                  'path': ['selected', 1],
                },
              },
            },
          },
        };

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(nonListRefs)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(nonStringPathSegment)),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown action descriptor fields fail closed at decode time', () {
      final json = _firstRunJsonWithAction();
      _object(_object(json['actions'])['requestNotifications'])['effect'] =
          'permission';

      _expectUnsupportedFieldDecodeFailure(
        json,
        r'$.actions.requestNotifications.effect',
      );
    });

    test('unknown action transition fields fail closed at decode time', () {
      final json = _firstRunJsonWithAction();
      final states = _object(json['states']);
      final welcome = _object(states['welcome']);
      final on = _object(welcome['on']);
      _object(on['next'])['retry'] = true;

      _expectUnsupportedFieldDecodeFailure(
        json,
        r'$.states.welcome.on.next.retry',
      );
    });

    test('unknown action result predicate shape fails closed at decode time',
        () {
      final json = _firstRunJsonWithAction();
      final states = _object(json['states']);
      final welcome = _object(states['welcome']);
      final on = _object(welcome['on']);
      final predicate = _object(_object(on['next'])['resultPredicate']);
      predicate['source'] = 'result == true';

      _expectUnsupportedFieldDecodeFailure(
        json,
        r'$.states.welcome.on.next.resultPredicate.source',
      );

      predicate.remove('source');
      predicate['kind'] = 'custom';

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported action result predicate kind "custom"'),
          ),
        ),
      );
    });

    test('action transition referencing an absent action fails closed', () {
      final json = _firstRunJsonWithAction();
      final states = _object(json['states']);
      final welcome = _object(states['welcome']);
      final on = _object(welcome['on']);
      _object(on['next'])['action'] = 'missingAction';

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('missingAction'),
          ),
        ),
      );
    });

    test('action contract name must match its table key when decoding', () {
      final json = _firstRunJsonWithAction();
      _object(_object(json['actions'])['requestNotifications'])['actionName'] =
          'requestNotificationsAlias';

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('actionNameMismatch'),
          ),
        ),
      );
    });

    test('duplicate action names fail validation', () {
      final document = _firstRunDocument(
        actions: {
          'requestNotifications': const FlowActionContract(
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _emptyArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
          ),
          'requestNotificationsAlias': const FlowActionContract(
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _emptyArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
          ),
        },
      );

      expect(
        FlowDocumentValidation.validate(document),
        _containsIssueCode('duplicateActionName'),
      );
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(document),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('malformed action hashes fail closed at decode time', () {
      final json = _firstRunJsonWithAction();
      _object(_object(json['actions'])['requestNotifications'])[
          'argsSchemaHash'] = _uppercaseHexHash;

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(isA<FormatException>()),
      );
    });

    test('action schema hashes must match the schema AST', () {
      final json = _firstRunJsonWithAction();
      final action = _object(_object(json['actions'])['requestNotifications']);
      action['argsSchemaHash'] = FlowActionSchema.hashFor(
        contractKind: 'args',
        schema: const FlowActionSchema.string(),
      ).value;

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('argsSchemaHash'),
              contains('argsSchema'),
            ),
          ),
        ),
      );
    });

    test('decision state decodes as a supported graph state', () {
      final json = jsonDecode(_firstRunCanonicalJson) as Map<String, Object?>;
      final states = json['states']! as Map<String, Object?>;
      final welcome = Map<String, Object?>.from(
        states['welcome']! as Map<String, Object?>,
      )
        ..['kind'] = 'decision'
        ..remove('screen')
        ..remove('on')
        ..['branches'] = [
          {
            'when': {
              'completed': {
                'eq': {'literal': true, 'type': 'bool'},
              },
            },
            'goto': 'done',
          },
        ]
        ..['default'] = {'goto': 'permissions'};
      json['states'] = {...states, 'welcome': welcome};

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));
      final state = decoded.states['welcome']!;
      final issues = FlowDocumentValidation.validate(decoded);

      expect(state, isNot(isA<UnsupportedFlowState>()));
      expect(state.kind.wireName, 'decision');
      expect(issues, isNot(_containsIssueCode('unsupportedStateKind')));
    });

    test('subFlow state decodes as a supported graph state', () {
      final json = jsonDecode(_firstRunCanonicalJson) as Map<String, Object?>;
      json['flowState'] = {
        ..._object(json['flowState']),
        'locale': {
          'type': 'string',
          'classification': 'screen',
        },
      };
      final states = json['states']! as Map<String, Object?>;
      final welcome = Map<String, Object?>.from(
        states['welcome']! as Map<String, Object?>,
      )
        ..['kind'] = 'subFlow'
        ..remove('screen')
        ..remove('on')
        ..['flow'] = 'profile'
        ..['version'] = 2
        ..['schemaVersion'] = 1
        ..['minClient'] = 3
        ..['contentHash'] = _artifactHash
        ..['input'] = {
          'locale': {
            'ref': {'state': 'locale'},
          },
        }
        ..['onComplete'] = [
          {
            'when': {
              'completed': {
                'eq': {'literal': true, 'type': 'bool'},
              },
            },
            'goto': 'done',
          },
        ]
        ..['default'] = {'goto': 'permissions'}
        ..['subFlowUnavailable'] = {'goto': 'done'};
      json['states'] = {...states, 'welcome': welcome};

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));
      final state = decoded.states['welcome']!;
      final issues = FlowDocumentValidation.validate(decoded);

      expect(state, isNot(isA<UnsupportedFlowState>()));
      expect(state.kind.wireName, 'subFlow');
      expect(issues, isNot(_containsIssueCode('unsupportedStateKind')));
    });

    test('malformed branch predicate grammar fails closed at decode time', () {
      final json = _firstRunJson();
      final states = _object(json['states']);
      final welcome = _object(states['welcome'])
        ..['kind'] = 'decision'
        ..remove('screen')
        ..remove('on')
        ..['branches'] = [
          {
            'when': {
              'completed': {'expr': 'state.completed == true'},
            },
            'goto': 'done',
          },
        ]
        ..['default'] = {'goto': 'permissions'};

      states['welcome'] = welcome;

      _expectUnsupportedFieldDecodeFailure(
        json,
        r'$.states.welcome.branches[0].when.completed.expr',
      );
    });

    test('malformed structured value sources fail closed at decode time', () {
      final json = _firstRunJson();
      final states = _object(json['states']);
      final welcome = _object(states['welcome'])
        ..['kind'] = 'subFlow'
        ..remove('screen')
        ..remove('on')
        ..['flow'] = 'profile'
        ..['version'] = 2
        ..['schemaVersion'] = 1
        ..['minClient'] = 3
        ..['contentHash'] = _artifactHash
        ..['input'] = {
          'locale': {
            'ref': {'state': 'locale'},
            'literal': 'en-US',
          },
        }
        ..['onComplete'] = <Object?>[]
        ..['default'] = {'goto': 'permissions'};

      states['welcome'] = welcome;

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(
              r'$.states.welcome.input.locale',
            ),
          ),
        ),
      );
    });

    test('unknown kind decodes to an unsupported state validation failure', () {
      final json = jsonDecode(_firstRunCanonicalJson) as Map<String, Object?>;
      final states = json['states']! as Map<String, Object?>;
      final welcome = Map<String, Object?>.from(
        states['welcome']! as Map<String, Object?>,
      )
        ..['kind'] = 'futureNode'
        ..['predicate'] = true;
      json['states'] = {...states, 'welcome': welcome};

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));
      final state = decoded.states['welcome']!;
      final issues = FlowDocumentValidation.validate(decoded);

      expect(state, isA<UnsupportedFlowState>());
      expect(() => state.kind, throwsA(isA<UnsupportedError>()));
      expect(issues, _containsIssueCode('unsupportedStateKind'));
    });

    test('null is rejected unless the field schema declares it nullable', () {
      final json = jsonDecode(_firstRunCanonicalJson) as Map<String, Object?>;
      json['flow'] = null;

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsA(isA<FormatException>()),
      );
    });

    test('nested result null fails validation and canonical encoding', () {
      const withNestedNull = FlowDocument(
        flow: 'first_run',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        initial: 'done',
        screenArtifacts: {},
        states: {
          'done': EndFlowState(result: {'completed': null}),
        },
      );

      expect(
        FlowDocumentValidation.validate(withNestedNull),
        _containsIssueCode('invalidJsonValue'),
      );
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(withNestedNull),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('non-finite numbers and doubles in Phase 1 documents are rejected',
        () {
      const withDouble = FlowDocument(
        flow: 'first_run',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        initial: 'done',
        screenArtifacts: {},
        states: {
          'done': EndFlowState(result: {'ratio': 1.5}),
        },
      );
      const withNonFinite = FlowDocument(
        flow: 'first_run',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        initial: 'done',
        screenArtifacts: {},
        states: {
          'done': EndFlowState(result: {'ratio': double.nan}),
        },
      );

      expect(
        FlowDocumentValidation.validate(withDouble),
        _containsIssueCode('invalidNumber'),
      );
      expect(
        FlowDocumentValidation.validate(withNonFinite),
        _containsIssueCode('invalidNumber'),
      );
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(withDouble),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => FlowDocumentCodec.encodeCanonicalJson(withNonFinite),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
        'non-ASCII generated ids, state ids, event ids, and artifact paths '
        'are rejected', () {
      expect(
        FlowDocumentValidation.validate(
          _firstRunDocument(flow: 'first_run_\u00e9'),
        ),
        _containsIssueCode('invalidIdentifier'),
      );
      expect(
        FlowDocumentValidation.validate(
          _firstRunDocument(initial: 'welc\u00f3me'),
        ),
        _containsIssueCode('invalidIdentifier'),
      );
      expect(
        FlowDocumentValidation.validate(
          _firstRunDocument(stateId: 'welc\u00f3me'),
        ),
        _containsIssueCode('invalidIdentifier'),
      );
      expect(
        FlowDocumentValidation.validate(
          _firstRunDocument(eventId: 'n\u00e9xt'),
        ),
        _containsIssueCode('invalidIdentifier'),
      );
      expect(
        FlowDocumentValidation.validate(
          _firstRunDocument(artifactPath: 'welc\u00f3me.rfw'),
        ),
        _containsIssueCode('invalidPath'),
      );
    });

    test('unsupported feature flags fail validation', () {
      final json = jsonDecode(_firstRunCanonicalJson) as Map<String, Object?>;
      json['features'] = ['decisions'];

      final decoded = FlowDocumentCodec.decodeJson(jsonEncode(json));
      final issues = FlowDocumentValidation.validate(decoded);

      expect(issues, _containsIssueCode('unsupportedFeature'));
    });

    test('validation rejects broken Phase 1 graph invariants', () {
      final missingInitial = _firstRunDocument(initial: 'missing');
      final missingScreen = _firstRunDocument(screen: 'missing');
      final missingTarget = _firstRunDocument(target: 'missing');
      const missingEnd = FlowDocument(
        flow: 'first_run',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        initial: 'welcome',
        screenArtifacts: {},
        states: {
          'welcome': ScreenFlowState(screen: 'welcome', on: {}),
        },
      );
      final unreachable = _firstRunDocument(
        extraStates: {
          'orphan': const EndFlowState(result: {'completed': false}),
        },
      );

      expect(
        FlowDocumentValidation.validate(missingInitial),
        _containsIssueCode('missingInitialState'),
      );
      expect(
        FlowDocumentValidation.validate(missingScreen),
        _containsIssueCode('missingScreenArtifact'),
      );
      expect(
        FlowDocumentValidation.validate(missingTarget),
        _containsIssueCode('missingTransitionTarget'),
      );
      expect(
        FlowDocumentValidation.validate(missingEnd),
        _containsIssueCode('missingEndState'),
      );
      expect(
        FlowDocumentValidation.validate(unreachable),
        _containsIssueCode('unreachableState'),
      );
    });
  });

  group('FlowContentHash', () {
    test('accepts only sha256 hashes with 64 lowercase hex chars', () {
      expect(
        FlowContentHash.parse(
          _zeroHash,
        ).value,
        _zeroHash,
      );

      expect(
        () => FlowContentHash.parse(
          _uppercaseHash,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => FlowContentHash.parse(
          _uppercaseHexHash,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('computes hashes over exact bytes and reports path diagnostics', () {
      final actual = FlowContentHash.compute(utf8.encode('artifact'));
      final expected = FlowContentHash.parse(
        _zeroHash,
      );

      expect(
        actual,
        FlowContentHash.parse(
          _artifactHash,
        ),
      );
      expect(
        expected.diagnosticForMismatch(path: 'welcome.rfw', actual: actual),
        contains('welcome.rfw'),
      );
      expect(
        expected.diagnosticForMismatch(path: 'welcome.rfw', actual: actual),
        contains(
          'expected $_zeroHash',
        ),
      );
      expect(
        expected.diagnosticForMismatch(path: 'welcome.rfw', actual: actual),
        contains(
          'actual $_artifactHash',
        ),
      );
    });
  });
}

Matcher _containsIssueCode(String code) {
  return contains(
    isA<FlowDocumentValidationIssue>().having(
      (issue) => issue.code,
      'code',
      code,
    ),
  );
}

Matcher _containsIssue({
  required String code,
  required String path,
}) {
  return contains(
    isA<FlowDocumentValidationIssue>()
        .having(
          (issue) => issue.code,
          'code',
          code,
        )
        .having(
          (issue) => issue.path,
          'path',
          path,
        ),
  );
}

Map<String, Object?> _firstRunJson() {
  return jsonDecode(_firstRunCanonicalJson) as Map<String, Object?>;
}

Map<String, Object?> _object(Object? value) {
  return value! as Map<String, Object?>;
}

String _readGolden(String fileName) {
  final workspacePath = File(
    'packages/restage_shared/test/flow_document/goldens/$fileName',
  );
  if (workspacePath.existsSync()) {
    return workspacePath.readAsStringSync();
  }
  return File('test/flow_document/goldens/$fileName').readAsStringSync();
}

void _expectUnsupportedFieldDecodeFailure(
  Map<String, Object?> json,
  String path,
) {
  expect(
    () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
    throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('Unsupported field'),
          contains(path),
        ),
      ),
    ),
  );
}

FlowDocument _firstRunDocument({
  String flow = 'first_run',
  String initial = 'welcome',
  String stateId = 'welcome',
  String eventId = 'next',
  String artifactPath = 'welcome.rfw',
  String screen = 'welcome',
  String target = 'permissions',
  FlowTransition? transition,
  Map<String, FlowActionContract>? actions,
  Map<String, FlowStateDeclaration> flowState = const {},
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  bool legacyTerminalResultPassthrough = false,
  Map<String, FlowState> extraStates = const {},
}) {
  final actionContracts = actions ??
      const {
        'requestNotifications': FlowActionContract(
          actionName: 'requestNotifications',
          contractVersion: 1,
          argsSchema: _emptyArgsSchema,
          resultSchema: _notificationResultSchema,
          minClient: 3,
          idempotent: false,
        ),
      };
  final generatedProofAction = actions == null;
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: initial,
    actions: actionContracts,
    flowState: flowState,
    outbound: outbound,
    legacyTerminalResultPassthrough: legacyTerminalResultPassthrough,
    screenArtifacts: {
      'permissions': ScreenArtifact(
        path: 'permissions.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.parse(
          _permissionsHash,
        ),
      ),
      'ready': ScreenArtifact(
        path: 'ready.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.parse(
          _readyHash,
        ),
      ),
      'welcome': ScreenArtifact(
        path: artifactPath,
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.parse(
          _welcomeHash,
        ),
      ),
    },
    states: {
      stateId: ScreenFlowState(
        screen: screen,
        on: {
          eventId: transition ?? FlowTransition.goto(target),
        },
      ),
      'permissions': ScreenFlowState(
        screen: 'permissions',
        on: {
          'next': generatedProofAction
              ? const ActionFlowTransition(
                  action: 'requestNotifications',
                  target: 'ready',
                  resultPredicate: ObjectBoolFieldEqualsActionResultPredicate(
                    field: 'granted',
                    value: true,
                  ),
                )
              : const FlowTransition.goto('ready'),
        },
      ),
      'ready': const ScreenFlowState(
        screen: 'ready',
        on: {
          'start': FlowTransition.goto('done'),
        },
      ),
      'done': const EndFlowState(
        result: {'completed': true},
      ),
      ...extraStates,
    },
  );
}

Map<String, Object?> _firstRunJsonWithAction() {
  final json = _firstRunJson();
  json['actions'] = {
    'requestNotifications': {
      'actionName': 'requestNotifications',
      'contractVersion': 1,
      'argsSchema': {
        'kind': 'object',
        'fields': <String, Object?>{},
      },
      'argsSchemaHash': _emptyObjectArgsHash,
      'resultSchema': {'kind': 'bool'},
      'resultSchemaHash': _boolResultHash,
      'minClient': 3,
      'idempotent': false,
    },
  };
  final states = _object(json['states']);
  final welcome = _object(states['welcome']);
  final on = _object(welcome['on']);
  on['next'] = <String, Object?>{
    'type': 'action',
    'action': 'requestNotifications',
    'resultPredicate': {
      'kind': 'boolEquals',
      'value': true,
    },
    'target': 'permissions',
  };
  return json;
}

const _generatedProofFlowState = {
  'completed': FlowStateDeclaration(
    type: FlowDataType.bool,
    classification: FlowStateClassification.exportable,
  ),
  'secret': FlowStateDeclaration(
    type: FlowDataType.string,
    classification: FlowStateClassification.internal,
  ),
};

const _generatedProofOutbound = FlowOutboundDeclarations(
  terminalResult: FlowOutboundPayloadDeclaration(
    fields: {
      'completed': FlowOutboundField(
        type: FlowDataType.bool,
        ref: StateFlowOutboundRef(key: 'completed'),
      ),
    },
  ),
  customEvents: {
    'analyticsTap': FlowOutboundPayloadDeclaration(
      fields: {
        'ctaId': FlowOutboundField(
          type: FlowDataType.string,
          ref: EventFlowOutboundRef(key: 'ctaId'),
        ),
      },
    ),
  },
);

FlowDocument _generatedProofDocument() {
  return _firstRunDocument(
    flowState: _generatedProofFlowState,
    outbound: _generatedProofOutbound,
    extraStates: const {
      'done': EndFlowState(
        result: {'completed': true, 'secret': 'internal'},
      ),
    },
  );
}

FlowDocument _generatedProofDocumentWithReorderedMaps() {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    actions: {
      'requestNotifications': const FlowActionContract(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: _emptyArgsSchema,
        resultSchema: _notificationResultSchema,
        minClient: 3,
        idempotent: false,
      ),
    },
    flowState: _generatedProofFlowState,
    outbound: _generatedProofOutbound,
    screenArtifacts: {
      'ready': ScreenArtifact(
        minClient: 1,
        schemaVersion: 1,
        version: 1,
        path: 'ready.rfw',
        contentHash: FlowContentHash.parse(
          _readyHash,
        ),
      ),
      'welcome': ScreenArtifact(
        minClient: 1,
        schemaVersion: 1,
        version: 1,
        path: 'welcome.rfw',
        contentHash: FlowContentHash.parse(
          _welcomeHash,
        ),
      ),
      'permissions': ScreenArtifact(
        minClient: 1,
        schemaVersion: 1,
        version: 1,
        path: 'permissions.rfw',
        contentHash: FlowContentHash.parse(
          _permissionsHash,
        ),
      ),
    },
    states: {
      'done': const EndFlowState(
        result: {'completed': true, 'secret': 'internal'},
      ),
      'ready': const ScreenFlowState(
        on: {
          'start': FlowTransition.goto('done'),
        },
        screen: 'ready',
      ),
      'welcome': const ScreenFlowState(
        on: {
          'next': FlowTransition.goto('permissions'),
        },
        screen: 'welcome',
      ),
      'permissions': const ScreenFlowState(
        on: {
          'next': ActionFlowTransition(
            action: 'requestNotifications',
            target: 'ready',
            resultPredicate: ObjectBoolFieldEqualsActionResultPredicate(
              field: 'granted',
              value: true,
            ),
          ),
        },
        screen: 'permissions',
      ),
    },
  );
}

Map<String, FlowStateDeclaration> _flowStateDeclarations() {
  return const {
    'diet': FlowStateDeclaration(
      type: FlowDataType.string,
      classification: FlowStateClassification.screen,
    ),
    'email': FlowStateDeclaration(
      type: FlowDataType.string,
      classification: FlowStateClassification.persistedAccount,
    ),
    'plan': FlowStateDeclaration(
      type: FlowDataType.string,
      classification: FlowStateClassification.exportable,
    ),
  };
}

Map<String, Object?> _flowStateJson() {
  return {
    'diet': {
      'type': 'string',
      'classification': 'screen',
    },
    'email': {
      'type': 'string',
      'classification': 'persistedAccount',
    },
    'plan': {
      'type': 'string',
      'classification': 'exportable',
    },
  };
}

Map<String, Object?> _outboundJson() {
  return {
    'actionArgs': {
      'submitSurvey': {
        'diet': {
          'type': 'string',
          'ref': {'state': 'diet'},
        },
      },
    },
    'customEvents': {
      'analyticsTap': {
        'fields': {
          'campaign': {
            'type': 'string',
            'ref': {
              'event': 'properties',
              'path': ['campaign'],
            },
          },
        },
      },
    },
    'terminalResult': {
      'fields': {
        'selectedPlan': {
          'type': 'string',
          'ref': {'state': 'plan'},
        },
      },
    },
  };
}

const _firstRunCanonicalJson =
    '{"actions":{"requestNotifications":{"actionName":"requestNotifications",'
    '"argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":'
    '"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a",'
    '"contractVersion":1,"idempotent":false,"minClient":3,'
    '"resultSchema":{"fields":{"granted":{"required":true,"schema":'
    '{"kind":"bool"}}},"kind":"object"},"resultSchemaHash":'
    '"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea'
    '2b8428ece4ec"}},'
    '"flow":"first_run","flowState":{"completed":{"classification":'
    '"exportable","type":"bool"},"secret":{"classification":"internal",'
    '"type":"string"}},"initial":"welcome","minClient":3,'
    '"outbound":{"customEvents":{"analyticsTap":{"fields":{"ctaId":{"ref":'
    '{"event":"ctaId"},"type":"string"}}}},"terminalResult":{"fields":'
    '{"completed":{"ref":{"state":"completed"},"type":"bool"}}}},'
    '"schemaVersion":1,"screenArtifacts":{"permissions":{"contentHash":'
    '"sha256:2fdf394099fc1b2726364d3c711bc67e4c6e3a6815e954f8ba40e5f6abff5f20",'
    '"minClient":1,"path":"permissions.rfw","schemaVersion":1,"version":1},'
    '"ready":{"contentHash":'
    '"sha256:3ddf726bd14672398d634f5f551d6774438f2a6b6f64c2337170405daebd1bd5",'
    '"minClient":1,"path":"ready.rfw","schemaVersion":1,"version":1},'
    '"welcome":{"contentHash":'
    '"sha256:173eb2f2fc701497bf99849f061570b609fc54ad654a77349083396be458d53b",'
    '"minClient":1,"path":"welcome.rfw","schemaVersion":1,"version":1}},'
    '"states":{"done":{"kind":"end","result":{"completed":true,'
    '"secret":"internal"}},'
    '"permissions":{"kind":"screen","on":{"next":{"action":'
    '"requestNotifications","resultPredicate":{"field":"granted","kind":'
    '"objectBoolFieldEquals","value":true},"target":"ready","type":"action"}},'
    '"screen":"permissions"},'
    '"ready":{"kind":"screen","on":{"start":{"target":"done","type":"goto"}},'
    '"screen":"ready"},'
    '"welcome":{"kind":"screen","on":{"next":{"target":"permissions",'
    '"type":"goto"}},'
    '"screen":"welcome"}},"version":1}';

const _phase1CanonicalJson =
    '{"flow":"first_run","initial":"welcome","minClient":3,'
    '"schemaVersion":1,"screenArtifacts":{"permissions":{"contentHash":'
    '"sha256:bc1f0432a3bec4a0440ace17c9b42b321cb174f405b2536b79646397f744d6b7",'
    '"minClient":3,"path":"permissions.rfw","schemaVersion":1,"version":1},'
    '"ready":{"contentHash":'
    '"sha256:1f8bcc406c7da0cb21cbac2aee000d72ff4fa741b23eb86f23f4d184c1ba2c9e",'
    '"minClient":3,"path":"ready.rfw","schemaVersion":1,"version":1},'
    '"welcome":{"contentHash":'
    '"sha256:4ebc58c93909d06721196c9864b3f758dbddce6f212673f39f374d55497460e0",'
    '"minClient":3,"path":"welcome.rfw","schemaVersion":1,"version":1}},'
    '"states":{"done":{"kind":"end","result":{"completed":true}},'
    '"permissions":{"kind":"screen","on":{"next":{"target":"ready",'
    '"type":"goto"}},"screen":"permissions"},'
    '"ready":{"kind":"screen","on":{"start":{"target":"done","type":"goto"}},'
    '"screen":"ready"},'
    '"welcome":{"kind":"screen","on":{"next":{"target":"permissions",'
    '"type":"goto"}},'
    '"screen":"welcome"}},"version":1}';

const _firstRunCanonicalHash = 'sha256:0a7e959d9a64e1ef0bfa6fef29e0ad992a80'
    '483f3f7b836ece9586a88819b15d';
const _zeroHash = 'sha256:00000000000000000000000000000000'
    '00000000000000000000000000000000';
const _permissionsHash = 'sha256:2fdf394099fc1b2726364d3c711bc67e'
    '4c6e3a6815e954f8ba40e5f6abff5f20';
const _readyHash = 'sha256:3ddf726bd14672398d634f5f551d6774'
    '438f2a6b6f64c2337170405daebd1bd5';
const _welcomeHash = 'sha256:173eb2f2fc701497bf99849f061570b6'
    '09fc54ad654a77349083396be458d53b';
const _emptyArgsSchema = FlowActionSchema.object({});
const _boolResultSchema = FlowActionSchema.bool();
const _notificationResultSchema = FlowActionSchema.object({
  'granted': FlowActionSchemaField(
    required: true,
    schema: FlowActionSchema.bool(),
  ),
});
const _emptyObjectArgsHash = 'sha256:590f015bf5e877b53e3501b7e12ad48'
    'a11158d4c5b696f9a82593c4f3272411a';
const _boolResultHash = 'sha256:b381695502a4099cf3610d182b471a25'
    '62086e5e8bdb11f4426f63ba512542b3';
const _notificationResultHash = 'sha256:ef1c091bc0c82e02a9c18695d6ececb'
    'd01dee150396df8bea8ea2b8428ece4ec';
const _uppercaseHash = 'SHA256:00000000000000000000000000000000'
    '00000000000000000000000000000000';
const _uppercaseHexHash = 'sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _artifactHash = 'sha256:c7c5c1d70c5dec4416ab6158afd0b223'
    'ef40c29b1dc1f97ed9428b94d4cadb1c';
