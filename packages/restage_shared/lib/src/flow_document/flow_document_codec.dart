import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/src/flow_document/flow_action_schema.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_hash.dart';
import 'package:restage_shared/src/flow_document/flow_document_validation.dart';

/// JSON codec for flow documents.
abstract final class FlowDocumentCodec {
  /// Decodes a flow document from JSON.
  static FlowDocument decodeJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('FlowDocument JSON must be an object.');
    }
    return _decodeDocument(decoded);
  }

  /// Encodes deterministic, indented JSON for review and fixtures.
  static String encodePrettyJson(FlowDocument document) {
    FlowDocumentValidation.checkValid(document);
    final pretty = const JsonEncoder.withIndent(
      '  ',
    ).convert(_sortJsonValue(_encodeDocument(document)));
    return '$pretty\n';
  }

  /// Encodes canonical JSON bytes with recursively sorted object keys.
  static List<int> encodeCanonicalJson(FlowDocument document) {
    FlowDocumentValidation.checkValid(document);
    final canonical = jsonEncode(_sortJsonValue(_encodeDocument(document)));
    return utf8.encode(canonical);
  }

  /// Returns the SHA-256 hash of the canonical JSON bytes.
  static String canonicalJsonSha256(FlowDocument document) {
    final digest = crypto.sha256.convert(encodeCanonicalJson(document));
    return 'sha256:$digest';
  }
}

FlowDocument _decodeDocument(Map<String, Object?> json) {
  _rejectUnknownKeys(
    json,
    const {
      'actions',
      'features',
      'flow',
      'flowState',
      'initial',
      'minClient',
      'outbound',
      'schemaVersion',
      'screenArtifacts',
      'states',
      'version',
    },
    r'$',
  );

  final unsupportedFeatures = <String>{};
  final features = json['features'];
  if (features != null) {
    if (features is! List<Object?>) {
      throw const FormatException('FlowDocument features must be a list.');
    }
    for (final feature in features) {
      if (feature is! String) {
        throw const FormatException('FlowDocument features must be strings.');
      }
      unsupportedFeatures.add(feature);
    }
  }

  final hasFlowState = json.containsKey('flowState');
  final hasOutbound = json.containsKey('outbound');
  final document = FlowDocument(
    flow: _requiredString(json, 'flow'),
    version: _requiredInt(json, 'version'),
    schemaVersion: _requiredInt(json, 'schemaVersion'),
    minClient: _requiredInt(json, 'minClient'),
    initial: _requiredString(json, 'initial'),
    actions: _decodeActions(_optionalObject(json, 'actions'), r'$.actions'),
    flowState: _decodeFlowState(
      _optionalObject(json, 'flowState'),
      r'$.flowState',
    ),
    outbound: _decodeOutbound(
      _optionalObject(json, 'outbound'),
      r'$.outbound',
    ),
    legacyTerminalResultPassthrough: !hasFlowState && !hasOutbound,
    screenArtifacts: _decodeArtifacts(
      _requiredObject(json, 'screenArtifacts'),
      r'$.screenArtifacts',
    ),
    states: _decodeStates(_requiredObject(json, 'states'), r'$.states'),
    unsupportedFeatures: unsupportedFeatures,
  );
  _checkDecodedActionInvariants(document);
  return document;
}

