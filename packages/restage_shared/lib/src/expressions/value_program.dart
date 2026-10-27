import 'dart:convert';
import 'dart:collection';

import 'package:restage_shared/src/expressions/collection_operations.dart'
    show isNativeCollectionItem, typedValueList;
import 'package:restage_shared/src/surface_contract/native_binding_contract.dart';

/// A trusted installed object; never constructed from a payload literal.
abstract interface class ValueNative {
  NativeBindingContract get contract;
  Object? get value;
}

/// Version of the closed value program encoding.
const valueProgramVersion = 1;

/// Catalog floor required by deferred value programs.
const valueProgramCapability = 19;

/// The program name of a native callback's parameter at [position].
String callbackParameterName(int position) => 'arg$position';

/// Fixed installed Material swatches admitted by the color boundary.
const canonicalMaterialColorNames = <String>{
  'red',
  'redAccent',
  'pink',
  'pinkAccent',
  'purple',
  'purpleAccent',
  'deepPurple',
  'deepPurpleAccent',
  'indigo',
  'indigoAccent',
  'blue',
  'blueAccent',
  'lightBlue',
  'lightBlueAccent',
  'cyan',
  'cyanAccent',
  'teal',
  'tealAccent',
  'green',
  'greenAccent',
  'lightGreen',
  'lightGreenAccent',
  'lime',
  'limeAccent',
  'yellow',
  'yellowAccent',
  'amber',
  'amberAccent',
  'orange',
  'orangeAccent',
  'deepOrange',
  'deepOrangeAccent',
  'brown',
  'grey',
  'blueGrey',
};

/// Exact inert components of a native color, independent of Flutter objects.
const colorValueType = ValueType('record', fields: {
  'a': ValueType.real,
  'r': ValueType.real,
  'g': ValueType.real,
  'b': ValueType.real,
  'colorSpace': ValueType.string,
  'material': ValueType.string,
});

/// Preserves the native Color(int) low-32-bit channel conversion.
Map<String, Object?> argbColorValue(int value) => {
      'a': ((value >> 24) & 0xff) / 255,
      'r': ((value >> 16) & 0xff) / 255,
      'g': ((value >> 8) & 0xff) / 255,
      'b': (value & 0xff) / 255,
      'colorSpace': 'sRGB',
      'material': '',
    };

/// A finite inert value shape. Records expose only their declared fields.
final class ValueType {
  const ValueType(this.kind,
      {this.nullable = false,
      this.item,
      this.fields = const {},
      this.nativeType});
  const ValueType.native(String type, {this.nullable = false})
      : kind = 'native',
        nativeType = type,
        item = null,
        fields = const {};
  final String? nativeType;
  final String kind;
  final bool nullable;
  final ValueType? item;
  final Map<String, ValueType> fields;
  static const boolean = ValueType('bool');
  static const integer = ValueType('int');
  static const real = ValueType('double');
  static const number = ValueType('num');
  static const string = ValueType('String');
  static const nullType = ValueType('Null', nullable: true);
  bool get numeric => const {'int', 'double', 'num'}.contains(kind);
  ValueType get nonNull =>
      ValueType(kind, item: item, fields: fields, nativeType: nativeType);
  Map<String, Object?> toJson() => {
        'kind': kind,
        if (nativeType != null) 'nativeType': nativeType,
        if (nullable) 'nullable': true,
        if (item != null) 'item': item!.toJson(),
        if (fields.isNotEmpty)
          'fields': fields.map((k, v) => MapEntry(k, v.toJson()))
      };
  factory ValueType.fromJson(Map<String, Object?> json, [int depth = 0]) {
    if (depth > 32)
      throw const FormatException('Value shape exceeds depth limit');
    _keys(json, {'kind', 'nullable', 'item', 'fields', 'nativeType'});
    final kind = json['kind'] as String;
    if (!const {
      'bool',
      'int',
      'double',
      'num',
      'String',
      'Null',
      'list',
      'iterable',
      'record',
      'native'
    }.contains(kind)) throw FormatException('Unknown value type $kind');
    final item = json['item'];
    final fields = json['fields'];
    final result = ValueType(kind,
        nullable: json['nullable'] as bool? ?? false,
        nativeType: json['nativeType'] as String?,
        item: item == null ? null : ValueType.fromJson(_map(item), depth + 1),
        fields: fields == null
            ? const {}
            : _map(fields).map(
                (k, v) => MapEntry(k, ValueType.fromJson(_map(v), depth + 1))));
    if ((kind == 'native') != (result.nativeType != null) ||
        result.nativeType == '' ||
        ({'list', 'iterable'}.contains(kind)) != (result.item != null) ||
        (kind != 'record' && result.fields.isNotEmpty) ||
        (kind == 'Null' && !result.nullable))
      throw const FormatException('Malformed value shape');
    return result;
  }
  bool get containsNative =>
      kind == 'native' ||
      (item?.containsNative ?? false) ||
      fields.values.any((type) => type.containsNative);
  bool matches(Object? value) => _matches(value, this);
  bool accepts(ValueType other) {
    if (other.kind == 'Null') return nullable;
    if (!nullable && other.nullable) return false;
    if (kind == 'num' && other.numeric) return true;
    if (kind == 'iterable' && other.kind == 'list')
      return item != null && other.item != null && item!.accepts(other.item!);
    if (kind != other.kind ||
        nativeType != other.nativeType ||
        fields.length != other.fields.length) return false;
    if (item != null && (other.item == null || !item!.accepts(other.item!)))
      return false;
    return fields.entries.every((field) =>
        other.fields[field.key] != null &&
        field.value.accepts(other.fields[field.key]!));
  }
}

