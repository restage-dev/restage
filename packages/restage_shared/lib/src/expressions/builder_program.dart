import 'dart:convert';
import 'dart:collection';
import 'package:restage_shared/src/expressions/value_program.dart';

/// Reserved installed runtime continuation, absent from the authoring catalog.
const kBuilderContinuationWidgetName = '__RestageBuilderContinuation';

/// Inert declaration locating an installed native value.
const nativeBindingReferenceValueType = ValueType(
  'record',
  fields: {
    'kind': ValueType.string,
    'key': ValueType.string,
    'type': ValueType.string,
    'nullable': ValueType.boolean,
  },
);

/// Control flow for a pure widget callback or finite child collection.
final class BuilderResult {
  const BuilderResult._(this.kind,
      {this.bodyIndex,
      this.values = const {},
      this.key,
      this.keyType = 'Object',
      this.condition,
      this.thenResult,
      this.elseResult,
      this.children = const [],
      this.parameter});
  const BuilderResult.body(int bodyIndex,
      {Map<String, int> values = const {}, int? key, String keyType = 'Object'})
      : this._('body',
            bodyIndex: bodyIndex, values: values, key: key, keyType: keyType);
  const BuilderResult.branch(
      int condition, BuilderResult thenResult, BuilderResult elseResult)
      : this._('branch',
            condition: condition,
            thenResult: thenResult,
            elseResult: elseResult);
  const BuilderResult.let(int node, BuilderResult next)
      : this._('let', condition: node, thenResult: next);
  const BuilderResult.nullResult() : this._('null');
  const BuilderResult.sequence(List<BuilderResult> children)
      : this._('sequence', children: children);
  const BuilderResult.forEach(int length, String parameter, BuilderResult body)
      : this._('forEach',
            condition: length, parameter: parameter, thenResult: body);
  const BuilderResult.forEachItem(
      int source, String parameter, BuilderResult body)
      : this._('forEachItem',
            condition: source, parameter: parameter, thenResult: body);
  final String kind;
  final int? bodyIndex;
  final Map<String, int> values;
  final int? key;
  final String keyType;
  final int? condition;
  final BuilderResult? thenResult;
  final BuilderResult? elseResult;
  final List<BuilderResult> children;
  final String? parameter;
  Iterable<BuilderResult> get descendants sync* {
    if (thenResult != null) yield thenResult!;
    if (elseResult != null) yield elseResult!;
    yield* children;
  }

  Map<String, Object?> toJson() => switch (kind) {
        'body' => {
            'kind': kind,
            'body': bodyIndex,
            'values': values,
            if (key != null) 'key': key,
            if (key != null) 'keyType': keyType
          },
        'branch' => {
            'kind': kind,
            'condition': condition,
            'then': thenResult!.toJson(),
            'else': elseResult!.toJson()
          },
        'let' => {
            'kind': kind,
            'node': condition,
            'then': thenResult!.toJson()
          },
        'sequence' => {
            'kind': kind,
            'children': children.map((c) => c.toJson()).toList()
          },
        'forEachItem' => {
            'kind': kind,
            'source': condition,
            'parameter': parameter,
            'then': thenResult!.toJson()
          },
        'forEach' => {
            'kind': kind,
            'length': condition,
            'parameter': parameter,
            'then': thenResult!.toJson()
          },
        _ => {'kind': 'null'},
      };
  factory BuilderResult.fromJson(Map<String, Object?> json, [int depth = 0]) {
    if (depth > 64)
      throw const FormatException('Builder result exceeds depth limit');
    final allowed = switch (json['kind']) {
      'body' => {'kind', 'body', 'values', 'key', 'keyType'},
      'branch' => {'kind', 'condition', 'then', 'else'},
      'let' => {'kind', 'node', 'then'},
      'sequence' => {'kind', 'children'},
      'forEach' => {'kind', 'length', 'parameter', 'then'},
      'forEachItem' => {'kind', 'source', 'parameter', 'then'},
      'null' => {'kind'},
      _ => <String>{}
    };
    if (json.keys.any((key) => !allowed.contains(key)))
      throw const FormatException('Unknown builder result field');
    if (json.containsKey('key') != json.containsKey('keyType') ||
        (json.containsKey('key') &&
            (json['key'] is! int || json['keyType'] is! String)))
      throw const FormatException(
          'Key projection requires its native generic type');
    BuilderResult child(String name) =>
        BuilderResult.fromJson((json[name]! as Map).cast(), depth + 1);
    return switch (json['kind']) {
      'body' => BuilderResult.body(json['body']! as int,
          values: (json['values']! as Map).cast<String, int>(),
          key: json['key'] as int?,
          keyType: json['keyType'] as String? ?? 'Object'),
      'branch' => BuilderResult.branch(
          json['condition']! as int, child('then'), child('else')),
      'let' => BuilderResult.let(json['node']! as int, child('then')),
      'sequence' => BuilderResult.sequence((json['children']! as List)
          .map((c) => BuilderResult.fromJson((c as Map).cast(), depth + 1))
          .toList()),
      'forEachItem' => BuilderResult.forEachItem(
          json['source']! as int, json['parameter']! as String, child('then')),
      'forEach' => BuilderResult.forEach(
          json['length']! as int, json['parameter']! as String, child('then')),
      'null' => const BuilderResult.nullResult(),
      _ => throw const FormatException('Unknown builder result'),
    };
  }
}