Map<String, FlowStateDeclaration> _decodeFlowState(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) return const {};
  return {
    for (final entry in json.entries)
      entry.key: _decodeFlowStateDeclaration(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

FlowStateDeclaration _decodeFlowStateDeclaration(
  Map<String, Object?> json,
  String path,
) {
  _rejectUnknownKeys(
    json,
    const {'classification', 'default', 'type'},
    path,
  );
  if (json.containsKey('default') && json['default'] == null) {
    throw FormatException('Field "$path.default" cannot be null.');
  }
  return FlowStateDeclaration(
    type: _decodeFlowDataType(_requiredString(json, 'type'), path),
    classification: _decodeFlowStateClassification(
      _requiredString(json, 'classification'),
      path,
    ),
    defaultValue: json['default'],
  );
}

FlowDataType _decodeFlowDataType(String value, String path) {
  for (final type in FlowDataType.values) {
    if (type.wireName == value) return type;
  }
  throw FormatException('Unsupported flow data type "$value" at $path.type.');
}

FlowStateClassification _decodeFlowStateClassification(
  String value,
  String path,
) {
  for (final classification in FlowStateClassification.values) {
    if (classification.wireName == value) return classification;
  }
  throw FormatException(
    'Unsupported flow state classification "$value" at '
    '$path.classification.',
  );
}

FlowOutboundDeclarations _decodeOutbound(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) return const FlowOutboundDeclarations();
  _rejectUnknownKeys(
    json,
    const {
      'actionArgs',
      'customEvents',
      'lifecycle',
      'subFlowResult',
      'surveyAnswers',
      'terminalResult',
    },
    path,
    unknownMessage: (key) => 'Unsupported outbound surface "$key".',
  );

  return FlowOutboundDeclarations(
    actionArgs: _decodeDirectOutboundPayloadMap(
      _optionalObject(json, 'actionArgs'),
      '$path.actionArgs',
    ),
    terminalResult: _decodeOutboundPayload(
      _optionalObject(json, 'terminalResult'),
      '$path.terminalResult',
    ),
    lifecycle: _decodeOutboundPayload(
      _optionalObject(json, 'lifecycle'),
      '$path.lifecycle',
    ),
    surveyAnswers: _decodeOutboundPayload(
      _optionalObject(json, 'surveyAnswers'),
      '$path.surveyAnswers',
    ),
    subFlowResult: _decodeOutboundPayload(
      _optionalObject(json, 'subFlowResult'),
      '$path.subFlowResult',
    ),
    customEvents: _decodeOutboundPayloadMap(
      _optionalObject(json, 'customEvents'),
      '$path.customEvents',
    ),
  );
}

Map<String, FlowOutboundPayloadDeclaration> _decodeDirectOutboundPayloadMap(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) return const {};
  return {
    for (final entry in json.entries)
      entry.key: FlowOutboundPayloadDeclaration(
        fields: _decodeOutboundFields(
          _asObject(entry.value, '$path.${entry.key}'),
          '$path.${entry.key}',
        ),
      ),
  };
}