/// One typed expression. Inputs refer only to earlier nodes.
final class ValueNode {
  const ValueNode(this.op, this.type,
      {this.inputs = const [], this.value, this.name});
  final String op;
  final ValueType type;
  final List<int> inputs;
  final Object? value;
  final String? name;
  Map<String, Object?> toJson() => {
        'op': op,
        'type': type.toJson(),
        if (inputs.isNotEmpty) 'inputs': inputs,
        if (value != null || op == 'literal') 'value': value,
        if (name != null) 'name': name
      };
  factory ValueNode.fromJson(Map<String, Object?> json) {
    _keys(json, {'op', 'type', 'inputs', 'value', 'name'});
    return ValueNode(
        json['op'] as String, ValueType.fromJson(_map(json['type'])),
        inputs: (json['inputs'] as List?)?.cast<int>() ?? const [],
        value: json['value'],
        name: json['name'] as String?);
  }
}

/// Installed, typed operations extend the same evaluator vocabulary.
abstract interface class ValueOperation {
  String get name;
  int get capability;
  void validate(ValueNode node, List<ValueType> inputs);
  Object? evaluate(List<Object?> inputs, Object? options);
}

/// Shared typed context for nested closed programs.
final class ValueOperationContext {
  const ValueOperationContext(
      {this.operations = const {},
      this.locals = const {},
      this.frame,
      this.depth = 0});
  final Map<String, ValueOperation> operations;
  final Map<String, ValueType> locals;
  final ValueLocalFrame? frame;
  final int depth;
  ValueOperationContext nested(
      {Map<String, ValueType> locals = const {}, ValueLocalFrame? frame}) {
    if (depth >= 32) throw const FormatException('Value program nesting limit');
    return ValueOperationContext(
        operations: operations,
        locals: {...this.locals, ...locals},
        frame: frame ?? this.frame,
        depth: depth + 1);
  }
}

/// Invocation-local cells, captured by reference by nested callbacks.
final class ValueLocalFrame {
  ValueLocalFrame(this.types, {this.parent});
  final Map<String, ValueType> types;
  final ValueLocalFrame? parent;
  final Map<String, Object?> _values = {};
  Map<String, ValueType> get visibleTypes =>
      {...?parent?.visibleTypes, ...types};
  ValueLocalFrame _owner(String name) {
    if (types.containsKey(name)) return this;
    if (parent != null) return parent!._owner(name);
    throw StateError('Undeclared local $name');
  }

  bool _initialized(String name) => _owner(name)._values.containsKey(name);
  Object? read(String name) {
    final owner = _owner(name);
    if (!owner._values.containsKey(name))
      throw StateError('Uninitialized local $name');
    return owner._values[name];
  }

  Object? write(String name, Object? value) {
    final owner = _owner(name);
    if (!_matches(value, owner.types[name]!))
      throw StateError('Invalid local $name');
    return owner._values[name] = value;
  }
}