/// A validated deferred callback, including explicit nullable returns.
final class BuilderProgram {
  const BuilderProgram(
      {required this.values,
      required this.result,
      required this.bodyCount,
      this.nullableResult = false,
      this.collection = false});
  final ValueProgram values;
  final BuilderResult result;
  final int bodyCount;
  final bool nullableResult;

  /// Collection plans preserve native eager child-list ordering and omission.
  final bool collection;
  Set<String> get iterationParameters {
    final names = <String>{};
    void visit(BuilderResult result) {
      if (result.kind == 'forEach' || result.kind == 'forEachItem')
        names.add(result.parameter!);
      for (final child in result.descendants) {
        visit(child);
      }
    }

    visit(result);
    return names;
  }

  String encode() => jsonEncode({
        'version': valueProgramVersion,
        'values': values.toJson(),
        'result': result.toJson(),
        'bodyCount': bodyCount,
        'nullableResult': nullableResult,
        if (collection) 'collection': true
      });
  factory BuilderProgram.decode(String encoded,
      {Map<String, ValueOperation> operations = const {},
      ValueOperationContext? context}) {
    if (encoded.length > 262144)
      throw const FormatException('Builder program exceeds size limit');
    final json = (jsonDecode(encoded) as Map).cast<String, Object?>();
    if (json['version'] != valueProgramVersion ||
        json.keys.any((k) => !const {
              'version',
              'values',
              'result',
              'bodyCount',
              'nullableResult',
              'collection'
            }.contains(k)))
      throw const FormatException('Unsupported builder program');
    final result = BuilderProgram(
        values: ValueProgram.decode(jsonEncode(json['values']),
            operations: operations, context: context),
        result: BuilderResult.fromJson((json['result']! as Map).cast()),
        bodyCount: json['bodyCount']! as int,
        nullableResult: json['nullableResult']! as bool,
        collection: json['collection'] as bool? ?? false);
    result.validate(operations: operations, context: context);
    return result;
  }
  void validate(
      {Map<String, ValueOperation> operations = const {},
      ValueOperationContext? context}) {
    values.validate(operations: operations, context: context);
    if (bodyCount < 0 || bodyCount > 256)
      throw const FormatException('Invalid builder body count');
    var cost = 0;
    final iterations = iterationParameters;
    final allocated = <String>{};
    final reads = <Set<String>>[];
    for (final node in values.nodes) {
      reads.add({
        if (node.op == 'parameter') node.name!,
        for (final input in node.inputs) ...reads[input]
      });
    }
    ValueType node(int? index, Set<String> scope) {
      if (index == null || index < 0 || index >= values.nodes.length)
        throw const FormatException('Unresolved builder value');
      if (reads[index].any((p) => iterations.contains(p) && !scope.contains(p)))
        throw const FormatException(
            'Collection parameter escapes its iteration');
      return values.nodes[index].type;
    }

    void visit(BuilderResult result, int depth, Set<String> scope) {
      if (++cost > 2048 || depth > 64)
        throw const FormatException('Builder result exceeds structural limit');
      switch (result.kind) {
        case 'body':
          if (result.bodyIndex == null ||
              result.bodyIndex! < 0 ||
              result.bodyIndex! >= bodyCount)
            throw const FormatException('Unresolved builder body');
          for (final value in result.values.values) {
            if (const {'list', 'iterable', 'record'}
                .contains(node(value, scope).kind))
              throw const FormatException(
                  'Builder frame requires projected primitive values');
          }
          if (result.key == null && result.keyType != 'Object')
            throw const FormatException('Absent key has no generic metadata');
          if (result.key != null) {
            final type = node(result.key, scope);
            if (result.keyType == 'nativeKey') {
              if (type.kind != 'native' || type.nativeType != 'flutter.Key') {
                throw const FormatException(
                    'Native key requires its exact nominal type');
              }
              break;
            }
            if (result.keyType == 'nativeBinding') {
              if (!nativeBindingReferenceValueType.accepts(type) ||
                  !type.accepts(nativeBindingReferenceValueType)) {
                throw const FormatException(
                  'Invalid native key reference shape',
                );
              }
              break;
            }
            const tags = {
              'Object',
              'Object?',
              'dynamic',
              'String',
              'String?',
              'int',
              'int?',
              'double',
              'double?',
              'num',
              'num?',
              'bool',
              'bool?',
              'Null'
            };
            if (!tags.contains(result.keyType) ||
                !const {'String', 'int', 'double', 'num', 'bool', 'Null'}
                    .contains(type.kind)) {
              throw const FormatException('Unsupported scalar ValueKey type');
            }
            final nullable = result.keyType.endsWith('?');
            final generic = nullable
                ? result.keyType.substring(0, result.keyType.length - 1)
                : result.keyType;
            final matches = switch (generic) {
              'dynamic' => true,
              'Object' => nullable || !type.nullable,
              'Null' => type.kind == 'Null',
              _ => ValueType(generic, nullable: nullable).accepts(type),
            };
            if (!matches)
              throw const FormatException(
                  'ValueKey generic type differs from its value');
          }
        case 'branch':
          final type = node(result.condition, scope);
          if (type.kind != 'bool' || type.nullable)
            throw const FormatException('Builder condition must be bool');
          visit(result.thenResult!, depth + 1, scope);
          visit(result.elseResult!, depth + 1, scope);
        case 'let':
          node(result.condition, scope);
          visit(result.thenResult!, depth + 1, scope);
        case 'null':
          if (!nullableResult)
            throw const FormatException('Nonnullable builder returns null');
        case 'sequence':
          if (!collection)
            throw const FormatException(
                'Callback cannot return a child sequence');
          for (final child in result.children) {
            visit(child, depth + 1, scope);
          }
        case 'forEachItem':
          final source = node(result.condition, scope);
          final type = values.parameters[result.parameter];
          if (!collection ||
              !{'list', 'iterable'}.contains(source.kind) ||
              source.nullable ||
              type == null ||
              !type.accepts(source.item!) ||
              !allocated.add(result.parameter!))
            throw const FormatException('Malformed finite iterable traversal');
          visit(result.thenResult!, depth + 1, {...scope, result.parameter!});
        case 'forEach':
          final length = node(result.condition, scope);
          final type = values.parameters[result.parameter];
          if (!collection ||
              length.kind != 'int' ||
              length.nullable ||
              type?.kind != 'int' ||
              type!.nullable ||
              !allocated.add(result.parameter!))
            throw const FormatException(
                'Malformed finite collection iteration');
          visit(result.thenResult!, depth + 1, {...scope, result.parameter!});
        default:
          throw const FormatException('Unknown builder result');
      }
    }

    visit(result, 0, {});
  }