Map<String, FlowOutboundPayloadDeclaration> _decodeOutboundPayloadMap(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) return const {};
  return {
    for (final entry in json.entries)
      entry.key: _decodeOutboundPayload(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

FlowOutboundPayloadDeclaration _decodeOutboundPayload(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) return const FlowOutboundPayloadDeclaration();
  _rejectUnknownKeys(json, const {'fields'}, path);
  final fields = _requiredObject(json, 'fields');
  return FlowOutboundPayloadDeclaration(
    fields: _decodeOutboundFields(fields, '$path.fields'),
  );
}

Map<String, FlowOutboundField> _decodeOutboundFields(
  Map<String, Object?> json,
  String path,
) {
  return {
    for (final entry in json.entries)
      entry.key: _decodeOutboundField(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

FlowOutboundField _decodeOutboundField(Map<String, Object?> json, String path) {
  _rejectUnknownKeys(json, const {'ref', 'type'}, path);
  return FlowOutboundField(
    type: _decodeFlowDataType(_requiredString(json, 'type'), path),
    ref: _decodeOutboundRef(_requiredObject(json, 'ref'), '$path.ref'),
  );
}

FlowOutboundRef _decodeOutboundRef(Map<String, Object?> json, String path) {
  _rejectUnknownKeys(json, const {'event', 'path', 'state'}, path);
  final hasEvent = json.containsKey('event');
  final hasState = json.containsKey('state');
  if (hasEvent == hasState) {
    throw FormatException(
      'Outbound ref "$path" must declare exactly one of event or state.',
    );
  }
  final refPath = _decodeStringList(json['path'], '$path.path');
  if (hasState) {
    return StateFlowOutboundRef(
      key: _requiredString(json, 'state'),
      path: refPath,
    );
  }
  return EventFlowOutboundRef(
    key: _requiredString(json, 'event'),
    path: refPath,
  );
}

List<String> _decodeStringList(Object? value, String path) {
  if (value == null) return const [];
  if (value is! List<Object?>) {
    throw FormatException('Expected "$path" to be a list.');
  }
  return [
    for (final item in value)
      if (item is String)
        item
      else
        throw FormatException('Expected "$path" items to be strings.'),
  ];
}

Map<String, FlowActionContract> _decodeActions(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) {
    return const {};
  }
  return {
    for (final entry in json.entries)
      entry.key: _decodeActionContract(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

FlowActionContract _decodeActionContract(
  Map<String, Object?> json,
  String path,
) {
  _rejectUnknownKeys(
    json,
    const {
      'actionName',
      'argsSchema',
      'argsSchemaHash',
      'contractVersion',
      'idempotent',
      'minClient',
      'resultSchema',
      'resultSchemaHash',
    },
    path,
  );

  final argsSchema = FlowActionSchema.fromJson(
    _requiredObject(json, 'argsSchema'),
    path: '$path.argsSchema',
  );
  final resultSchema = FlowActionSchema.fromJson(
    _requiredObject(json, 'resultSchema'),
    path: '$path.resultSchema',
  );
  _checkSchemaHash(
    path: path,
    field: 'argsSchemaHash',
    contractKind: 'args',
    schema: argsSchema,
    hash: FlowContentHash.parse(_requiredString(json, 'argsSchemaHash')),
  );
  _checkSchemaHash(
    path: path,
    field: 'resultSchemaHash',
    contractKind: 'result',
    schema: resultSchema,
    hash: FlowContentHash.parse(_requiredString(json, 'resultSchemaHash')),
  );

  return FlowActionContract(
    actionName: _requiredString(json, 'actionName'),
    contractVersion: _requiredInt(json, 'contractVersion'),
    argsSchema: argsSchema,
    resultSchema: resultSchema,
    minClient: _requiredInt(json, 'minClient'),
    idempotent: _requiredBool(json, 'idempotent'),
  );
}

void _checkSchemaHash({
  required String path,
  required String field,
  required String contractKind,
  required FlowActionSchema schema,
  required FlowContentHash hash,
}) {
  final derived = FlowActionSchema.hashFor(
    contractKind: contractKind,
    schema: schema,
  );
  if (hash == derived) return;
  final schemaField = field.replaceFirst('Hash', '');
  throw FormatException(
    'Field "$path.$field" does not match $path.$schemaField: '
    'expected ${derived.value}, got ${hash.value}.',
  );
}

Map<String, ScreenArtifact> _decodeArtifacts(
  Map<String, Object?> json,
  String path,
) {
  return {
    for (final entry in json.entries)
      entry.key: _decodeArtifact(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

ScreenArtifact _decodeArtifact(Map<String, Object?> json, String path) {
  _rejectUnknownKeys(
    json,
    const {
      'contentHash',
      'minClient',
      'path',
      'schemaVersion',
      'version',
    },
    path,
  );

  return ScreenArtifact(
    path: _requiredString(json, 'path'),
    version: _requiredInt(json, 'version'),
    schemaVersion: _requiredInt(json, 'schemaVersion'),
    minClient: _requiredInt(json, 'minClient'),
    contentHash: FlowContentHash.parse(_requiredString(json, 'contentHash')),
  );
}

Map<String, FlowState> _decodeStates(Map<String, Object?> json, String path) {
  return {
    for (final entry in json.entries)
      entry.key: _decodeState(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

FlowState _decodeState(Map<String, Object?> json, String path) {
  final kind = _requiredString(json, 'kind');
  switch (kind) {
    case 'screen':
      _rejectUnknownKeys(json, const {'kind', 'on', 'screen'}, path);
      return ScreenFlowState(
        screen: _requiredString(json, 'screen'),
        on: _decodeTransitions(_requiredObject(json, 'on'), '$path.on'),
      );
    case 'decision':
      _rejectUnknownKeys(json, const {'branches', 'default', 'kind'}, path);
      return DecisionFlowState(
        branches: _decodeBranches(
          _requiredList(json, 'branches'),
          '$path.branches',
        ),
        defaultBranch: _decodeBranchTarget(
          _requiredObject(json, 'default'),
          '$path.default',
        ),
      );
    case 'subFlow':
      _rejectUnknownKeys(
        json,
        const {
          'contentHash',
          'default',
          'flow',
          'input',
          'kind',
          'minClient',
          'onComplete',
          'schemaVersion',
          'subFlowUnavailable',
          'version',
        },
        path,
      );
      return SubFlowState(
        flow: _requiredString(json, 'flow'),
        version: _requiredInt(json, 'version'),
        schemaVersion: _requiredInt(json, 'schemaVersion'),
        minClient: _requiredInt(json, 'minClient'),
        contentHash:
            FlowContentHash.parse(_requiredString(json, 'contentHash')),
        input: _decodeValueSourceMap(
          _optionalObject(json, 'input'),
          '$path.input',
        ),
        onComplete: _decodeBranches(
          _requiredList(json, 'onComplete'),
          '$path.onComplete',
        ),
        defaultBranch: _decodeBranchTarget(
          _requiredObject(json, 'default'),
          '$path.default',
        ),
        subFlowUnavailable: json.containsKey('subFlowUnavailable')
            ? _decodeBranchTarget(
                _requiredObject(json, 'subFlowUnavailable'),
                '$path.subFlowUnavailable',
              )
            : null,
      );
    case 'end':
      _rejectUnknownKeys(json, const {'kind', 'result'}, path);
      return EndFlowState(
        result: _requiredObject(json, 'result'),
      );
    default:
      return UnsupportedFlowState(wireKind: kind, raw: Map.of(json));
  }
}

List<FlowBranch> _decodeBranches(List<Object?> json, String path) {
  return [
    for (var index = 0; index < json.length; index += 1)
      _decodeBranch(
        _asObject(json[index], '$path[$index]'),
        '$path[$index]',
      ),
  ];
}

FlowBranch _decodeBranch(Map<String, Object?> json, String path) {
  _rejectUnknownKeys(json, const {'goto', 'set', 'when'}, path);
  return FlowBranch(
    when: _decodeBranchPredicate(_requiredObject(json, 'when'), '$path.when'),
    target: _requiredString(json, 'goto'),
    stateWrites: _decodeStateWrites(_optionalObject(json, 'set'), '$path.set'),
  );
}

FlowBranchTarget _decodeBranchTarget(Map<String, Object?> json, String path) {
  _rejectUnknownKeys(json, const {'goto', 'set'}, path);
  return FlowBranchTarget(
    target: _requiredString(json, 'goto'),
    stateWrites: _decodeStateWrites(_optionalObject(json, 'set'), '$path.set'),
  );
}

FlowBranchPredicate _decodeBranchPredicate(
  Map<String, Object?> json,
  String path,
) {
  return FlowBranchPredicate(
    fields: {
      for (final entry in json.entries)
        entry.key: _decodePredicateCondition(
          _asObject(entry.value, '$path.${entry.key}'),
          '$path.${entry.key}',
        ),
    },
  );
}

FlowPredicateCondition _decodePredicateCondition(
  Map<String, Object?> json,
  String path,
) {
  const operators = {'eq', 'exists', 'gt', 'gte', 'in', 'lt', 'lte', 'ne'};
  _rejectUnknownKeys(json, operators, path);
  final presentOperators = json.keys.where(operators.contains).toList();
  if (presentOperators.length != 1) {
    throw FormatException(
      'Predicate condition "$path" must declare exactly one operator.',
    );
  }

  final operator = presentOperators.single;
  switch (operator) {
    case 'eq':
      return EqualsFlowPredicateCondition(
        value: _decodeValueSource(
          _required(json, operator),
          '$path.$operator',
        ),
      );
    case 'ne':
      return NotEqualsFlowPredicateCondition(
        value: _decodeValueSource(
          _required(json, operator),
          '$path.$operator',
        ),
      );
    case 'in':
      final values = _requiredList(json, operator);
      return InFlowPredicateCondition(
        values: [
          for (var index = 0; index < values.length; index += 1)
            _decodeValueSource(
              values[index],
              '$path.$operator[$index]',
            ),
        ],
      );
    case 'gt':
      return GreaterThanFlowPredicateCondition(
        value: _decodeValueSource(
          _required(json, operator),
          '$path.$operator',
        ),
      );
    case 'gte':
      return GreaterThanOrEqualsFlowPredicateCondition(
        value: _decodeValueSource(
          _required(json, operator),
          '$path.$operator',
        ),
      );
    case 'lt':
      return LessThanFlowPredicateCondition(
        value: _decodeValueSource(
          _required(json, operator),
          '$path.$operator',
        ),
      );
    case 'lte':
      return LessThanOrEqualsFlowPredicateCondition(
        value: _decodeValueSource(
          _required(json, operator),
          '$path.$operator',
        ),
      );
    case 'exists':
      return ExistsFlowPredicateCondition(
        exists: _requiredBool(json, operator),
      );
    default:
      throw StateError('Unhandled predicate operator "$operator".');
  }
}

Map<String, FlowStateWrite> _decodeStateWrites(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) return const {};
  return {
    for (final entry in json.entries)
      entry.key: _decodeStateWrite(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

FlowStateWrite _decodeStateWrite(Map<String, Object?> json, String path) {
  _rejectUnknownKeys(json, const {'type', 'value'}, path);
  return FlowStateWrite(
    type: _decodeFlowDataType(_requiredString(json, 'type'), path),
    value: _decodeValueSource(_required(json, 'value'), '$path.value'),
  );
}

Map<String, FlowValueSource> _decodeValueSourceMap(
  Map<String, Object?>? json,
  String path,
) {
  if (json == null) return const {};
  return {
    for (final entry in json.entries)
      entry.key: _decodeValueSource(entry.value, '$path.${entry.key}'),
  };
}

FlowValueSource _decodeValueSource(Object? value, String path) {
  final json = _asObject(value, path);
  _rejectUnknownKeys(json, const {'literal', 'ref', 'type'}, path);
  final hasLiteral = json.containsKey('literal');
  final hasRef = json.containsKey('ref');
  if (hasLiteral == hasRef) {
    throw FormatException(
      'Value source "$path" must declare exactly one of literal or ref.',
    );
  }
  if (hasLiteral) {
    final type = _decodeFlowDataType(_requiredString(json, 'type'), path);
    final literal = _decodeLiteral(
      _required(json, 'literal'),
      type,
      '$path.literal',
    );
    return LiteralFlowValueSource(type: type, value: literal);
  }
  if (json.containsKey('type')) {
    throw FormatException(
      'Value ref "$path" must not declare a literal type.',
    );
  }
  return _decodeValueRef(_requiredObject(json, 'ref'), '$path.ref');
}

Object _decodeLiteral(Object? value, FlowDataType type, String path) {
  switch (type) {
    case FlowDataType.bool:
      if (value is bool) return value;
    case FlowDataType.int:
      if (value is int) return value;
    case FlowDataType.string:
      if (value is String) return value;
  }
  if (value is double) {
    throw FormatException('Expected "$path" to be an integer, got double.');
  }
  throw FormatException(
    'Expected "$path" to match literal type ${type.wireName}.',
  );
}

FlowValueSource _decodeValueRef(Map<String, Object?> json, String path) {
  const refKeys = {'actionResult', 'event', 'path', 'state', 'subFlowResult'};
  _rejectUnknownKeys(json, refKeys, path);
  final presentRefs = [
    for (final key in const ['actionResult', 'event', 'state', 'subFlowResult'])
      if (json.containsKey(key)) key,
  ];
  if (presentRefs.length != 1) {
    throw FormatException(
      'Value ref "$path" must declare exactly one source key.',
    );
  }
  final refPath = _decodeStringList(json['path'], '$path.path');
  final key = presentRefs.single;
  switch (key) {
    case 'actionResult':
      return ActionResultFlowValueSource(
        key: _requiredString(json, key),
        path: refPath,
      );
    case 'event':
      return EventFlowValueSource(
        key: _requiredString(json, key),
        path: refPath,
      );
    case 'state':
      return StateFlowValueSource(
        key: _requiredString(json, key),
        path: refPath,
      );
    case 'subFlowResult':
      return SubFlowResultFlowValueSource(
        key: _requiredString(json, key),
        path: refPath,
      );
    default:
      throw StateError('Unhandled value ref "$key".');
  }
}

Map<String, FlowTransition> _decodeTransitions(
  Map<String, Object?> json,
  String path,
) {
  return {
    for (final entry in json.entries)
      entry.key: _decodeTransition(
        _asObject(entry.value, '$path.${entry.key}'),
        '$path.${entry.key}',
      ),
  };
}

FlowTransition _decodeTransition(Map<String, Object?> json, String path) {
  final type = _requiredString(json, 'type');
  switch (type) {
    case 'goto':
      _rejectUnknownKeys(json, const {'set', 'target', 'type'}, path);
      return GotoFlowTransition(
        _requiredString(json, 'target'),
        stateWrites:
            _decodeStateWrites(_optionalObject(json, 'set'), '$path.set'),
      );
    case 'action':
      _rejectUnknownKeys(
        json,
        const {'action', 'resultPredicate', 'set', 'target', 'type'},
        path,
      );
      return ActionFlowTransition(
        action: _requiredString(json, 'action'),
        resultPredicate: _decodeActionResultPredicate(
          _requiredObject(json, 'resultPredicate'),
          '$path.resultPredicate',
        ),
        target: _requiredString(json, 'target'),
        stateWrites:
            _decodeStateWrites(_optionalObject(json, 'set'), '$path.set'),
      );
    default:
      throw FormatException('Unsupported transition type "$type".');
  }
}

FlowActionResultPredicate _decodeActionResultPredicate(
  Map<String, Object?> json,
  String path,
) {
  final kind = _requiredString(json, 'kind');
  switch (kind) {
    case 'boolEquals':
      _rejectUnknownKeys(json, const {'kind', 'value'}, path);
      return BoolEqualsActionResultPredicate(
        value: _requiredBool(json, 'value'),
      );
    case 'objectBoolFieldEquals':
      _rejectUnknownKeys(json, const {'field', 'kind', 'value'}, path);
      return ObjectBoolFieldEqualsActionResultPredicate(
        field: _requiredString(json, 'field'),
        value: _requiredBool(json, 'value'),
      );
    default:
      throw FormatException(
        'Unsupported action result predicate kind "$kind".',
      );
  }
}

void _rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowedKeys,
  String path, {
  String Function(String key)? unknownMessage,
}) {
  final unknownKeys = json.keys.where((key) => !allowedKeys.contains(key));
  if (unknownKeys.isEmpty) {
    return;
  }

  final key = unknownKeys.first;
  throw FormatException(
    unknownMessage?.call(key) ?? 'Unsupported field "$path.$key".',
  );
}

Map<String, Object?> _encodeDocument(FlowDocument document) {
  final json = <String, Object?>{
    'flow': document.flow,
    'version': document.version,
    'schemaVersion': document.schemaVersion,
    'minClient': document.minClient,
    'initial': document.initial,
    'screenArtifacts': {
      for (final entry in document.screenArtifacts.entries)
        entry.key: _encodeArtifact(entry.value),
    },
    'states': {
      for (final entry in document.states.entries)
        entry.key: _encodeState(entry.value),
    },
  };
  if (document.unsupportedFeatures.isNotEmpty) {
    json['features'] = document.unsupportedFeatures.toList();
  }
  if (document.actions.isNotEmpty) {
    json['actions'] = {
      for (final entry in document.actions.entries)
        entry.key: _encodeActionContract(entry.value),
    };
  }
  if (document.flowState.isNotEmpty) {
    json['flowState'] = {
      for (final entry in document.flowState.entries)
        entry.key: _encodeFlowStateDeclaration(entry.value),
    };
  }
  final shouldEncodeOutbound = !document.outbound.isEmpty ||
      (!document.legacyTerminalResultPassthrough && document.flowState.isEmpty);
  if (shouldEncodeOutbound) {
    json['outbound'] = _encodeOutbound(document.outbound);
  }
  return json;
}

Map<String, Object?> _encodeFlowStateDeclaration(
  FlowStateDeclaration declaration,
) {
  return {
    'type': declaration.type.wireName,
    'classification': declaration.classification.wireName,
    if (declaration.defaultValue != null) 'default': declaration.defaultValue,
  };
}

Map<String, Object?> _encodeOutbound(FlowOutboundDeclarations outbound) {
  return {
    if (outbound.actionArgs.isNotEmpty)
      'actionArgs': {
        for (final entry in outbound.actionArgs.entries)
          entry.key: _encodeOutboundFields(entry.value.fields),
      },
    if (!outbound.terminalResult.isEmpty)
      'terminalResult': _encodeOutboundPayload(outbound.terminalResult),
    if (!outbound.lifecycle.isEmpty)
      'lifecycle': _encodeOutboundPayload(outbound.lifecycle),
    if (!outbound.surveyAnswers.isEmpty)
      'surveyAnswers': _encodeOutboundPayload(outbound.surveyAnswers),
    if (!outbound.subFlowResult.isEmpty)
      'subFlowResult': _encodeOutboundPayload(outbound.subFlowResult),
    if (outbound.customEvents.isNotEmpty)
      'customEvents': {
        for (final entry in outbound.customEvents.entries)
          entry.key: _encodeOutboundPayload(entry.value),
      },
  };
}

Map<String, Object?> _encodeOutboundPayload(
  FlowOutboundPayloadDeclaration declaration,
) {
  return {
    'fields': _encodeOutboundFields(declaration.fields),
  };
}

Map<String, Object?> _encodeOutboundFields(
  Map<String, FlowOutboundField> fields,
) {
  return {
    for (final entry in fields.entries)
      entry.key: _encodeOutboundField(entry.value),
  };
}

Map<String, Object?> _encodeOutboundField(FlowOutboundField field) {
  return {
    'type': field.type.wireName,
    'ref': _encodeOutboundRef(field.ref),
  };
}

Map<String, Object?> _encodeOutboundRef(FlowOutboundRef ref) {
  switch (ref) {
    case StateFlowOutboundRef(:final key, :final path):
      return {
        'state': key,
        if (path.isNotEmpty) 'path': path,
      };
    case EventFlowOutboundRef(:final key, :final path):
      return {
        'event': key,
        if (path.isNotEmpty) 'path': path,
      };
  }
}

Map<String, Object?> _encodeActionContract(FlowActionContract contract) {
  return {
    'actionName': contract.actionName,
    'contractVersion': contract.contractVersion,
    'argsSchema': FlowActionSchema.toJson(contract.argsSchema),
    'argsSchemaHash': contract.argsSchemaHash.value,
    'resultSchema': FlowActionSchema.toJson(contract.resultSchema),
    'resultSchemaHash': contract.resultSchemaHash.value,
    'minClient': contract.minClient,
    'idempotent': contract.idempotent,
  };
}

Map<String, Object?> _encodeArtifact(ScreenArtifact artifact) {
  return {
    'path': artifact.path,
    'version': artifact.version,
    'schemaVersion': artifact.schemaVersion,
    'minClient': artifact.minClient,
    'contentHash': artifact.contentHash.value,
  };
}

Map<String, Object?> _encodeState(FlowState state) {
  switch (state) {
    case ScreenFlowState(:final screen, :final on):
      return {
        'kind': FlowStateKind.screen.wireName,
        'screen': screen,
        'on': {
          for (final entry in on.entries)
            entry.key: _encodeTransition(entry.value),
        },
      };
    case DecisionFlowState(:final branches, :final defaultBranch):
      return {
        'kind': FlowStateKind.decision.wireName,
        'branches': [
          for (final branch in branches) _encodeBranch(branch),
        ],
        'default': _encodeBranchTarget(defaultBranch),
      };
    case SubFlowState(
        :final flow,
        :final version,
        :final schemaVersion,
        :final minClient,
        :final contentHash,
        :final input,
        :final onComplete,
        :final defaultBranch,
        :final subFlowUnavailable,
      ):
      return {
        'kind': FlowStateKind.subFlow.wireName,
        'flow': flow,
        'version': version,
        'schemaVersion': schemaVersion,
        'minClient': minClient,
        'contentHash': contentHash.value,
        if (input.isNotEmpty)
          'input': {
            for (final entry in input.entries)
              entry.key: _encodeValueSource(entry.value),
          },
        'onComplete': [
          for (final branch in onComplete) _encodeBranch(branch),
        ],
        'default': _encodeBranchTarget(defaultBranch),
        if (subFlowUnavailable != null)
          'subFlowUnavailable': _encodeBranchTarget(subFlowUnavailable),
      };
    case EndFlowState(:final result):
      return {
        'kind': FlowStateKind.end.wireName,
        'result': result,
      };
    case UnsupportedFlowState(:final raw):
      return raw;
  }
}

Map<String, Object?> _encodeBranch(FlowBranch branch) {
  return {
    'when': _encodeBranchPredicate(branch.when),
    'goto': branch.target,
    if (branch.stateWrites.isNotEmpty)
      'set': _encodeStateWrites(branch.stateWrites),
  };
}

Map<String, Object?> _encodeBranchTarget(FlowBranchTarget branch) {
  return {
    'goto': branch.target,
    if (branch.stateWrites.isNotEmpty)
      'set': _encodeStateWrites(branch.stateWrites),
  };
}

Map<String, Object?> _encodeBranchPredicate(FlowBranchPredicate predicate) {
  return {
    for (final entry in predicate.fields.entries)
      entry.key: _encodePredicateCondition(entry.value),
  };
}

Map<String, Object?> _encodePredicateCondition(
  FlowPredicateCondition condition,
) {
  switch (condition) {
    case EqualsFlowPredicateCondition(:final value):
      return {'eq': _encodeValueSource(value)};
    case NotEqualsFlowPredicateCondition(:final value):
      return {'ne': _encodeValueSource(value)};
    case InFlowPredicateCondition(:final values):
      return {
        'in': [
          for (final value in values) _encodeValueSource(value),
        ],
      };
    case GreaterThanFlowPredicateCondition(:final value):
      return {'gt': _encodeValueSource(value)};
    case GreaterThanOrEqualsFlowPredicateCondition(:final value):
      return {'gte': _encodeValueSource(value)};
    case LessThanFlowPredicateCondition(:final value):
      return {'lt': _encodeValueSource(value)};
    case LessThanOrEqualsFlowPredicateCondition(:final value):
      return {'lte': _encodeValueSource(value)};
    case ExistsFlowPredicateCondition(:final exists):
      return {'exists': exists};
  }
}

Map<String, Object?> _encodeStateWrites(
  Map<String, FlowStateWrite> stateWrites,
) {
  return {
    for (final entry in stateWrites.entries)
      entry.key: _encodeStateWrite(entry.value),
  };
}

Map<String, Object?> _encodeStateWrite(FlowStateWrite stateWrite) {
  return {
    'type': stateWrite.type.wireName,
    'value': _encodeValueSource(stateWrite.value),
  };
}

Map<String, Object?> _encodeValueSource(FlowValueSource source) {
  switch (source) {
    case LiteralFlowValueSource(:final type, :final value):
      return {'literal': value, 'type': type.wireName};
    case StateFlowValueSource(:final key, :final path):
      return {'ref': _encodeValueRef('state', key, path)};
    case EventFlowValueSource(:final key, :final path):
      return {'ref': _encodeValueRef('event', key, path)};
    case ActionResultFlowValueSource(:final key, :final path):
      return {'ref': _encodeValueRef('actionResult', key, path)};
    case SubFlowResultFlowValueSource(:final key, :final path):
      return {'ref': _encodeValueRef('subFlowResult', key, path)};
  }
}

Map<String, Object?> _encodeValueRef(
  String source,
  String key,
  List<String> path,
) {
  return {
    source: key,
    if (path.isNotEmpty) 'path': path,
  };
}

Map<String, Object?> _encodeTransition(FlowTransition transition) {
  switch (transition) {
    case GotoFlowTransition(:final target, :final stateWrites):
      return {
        'type': transition.type,
        if (stateWrites.isNotEmpty) 'set': _encodeStateWrites(stateWrites),
        'target': target,
      };
    case ActionFlowTransition(:final action, :final target, :final stateWrites):
      return {
        'type': transition.type,
        'action': action,
        'resultPredicate': _encodeActionResultPredicate(
          transition.resultPredicate,
        ),
        if (stateWrites.isNotEmpty) 'set': _encodeStateWrites(stateWrites),
        'target': target,
      };
  }
}

Map<String, Object?> _encodeActionResultPredicate(
  FlowActionResultPredicate predicate,
) {
  switch (predicate) {
    case BoolEqualsActionResultPredicate(:final value):
      return {
        'kind': predicate.kind,
        'value': value,
      };
    case ObjectBoolFieldEqualsActionResultPredicate(:final field, :final value):
      return {
        'kind': predicate.kind,
        'field': field,
        'value': value,
      };
  }
}

Object? _sortJsonValue(Object? value) {
  switch (value) {
    case null:
      throw ArgumentError.value(
        value,
        'value',
        'Null JSON values are not supported in flow documents.',
      );
    case String() || bool() || int():
      return value;
    case double():
      throw ArgumentError.value(
        value,
        'value',
        'Doubles and non-finite numbers are not supported.',
      );
    case List<Object?>():
      return [for (final item in value) _sortJsonValue(item)];
    case Map<String, Object?>():
      final keys = value.keys.toList()..sort();
      return {
        for (final key in keys) key: _sortJsonValue(value[key]),
      };
    case Map():
      throw ArgumentError.value(
        value,
        'value',
        'JSON object keys must be strings.',
      );
    default:
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported JSON value type ${value.runtimeType}.',
      );
  }
}

Map<String, Object?>? _optionalObject(
  Map<String, Object?> json,
  String key,
) {
  if (!json.containsKey(key)) {
    return null;
  }
  final value = json[key];
  if (value == null) {
    throw FormatException('Field "$key" cannot be null.');
  }
  return _asObject(value, key);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is String) {
    return value;
  }
  throw FormatException('Expected "$key" to be a non-null string.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is int) {
    return value;
  }
  if (value is double) {
    throw FormatException('Expected "$key" to be an integer, got double.');
  }
  throw FormatException('Expected "$key" to be a non-null integer.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected "$key" to be a non-null boolean.');
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  return _asObject(_required(json, key), key);
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is List) {
    return value.cast<Object?>();
  }
  throw FormatException('Expected "$key" to be a non-null list.');
}

Object? _required(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$key".');
  }
  final value = json[key];
  if (value == null) {
    throw FormatException('Field "$key" cannot be null.');
  }
  return value;
}

Map<String, Object?> _asObject(Object? value, String key) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  throw FormatException('Expected "$key" to be an object.');
}

void _checkDecodedActionInvariants(FlowDocument document) {
  final issues = FlowDocumentValidation.validate(document)
      .where(
        (issue) =>
            issue.code == 'actionNameMismatch' ||
            issue.code == 'duplicateActionName' ||
            issue.code == 'missingAction',
      )
      .toList();
  if (issues.isEmpty) {
    return;
  }
  throw FormatException(issues.map((issue) => issue.toString()).join('\n'));
}