/// An installed operation using the owning registry and lexical scope.
abstract interface class RegistryValueOperation implements ValueOperation {
  Iterable<ValueProgram> nestedPrograms(
      ValueNode node, ValueOperationContext context);
  void validateWithContext(
      ValueNode node, List<ValueType> inputs, ValueOperationContext context);
  Object? evaluateWithContext(
      List<Object?> inputs, Object? options, ValueOperationContext context);
}

/// Derives the installed capability floor, including nested closed programs.
int valueProgramRequiredCapability(ValueProgram program,
    {Map<String, ValueOperation> operations = const {},
    ValueOperationContext? context}) {
  context ??= ValueOperationContext(operations: operations);
  program.validate(operations: operations, context: context);
  final scope = ValueOperationContext(
      operations: operations,
      locals: {...program.outerLocals, ...program.locals},
      depth: context.depth);
  var capability = program.locals.isNotEmpty || program.outerLocals.isNotEmpty
      ? 24
      : valueProgramCapability;
  if ([
    ...program.captures.values,
    ...program.parameters.values,
    ...program.locals.values,
    ...program.outerLocals.values,
    ...program.nodes.map((node) => node.type)
  ].any((type) => type.containsNative)) {
    capability = 24;
  }
  for (final node in program.nodes) {
    final operation = operations[node.op];
    final required = operation?.capability ?? valueProgramCapability;
    if (required > capability) capability = required;
    if (operation is RegistryValueOperation) {
      for (final nested in operation.nestedPrograms(node, scope)) {
        final required = valueProgramRequiredCapability(nested,
            operations: operations, context: scope.nested());
        if (required > capability) capability = required;
      }
    }
  }
  return capability;
}

/// A finite expression graph with declared capture and native parameter shapes.
final class ValueProgram {
  const ValueProgram(
      {required this.nodes,
      required this.root,
      this.captures = const {},
      this.parameters = const {},
      this.locals = const {},
      this.outerLocals = const {}});
  final List<ValueNode> nodes;
  final int root;
  final Map<String, ValueType> captures;
  final Map<String, ValueType> parameters;
  final Map<String, ValueType> locals;
  final Map<String, ValueType> outerLocals;
  Map<String, Object?> toJson() => {
        'version': valueProgramVersion,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'root': root,
        'captures': captures.map((k, v) => MapEntry(k, v.toJson())),
        'parameters': parameters.map((k, v) => MapEntry(k, v.toJson())),
        if (locals.isNotEmpty)
          'locals': locals.map((k, v) => MapEntry(k, v.toJson())),
        if (outerLocals.isNotEmpty)
          'outerLocals': outerLocals.map((k, v) => MapEntry(k, v.toJson()))
      };
  String encode() => jsonEncode(toJson());
  factory ValueProgram.decode(String encoded,
      {Map<String, ValueOperation> operations = const {},
      ValueOperationContext? context}) {
    if (encoded.length > 262144)
      throw const FormatException('Value program exceeds size limit');
    final json = _map(jsonDecode(encoded));
    _keys(json, {
      'version',
      'nodes',
      'root',
      'captures',
      'parameters',
      'locals',
      'outerLocals'
    });
    if (json['version'] != valueProgramVersion)
      throw const FormatException('Unsupported value program version');
    final result = ValueProgram(
        nodes: (json['nodes'] as List)
            .map((n) => ValueNode.fromJson(_map(n)))
            .toList(),
        root: json['root'] as int,
        locals: _map(json['locals'] ?? {})
            .map((k, v) => MapEntry(k, ValueType.fromJson(_map(v)))),
        outerLocals: _map(json['outerLocals'] ?? {})
            .map((k, v) => MapEntry(k, ValueType.fromJson(_map(v)))),
        captures: _map(json['captures'])
            .map((k, v) => MapEntry(k, ValueType.fromJson(_map(v)))),
        parameters: _map(json['parameters'])
            .map((k, v) => MapEntry(k, ValueType.fromJson(_map(v)))));
    result.validate(operations: operations, context: context);
    return result;
  }
  void validate(
      {Map<String, ValueOperation> operations = const {},
      ValueOperationContext? context}) {
    context ??= ValueOperationContext(operations: operations);
    for (final type in [
      ...captures.values,
      ...parameters.values,
      ...locals.values,
      ...outerLocals.values,
      ...nodes.map((node) => node.type)
    ]) {
      if (type.containsNative && type.kind != 'native') {
        throw const FormatException(
            'Native containers require a nominal installed type');
      }
    }
    for (final entry in outerLocals.entries) {
      final outer = context.locals[entry.key];
      if (outer == null ||
          !entry.value.accepts(outer) ||
          !outer.accepts(entry.value))
        throw const FormatException('Invalid outer local binding');
    }
    if (locals.keys.any(outerLocals.containsKey))
      throw const FormatException('Duplicate local slot');
    bool internal(ValueType type) =>
        type.kind == 'iterable' ||
        (type.item != null && internal(type.item!)) ||
        type.fields.values.any(internal);
    if (captures.values.any(internal) || parameters.values.any(internal))
      throw const FormatException('Internal iterable cannot be captured');
    final localTypes = {...outerLocals, ...locals};
    final operationContext = ValueOperationContext(
        operations: operations,
        locals: localTypes,
        frame: context.frame,
        depth: context.depth);

    if (nodes.isEmpty ||
        nodes.length > 2048 ||
        root < 0 ||
        root >= nodes.length)
      throw const FormatException('Invalid value graph size or root');
    final depths = <int>[];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.inputs.any((j) => j < 0 || j >= i))
        throw FormatException('Value node $i has a cyclic or unresolved input');
      final depth =
          node.inputs.fold(0, (int d, int j) => depths[j] > d ? depths[j] : d) +
              1;
      if (depth > 64)
        throw const FormatException('Value expression exceeds depth limit');
      depths.add(depth);
      final args = node.inputs.map((j) => nodes[j].type).toList();
      void require(bool valid) {
        if (!valid)
          throw FormatException('Invalid ${node.op} types at node $i');
      }