  BuilderInvocation invoke(
      {required ValueReader captures,
      required Map<String, Object?> parameters,
      Map<String, ValueOperation> operations = const {},
      ValueOperationContext? context}) {
    if (collection)
      throw const FormatException(
          'Collection program requires list invocation');
    return _invoke(captures, parameters, operations, context).single;
  }

  /// Evaluates finite child construction; a null result omits that child.
  List<BuilderInvocation> invokeAll(
      {required ValueReader captures,
      required Map<String, Object?> parameters,
      Map<String, ValueOperation> operations = const {},
      ValueOperationContext? context}) {
    if (!collection)
      throw const FormatException('Callback program requires one invocation');
    return _invoke(captures, parameters, operations, context)
        .where((i) => !i.isNull)
        .toList();
  }

  List<BuilderInvocation> _invoke(
      ValueReader captures,
      Map<String, Object?> parameters,
      Map<String, ValueOperation> operations,
      ValueOperationContext? context) {
    validate(operations: operations, context: context);
    ValueEvaluator evaluator(Map<String, Object?> parameters) =>
        ValueEvaluator(values,
            captures: captures,
            parameters: parameters,
            operations: operations,
            context: context);
    final results = <BuilderInvocation>[];
    void visit(BuilderResult result, ValueEvaluator values,
        Map<String, Object?> parameters) {
      switch (result.kind) {
        case 'null':
          results.add(const BuilderInvocation.nullResult());
        case 'body':
          results.add(BuilderInvocation(
              result.bodyIndex!,
              {
                for (final entry in result.values.entries)
                  entry.key: values.evaluate(entry.value)
              },
              frame: values.frame,
              projectedKey:
                  result.key == null ? null : values.evaluate(result.key),
              keyType: result.keyType,
              hasKey: result.key != null));
        case 'branch':
          visit(
              values.evaluate(result.condition)! as bool
                  ? result.thenResult!
                  : result.elseResult!,
              values,
              parameters);
        case 'let':
          values.bind(result.condition!);
          visit(result.thenResult!, values, parameters);
        case 'sequence':
          for (final child in result.children) {
            visit(child, values, parameters);
          }
        case 'forEachItem':
          final source =
              values.evaluate(result.condition)! as Iterable<Object?>;
          for (final item in source) {
            final frame =
                _IterationParameters(parameters, result.parameter!, item);
            visit(result.thenResult!, values.fork(parameters: frame), frame);
          }
        case 'forEach':
          final length = values.evaluate(result.condition)! as int;
          if (length < 0)
            throw const FormatException('Negative collection length');
          for (var index = 0; index < length; index++) {
            final frame =
                _IterationParameters(parameters, result.parameter!, index);
            visit(result.thenResult!, values.fork(parameters: frame), frame);
          }
        default:
          throw const FormatException('Unknown builder result');
      }
    }

    visit(result, evaluator(parameters), parameters);
    return results;
  }
}

/// One selected body and the values it demands.
final class BuilderInvocation {
  const BuilderInvocation(this.bodyIndex, this.values,
      {this.frame, this.projectedKey, this.keyType = 'Object', bool? hasKey})
      : hasKey = hasKey ?? (projectedKey != null);
  const BuilderInvocation.nullResult()
      : frame = null,
        bodyIndex = null,
        values = const {},
        projectedKey = null,
        keyType = 'Object',
        hasKey = false;
  final ValueLocalFrame? frame;
  final int? bodyIndex;
  final Map<String, Object?> values;
  final Object? projectedKey;
  final String keyType;
  final bool hasKey;
  bool get isNull => bodyIndex == null;
}

/// A lexical iteration frame that never reads unrelated native parameters.
final class _IterationParameters extends MapBase<String, Object?> {
  _IterationParameters(this.parent, this.name, this.value);
  final Map<String, Object?> parent;
  final String name;
  final Object? value;
  @override
  Iterable<String> get keys => {...parent.keys, name};
  @override
  Object? operator [](Object? key) => key == name ? value : parent[key];
  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Immutable iteration frame');
  @override
  void clear() => throw UnsupportedError('Immutable iteration frame');
  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Immutable iteration frame');
}