      if (!operations.containsKey(node.op)) {
        require(node.name == null ||
            const {'capture', 'parameter', 'field', 'local.read', 'local.write'}
                .contains(node.op));
        require(node.value == null || node.op == 'literal');
      }
      if ({'list', 'iterable'}.contains(node.type.kind)) {
        require(
            node.type.item != null && isNativeCollectionItem(node.type.item!));
      }
      bool numeric(int count) =>
          args.length == count && args.every((t) => t.numeric && !t.nullable);
      switch (node.op) {
        case 'local.read':
          require(args.isEmpty &&
              localTypes[node.name] != null &&
              node.type.accepts(localTypes[node.name]!));
        case 'local.write':
          require(args.length == 1 &&
              localTypes[node.name] != null &&
              localTypes[node.name]!.accepts(args.single) &&
              node.type.accepts(args.single));
        case 'let':
          require(args.length == 2 && node.type.accepts(args[1]));
        case 'record':
          require(node.type.kind == 'record' &&
              !node.type.containsNative &&
              !node.type.nullable &&
              args.length == node.type.fields.length &&
              List.generate(
                      args.length,
                      (i) =>
                          node.type.fields.values.elementAt(i).accepts(args[i]))
                  .every((valid) => valid));
        case 'argbColor':
          require(args.length == 1 &&
              args.single.kind == 'int' &&
              !args.single.nullable &&
              colorValueType.accepts(node.type) &&
              node.type.accepts(colorValueType));
        case 'list':
          require(node.type.kind == 'list' &&
              !node.type.containsNative &&
              !node.type.nullable &&
              args.every(node.type.item!.accepts));
        case 'literal':
          require(args.isEmpty &&
              !internal(node.type) &&
              _literalMatches(node.value, node.type));
          if (colorValueType.accepts(node.type) &&
              node.type.accepts(colorValueType)) {
            final material = (node.value! as Map)['material'];
            require(material == '' ||
                canonicalMaterialColorNames.contains(material));
          }
        case 'capture':
          require(args.isEmpty &&
              captures[node.name] != null &&
              node.type.accepts(captures[node.name]!));
        case 'parameter':
          require(args.isEmpty &&
              parameters[node.name] != null &&
              node.type.accepts(parameters[node.name]!));
        case 'field':
          require(args.length == 1 &&
              !args[0].nullable &&
              args[0].kind == 'record' &&
              args[0].fields[node.name] != null &&
              node.type.accepts(args[0].fields[node.name]!));
        case 'index':
          require(args.length == 2 &&
              args[0].kind == 'list' &&
              !args[0].nullable &&
              args[1].kind == 'int' &&
              !args[1].nullable &&
              node.type.accepts(args[0].item!));
        case 'nonNull':
          require(args.length == 1 &&
              args[0].nullable &&
              !node.type.nullable &&
              node.type.accepts(args[0].nonNull));
        case 'length':
          require(args.length == 1 &&
              (args[0].kind == 'list' || args[0].kind == 'String') &&
              !args[0].nullable &&
              node.type.kind == 'int');
        case '&&':
        case '||':
          require(args.length == 2 &&
              args.every((a) => a.kind == 'bool' && !a.nullable) &&
              node.type.kind == 'bool');
        case '!':
          require(args.length == 1 &&
              args[0].kind == 'bool' &&
              !args[0].nullable &&
              node.type.kind == 'bool');
        case 'conditional':
          require(args.length == 3 &&
              args[0].kind == 'bool' &&
              !args[0].nullable &&
              node.type.accepts(args[1]) &&
              node.type.accepts(args[2]));
        case '??':
          require(args.length == 2 &&
              (args[0].kind == 'Null' || node.type.accepts(args[0].nonNull)) &&
              node.type.accepts(args[1]));
        case '==':
        case '!=':
          require(args.length == 2 &&
              (args.any((arg) => arg.kind == 'Null') ||
                  (!const {'list', 'iterable', 'record', 'native'}
                          .contains(args[0].kind) &&
                      !const {'list', 'iterable', 'record', 'native'}
                          .contains(args[1].kind))) &&
              node.type.kind == 'bool');
        case '<':
        case '<=':
        case '>':
        case '>=':
          require(numeric(2) && node.type.kind == 'bool');
        case '+':
        case '-':
        case '*':
        case '%':
          require(numeric(2) &&
              node.type.accepts(ValueType(args.any((a) => a.kind == 'double')
                  ? 'double'
                  : args.every((a) => a.kind == 'int')
                      ? 'int'
                      : 'num')));
        case '/':
          require(numeric(2) && node.type.kind == 'double');
        case '~/':
          require(numeric(2) && node.type.kind == 'int');
        case 'negate':
          require(numeric(1) && node.type.accepts(args[0]));
        case 'floor':
        case 'ceil':
        case 'round':
        case 'toInt':
          require(numeric(1) && node.type.kind == 'int');
        case 'toDouble':
          require(numeric(1) && node.type.kind == 'double');
        case 'clamp':
          require(numeric(3) && node.type.numeric);
        case 'isFinite':
        case 'isInfinite':
          require(numeric(1) && node.type.kind == 'bool');
        case 'isEven':
        case 'isOdd':
          require(args.length == 1 &&
              args[0].kind == 'int' &&
              !args[0].nullable &&
              node.type.kind == 'bool');
        case 'string':
          require(args.length == 1 &&
              !const {'list', 'iterable', 'record', 'native'}
                  .contains(args[0].kind) &&
              node.type.kind == 'String');
        case 'concat':
          require(args.every((a) => a.kind == 'String' && !a.nullable) &&
              node.type.kind == 'String');
        default:
          final operation = operations[node.op];
          if (operation == null)
            throw FormatException('Unknown value operation ${node.op}');
          if (operation is RegistryValueOperation) {
            operation.validateWithContext(node, args, operationContext);
          } else {
            operation.validate(node, args);
          }
      }
    }
  }
}

/// Reads only a requested value or collection length from an inert data source.
abstract interface class ValueReader {
  Object? read(List<Object> path, ValueType type);
  int length(List<Object> path);
}

/// A typed record view that reads only requested stored fields.
final class ValueRecordView extends MapBase<String, Object?> {
  ValueRecordView(this.reader, this.path, this.fields);
  final ValueReader reader;
  final List<Object> path;
  final Map<String, ValueType> fields;
  @override
  Iterable<String> get keys => fields.keys;
  @override
  Object? operator [](Object? key) => key is String && fields.containsKey(key)
      ? reader.read([...path, key], fields[key]!)
      : null;
  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Immutable value record');
  @override
  void clear() => throw UnsupportedError('Immutable value record');
  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Immutable value record');
}

/// A finite typed sequence that reads one requested element at a time.
final class ValueListView extends ListBase<Object?> {
  ValueListView(this.reader, this.path, this.item);
  final ValueReader reader;
  final List<Object> path;
  final ValueType item;
  @override
  int get length => reader.length(path);
  @override
  set length(int value) => throw UnsupportedError('Immutable value list');
  @override
  Object? operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    return reader.read([...path, index], item);
  }

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('Immutable value list');
}

final class _ValueReference {
  const _ValueReference(this.reader, this.path, this.type);
  final ValueReader reader;
  final List<Object> path;
  final ValueType type;
  Object? get value => reader.read(path, type);
}

/// Evaluates one invocation; cached values never leak between invocations.
final class ValueEvaluator {
  ValueEvaluator(this.program,
      {required this.captures,
      required this.parameters,
      this.operations = const {},
      ValueLocalFrame? parentFrame,
      ValueOperationContext? context})
      : frame = ValueLocalFrame(program.locals,
            parent: parentFrame ?? context?.frame),
        depth = context?.depth ?? 0 {
    program.validate(
        operations: operations,
        context: ValueOperationContext(
            operations: operations,
            locals: frame.parent?.visibleTypes ?? {},
            depth: depth));
  }
  ValueEvaluator._fork(this.program, this.captures, this.parameters,
      this.operations, this.frame, this.depth);
  final ValueProgram program;
  final ValueReader captures;
  final Map<String, Object?> parameters;
  final Map<String, ValueOperation> operations;
  final ValueLocalFrame frame;
  final int depth;
  final Map<int, Object?> _cache = {};
  final Set<int> _bound = {};

  /// Starts one iteration while retaining only explicitly bound outer values.
  ValueEvaluator fork({required Map<String, Object?> parameters}) {
    final child = ValueEvaluator._fork(
        program,
        captures,
        parameters,
        operations,
        ValueLocalFrame({
          for (final entry in program.locals.entries)
            if (!frame._initialized(entry.key)) entry.key: entry.value
        }, parent: frame),
        depth);
    for (final node in _bound) {
      child._cache[node] = _cache[node];
      child._bound.add(node);
    }
    return child;
  }

  void bind(int node) {
    final value = _evaluate(node);
    _bound.add(node);
    if (!const {'list', 'record'}.contains(program.nodes[node].type.kind)) {
      _cache[node] = _materialize(value);
    }
  }

  Object? evaluate([int? node]) =>
      _materialize(_evaluate(node ?? program.root));
  Object? _materialize(Object? value) {
    if (value is _ValueReference) {
      final resolved = value.value;
      if (!value.type.matches(resolved))
        throw StateError('Invalid captured value');
      return resolved;
    }
    return value;
  }

  Object? _evaluate(int index) {
    if (_cache.containsKey(index)) return _cache[index];
    final node = program.nodes[index];
    Object? arg(int i) => _materialize(_evaluate(node.inputs[i]));
    num number(int i) => arg(i)! as num;
    final Object? result;
    switch (node.op) {
      case 'local.read':
        result = frame.read(node.name!);
      case 'local.write':
        result = frame.write(node.name!, arg(0));
      case 'let':
        bind(node.inputs[0]);
        result = _evaluate(node.inputs[1]);
      case 'record':
        result = <String, Object?>{
          for (var i = 0; i < node.inputs.length; i++)
            node.type.fields.keys.elementAt(i): arg(i)
        };
      case 'argbColor':
        result = argbColorValue(arg(0)! as int);
      case 'list':
        result = typedValueList(
            [for (var i = 0; i < node.inputs.length; i++) arg(i)],
            node.type.item!);
      case 'literal':
        result = node.value;
      case 'capture':
        result = _ValueReference(captures, [node.name!], node.type);
      case 'parameter':
        if (!parameters.containsKey(node.name))
          throw StateError('Missing callback parameter ${node.name}');
        result = parameters[node.name];
      case 'field':
        final target = _evaluate(node.inputs[0]);
        result = target is _ValueReference
            ? _ValueReference(
                target.reader, [...target.path, node.name!], node.type)
            : (target as Map<String, Object?>)[node.name];
      case 'index':
        final target = _evaluate(node.inputs[0]);
        final index = arg(1)! as int;
        final length = target is _ValueReference
            ? target.reader.length(target.path)
            : (target as List).length;
        RangeError.checkValidIndex(index, target, null, length);
        result = target is _ValueReference
            ? _ValueReference(target.reader, [...target.path, index], node.type)
            : (target as List)[index];
      case 'nonNull':
        result = arg(0)!;
      case 'length':
        final target = _evaluate(node.inputs[0]);
        result = target is _ValueReference && target.type.kind == 'list'
            ? target.reader.length(target.path)
            : switch (_materialize(target)) {
                final String s => s.length,
                final List<Object?> l => l.length,
                _ => throw StateError('Invalid length target')
              };
      case '&&':
        result = (arg(0)! as bool) && (arg(1)! as bool);
      case '||':
        result = (arg(0)! as bool) || (arg(1)! as bool);
      case '!':
        result = !(arg(0)! as bool);
      case 'conditional':
        result = (arg(0)! as bool)
            ? _evaluate(node.inputs[1])
            : _evaluate(node.inputs[2]);
      case '??':
        result = arg(0) ?? _evaluate(node.inputs[1]);
      case '==':
        result = arg(0) == arg(1);
      case '!=':
        result = arg(0) != arg(1);
      case '<':
        result = number(0) < number(1);
      case '<=':
        result = number(0) <= number(1);
      case '>':
        result = number(0) > number(1);
      case '>=':
        result = number(0) >= number(1);
      case '+':
        result = number(0) + number(1);
      case '-':
        result = number(0) - number(1);
      case '*':
        result = number(0) * number(1);
      case '/':
        result = number(0) / number(1);
      case '~/':
        result = number(0) ~/ number(1);
      case '%':
        result = number(0) % number(1);
      case 'negate':
        result = -number(0);
      case 'floor':
        result = number(0).floor();
      case 'ceil':
        result = number(0).ceil();
      case 'round':
        result = number(0).round();
      case 'toInt':
        result = number(0).toInt();
      case 'toDouble':
        result = number(0).toDouble();
      case 'clamp':
        result = number(0).clamp(number(1), number(2));
      case 'isFinite':
        result = number(0).isFinite;
      case 'isInfinite':
        result = number(0).isInfinite;
      case 'isEven':
        result = (arg(0)! as int).isEven;
      case 'isOdd':
        result = (arg(0)! as int).isOdd;
      case 'string':
        result = arg(0).toString();
      case 'concat':
        result = [
          for (var i = 0; i < node.inputs.length; i++) arg(i)! as String
        ].join();
      default:
        final operation = operations[node.op]!;
        result = operation is RegistryValueOperation
            ? operation.evaluateWithContext(
                _OperationInputs(node.inputs.length, arg),
                node.value,
                ValueOperationContext(
                    operations: operations,
                    locals: frame.visibleTypes,
                    frame: frame,
                    depth: depth))
            : operation.evaluate(
                [for (var i = 0; i < node.inputs.length; i++) arg(i)],
                node.value);
    }
    if (result is! _ValueReference && !_matches(result, node.type))
      throw StateError(
          'Operation ${node.op} returned an invalid ${node.type.kind}');
    return _cache[index] = result;
  }
}

bool _literalMatches(Object? value, ValueType type) {
  if (type.kind == 'native') return false;
  if (!_matches(value, type)) return false;
  if (value == null) return true;
  if (type.kind == 'record') {
    final fields = value as Map<String, Object?>;
    return fields.length == type.fields.length &&
        type.fields.entries.every((field) =>
            fields.containsKey(field.key) &&
            _literalMatches(fields[field.key], field.value));
  }
  if (type.kind == 'list')
    return (value as List).every((item) => _literalMatches(item, type.item!));
  return true;
}

bool _matches(Object? value, ValueType type) {
  if (value == null) return type.nullable;
  return switch (type.kind) {
    'bool' => value is bool,
    'int' => value is int,
    'double' => value is double,
    'num' => value is num,
    'String' => value is String,
    'native' => value is ValueNative &&
        value.value != null &&
        value.contract.call == null &&
        value.contract.type == type.nativeType,
    'list' => value is List,
    'iterable' => value is Iterable,
    'record' => value is Map<String, Object?>,
    _ => false
  };
}

Map<String, Object?> _map(Object? value) =>
    (value! as Map).cast<String, Object?>();
void _keys(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.any((k) => !allowed.contains(k)))
    throw const FormatException('Unknown value program field');
}

final class _OperationInputs extends ListBase<Object?> {
  _OperationInputs(this.length, this.read);
  @override
  final int length;
  final Object? Function(int) read;
  @override
  Object? operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return read(index);
  }

  @override
  set length(int value) => throw UnsupportedError('Immutable operation inputs');
  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('Immutable operation inputs');
}
