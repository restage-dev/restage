import 'dart:collection';
import 'dart:convert';

import 'package:restage_shared/src/expressions/temporal_value_operations.dart'
    show dateTimeValueType, durationValueType;
import 'package:restage_shared/src/expressions/value_program.dart';

/// Fixed native operations over finite, compiler-admitted collections.
const Map<String, ValueOperation> kCollectionValueOperations = {
  'collection.map': _CollectionOperation('map'),
  'collection.where': _CollectionOperation('where'),
  'collection.take': _CollectionOperation('take'),
  'collection.skip': _CollectionOperation('skip'),
  'collection.takeWhile': _CollectionOperation('takeWhile'),
  'collection.skipWhile': _CollectionOperation('skipWhile'),
  'collection.reversed': _CollectionOperation('reversed'),
  'collection.copy': _CollectionOperation('copy'),
  'collection.toList': _CollectionOperation('toList'),
  'collection.length': _CollectionOperation('length'),
  'collection.isEmpty': _CollectionOperation('isEmpty'),
  'collection.isNotEmpty': _CollectionOperation('isNotEmpty'),
  'collection.first': _CollectionOperation('first'),
  'collection.last': _CollectionOperation('last'),
  'collection.single': _CollectionOperation('single'),
  'collection.elementAt': _CollectionOperation('elementAt'),
  'collection.any': _CollectionOperation('any'),
  'collection.every': _CollectionOperation('every'),
  'collection.contains': _CollectionOperation('contains'),
  'collection.indexOf': _CollectionOperation('indexOf'),
  'collection.lastIndexOf': _CollectionOperation('lastIndexOf'),
  'collection.indexWhere': _CollectionOperation('indexWhere'),
  'collection.lastIndexWhere': _CollectionOperation('lastIndexWhere'),
  'collection.firstWhere': _CollectionOperation('firstWhere'),
  'collection.lastWhere': _CollectionOperation('lastWhere'),
  'collection.singleWhere': _CollectionOperation('singleWhere'),
  'collection.fold': _CollectionOperation('fold'),
  'collection.reduce': _CollectionOperation('reduce'),
  'collection.join': _CollectionOperation('join'),
  'collection.sort': _CollectionOperation('sort'),
  'collection.compareTo': _CollectionOperation('compareTo'),
  'collection.concat': _CollectionOperation('concat'),
  'collection.expand': _CollectionOperation('expand'),
};

final Expando<bool> _ownedLists = Expando<bool>();
final Expando<Map<String, Object>> _borrowedLists =
    Expando<Map<String, Object>>();

/// Shapes with a native generic representation at collection boundaries.
bool isNativeCollectionItem(ValueType type) => switch (type.kind) {
      'int' || 'double' || 'num' || 'bool' || 'String' || 'Null' => true,
      'list' => type.item != null && isNativeCollectionItem(type.item!),
      'record' => type.fields.values.every(isNativeCollectionItem),
      _ => false,
    };

Object? _reifyBorrowedValue(Object? value) {
  if (value is! ValueListView) return value;
  final views = _borrowedLists[value.reader] ??= {};
  final key = jsonEncode([value.path, value.item.toJson()]);
  return views.putIfAbsent(key,
      () => withValueType(value.item, <T>() => _TypedBorrowedList<T>(value)));
}

final class _TypedBorrowedList<T> extends ListBase<T> {
  _TypedBorrowedList(this.source);
  final ValueListView source;
  @override
  int get length => source.length;
  @override
  set length(int value) => source.length = value;
  @override
  T operator [](int index) => _reifyBorrowedValue(source[index]) as T;
  @override
  void operator []=(int index, T value) => source[index] = value;
}

/// Reifies the closed scalar/collection type at a native generic boundary.
R withValueType<R>(ValueType type, R Function<T>() action) {
  switch (type.kind) {
    case 'int':
      return type.nullable ? action<int?>() : action<int>();
    case 'double':
      return type.nullable ? action<double?>() : action<double>();
    case 'num':
      return type.nullable ? action<num?>() : action<num>();
    case 'bool':
      return type.nullable ? action<bool?>() : action<bool>();
    case 'String':
      return type.nullable ? action<String?>() : action<String>();
    case 'Null':
      return action<Null>();
    case 'record':
      return type.nullable
          ? action<Map<String, Object?>?>()
          : action<Map<String, Object?>>();
    case 'list':
      return withValueType(type.item!,
          <T>() => type.nullable ? action<List<T>?>() : action<List<T>>());
    default:
      throw const FormatException('Unsupported native collection item');
  }
}

/// Constructs a native typed list while retaining its explicit mutability.
Object typedValueList(Iterable<Object?> values, ValueType item,
        {bool growable = true}) =>
    withValueType(item, <T>() {
      final result =
          List<T>.from(values.map(_reifyBorrowedValue), growable: growable);
      _ownedLists[result] = true;
      return result;
    });

/// Invokes a closed callback with a fresh cache and its live enclosing frame.
Object? invokeClosedValueCallback(ValueProgram program,
        Map<String, Object?> parameters, ValueOperationContext context) =>
    ValueEvaluator(program,
            captures: const _NoCaptures(),
            parameters: parameters,
            operations: context.operations,
            context: context.nested())
        .evaluate();

Object? _invokeCollectionCallback(ValueProgram program, List<Object?> arguments,
        List<Object?> captures, ValueOperationContext context) =>
    invokeClosedValueCallback(
        program,
        {
          for (var i = 0; i < arguments.length; i++)
            callbackParameterName(i): arguments[i],
          for (var i = 0; i < captures.length; i++) 'outer$i': captures[i],
        },
        context);

final class _NoCaptures implements ValueReader {
  const _NoCaptures();
  @override
  int length(List<Object> path) =>
      throw StateError('Undeclared collection capture');
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Undeclared collection capture');
}

final class _CollectionOperation implements RegistryValueOperation {
  const _CollectionOperation(this.method);
  final String method;
  @override
  String get name => 'collection.$method';
  @override
  int get capability => 24;

  Map<String, Object?> _options(Object? options) {
    if (options is! Map)
      throw const FormatException('Missing collection descriptor');
    final result = options.cast<String, Object?>();
    if (result.keys.any(
        (k) => !{'arguments', 'callbacks', 'item', 'equality'}.contains(k)))
      throw const FormatException('Unknown collection descriptor');
    return result;
  }

  List<Map<String, Object?>> _callbacks(Map<String, Object?> options) =>
      (options['callbacks']! as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  ValueProgram _program(
          Map<String, Object?> callback, ValueOperationContext context) =>
      ValueProgram.decode(callback['program']! as String,
          operations: context.operations, context: context.nested());

  @override
  Iterable<ValueProgram> nestedPrograms(
          ValueNode node, ValueOperationContext context) =>
      _callbacks(_options(node.value)).map((c) => _program(c, context));
  @override
  void validate(ValueNode node, List<ValueType> inputs) => validateWithContext(
      node,
      inputs,
      const ValueOperationContext(operations: kCollectionValueOperations));
  @override
  void validateWithContext(
      ValueNode node, List<ValueType> inputs, ValueOperationContext context) {
    final options = _options(node.value);
    final arguments = (options['arguments']! as List).cast<int>();
    final callbacks = _callbacks(options);
    void require(bool condition) {
      if (!condition) throw FormatException('Invalid $name descriptor');
    }

    require(inputs.isNotEmpty && node.name == null);
    final receiver = inputs.first;
    final item = receiver.item;
    require(!receiver.nullable);
    require(arguments.every((i) => i > 0 && i < inputs.length));
    if (method == 'compareTo') {
      require((receiver.numeric || receiver.kind == 'String') &&
          arguments.length == 1 &&
          callbacks.isEmpty &&
          (receiver.numeric
              ? inputs[arguments.single].numeric
              : inputs[arguments.single].kind == 'String') &&
          !inputs[arguments.single].nullable &&
          node.type.kind == 'int' &&
          !node.type.nullable);
      return;
    }
    require({'list', 'iterable'}.contains(receiver.kind) &&
        item != null &&
        isNativeCollectionItem(item));
    if ({
      'reversed',
      'indexOf',
      'lastIndexOf',
      'indexWhere',
      'lastIndexWhere',
      'sort'
    }.contains(method)) require(receiver.kind == 'list');
    final used = <int>{0};
    for (final index in arguments) {
      require(index > 0 && index < inputs.length && used.add(index));
    }
    final callbackTypes = <ValueType>[];
    for (final callback in callbacks) {
      require(callback.keys.every({'program', 'bindings'}.contains));
      final program = _program(callback, context);
      require(program.captures.isEmpty);
      final bindings = (callback['bindings']! as List).cast<int>();
      for (var i = 0; i < bindings.length; i++) {
        final index = bindings[i];
        require(index > 0 && index < inputs.length && used.add(index));
        require(program.parameters['outer$i']?.accepts(inputs[index]) == true);
      }
      final ordinal = callbackTypes.length;
      final parameterTypes = ordinal == 1
          ? <ValueType>[]
          : switch (method) {
              'fold' => [node.type, item!],
              'reduce' || 'sort' => [item!, item],
              _ => [item!],
            };
      require(
          program.parameters.length == parameterTypes.length + bindings.length);
      for (var i = 0; i < parameterTypes.length; i++) {
        require(program.parameters[callbackParameterName(i)]
                ?.accepts(parameterTypes[i]) ==
            true);
      }
      callbackTypes.add(program.nodes[program.root].type);
    }
    require(used.length == inputs.length);
    final predicate = {
      'where',
      'takeWhile',
      'skipWhile',
      'any',
      'every',
      'indexWhere',
      'lastIndexWhere',
      'firstWhere',
      'lastWhere',
      'singleWhere'
    }.contains(method);
    final callbackRequired =
        predicate || {'map', 'expand', 'fold', 'reduce'}.contains(method);
    final orElse = {'firstWhere', 'lastWhere', 'singleWhere'}.contains(method);
    require(callbacks.length == (callbackRequired ? 1 : 0) ||
        (orElse && callbacks.length == 2) ||
        (method == 'sort' && callbacks.length == 1));
    if (predicate) require(ValueType.boolean.accepts(callbackTypes.first));
    if (callbacks.length == 2) require(item!.accepts(callbackTypes.last));
    final expectedArguments = switch (method) {
      'take' ||
      'skip' ||
      'elementAt' ||
      'contains' ||
      'fold' ||
      'toList' ||
      'copy' =>
        1,
      'indexOf' || 'lastIndexOf' => 2,
      'indexWhere' || 'lastIndexWhere' || 'join' => 1,
      'concat' => arguments.length,
      _ => 0,
    };
    require(arguments.length == expectedArguments);
    ValueType argument(int i) => inputs[arguments[i]];
    if ({'take', 'skip', 'elementAt', 'indexWhere', 'lastIndexWhere'}
        .contains(method))
      require(ValueType.integer.accepts(argument(0)) ||
          (method == 'lastIndexWhere' && argument(0).kind == 'Null'));
    if ({'indexOf', 'lastIndexOf'}.contains(method))
      require(ValueType.integer.accepts(argument(1)) ||
          (method == 'lastIndexOf' && argument(1).kind == 'Null'));
    final equality = options['equality'];
    if (equality != null) {
      require({'contains', 'indexOf', 'lastIndexOf'}.contains(method));
      final shape = switch (equality) {
        'datetime' => dateTimeValueType,
        'duration' => durationValueType,
        _ => throw const FormatException('Unknown collection equality domain'),
      };
      require(shape.accepts(item!.nonNull) && item.nonNull.accepts(shape));
      require(argument(0).kind == 'Null' ||
          shape.accepts(argument(0).nonNull) &&
              argument(0).nonNull.accepts(shape));
    } else if ({'contains', 'indexOf', 'lastIndexOf'}.contains(method)) {
      require({'int', 'double', 'num', 'String', 'bool', 'Null'}
              .contains(item!.kind) &&
          {'int', 'double', 'num', 'String', 'bool', 'Null'}
              .contains(argument(0).kind));
    }
    if (method == 'join')
      require(ValueType.string.accepts(argument(0)) &&
          {'int', 'double', 'num', 'String', 'bool', 'Null'}
              .contains(item!.kind));
    if (method == 'toList' || method == 'copy')
      require(ValueType.boolean.accepts(argument(0)));
    if (method == 'fold')
      require(node.type.accepts(argument(0)) &&
          node.type.accepts(callbackTypes.single));
    if (method == 'expand')
      require(callbackTypes.single.kind == 'list' &&
          !callbackTypes.single.nullable);
    if (method == 'reduce') require(item!.accepts(callbackTypes.single));
    if (method == 'sort')
      require(callbacks.isEmpty
          ? item!.numeric || item.kind == 'String'
          : ValueType.integer.accepts(callbackTypes.single));
    if (method == 'concat')
      for (final index in arguments) {
        require({'list', 'iterable'}.contains(inputs[index].kind) &&
            item!.accepts(inputs[index].item!));
      }
    if (method == 'map')
      require(node.type.kind == 'iterable' &&
          !node.type.nullable &&
          node.type.item!.accepts(callbackTypes.single));
    if (method == 'copy')
      require(node.type.kind == 'list' && !node.type.nullable);
    final expected = switch (method) {
      'map' => node.type,
      'where' ||
      'take' ||
      'skip' ||
      'takeWhile' ||
      'skipWhile' ||
      'reversed' =>
        ValueType('iterable', item: item),
      'copy' => node.type,
      'toList' || 'concat' => ValueType('list', item: item),
      'expand' => ValueType('list', item: callbackTypes.single.item),
      'length' ||
      'indexOf' ||
      'lastIndexOf' ||
      'indexWhere' ||
      'lastIndexWhere' =>
        ValueType.integer,
      'isEmpty' ||
      'isNotEmpty' ||
      'any' ||
      'every' ||
      'contains' =>
        ValueType.boolean,
      'join' => ValueType.string,
      'sort' => ValueType.nullType,
      'fold' => node.type,
      _ => item!,
    };
    require(expected.accepts(node.type) && node.type.accepts(expected));
    final runtimeItem =
        ValueType.fromJson((options['item']! as Map).cast<String, Object?>());
    final materializedItem = {'copy', 'map'}.contains(method)
        ? node.type.item!
        : method == 'expand'
            ? callbackTypes.single.item!
            : item!;
    require(isNativeCollectionItem(runtimeItem));
    require(runtimeItem.accepts(materializedItem) &&
        materializedItem.accepts(runtimeItem));
  }

  @override
  Object? evaluate(List<Object?> inputs, Object? options) =>
      evaluateWithContext(inputs, options,
          const ValueOperationContext(operations: kCollectionValueOperations));
  @override
  Object? evaluateWithContext(
      List<Object?> inputs, Object? options, ValueOperationContext context) {
    // Demand all call operands in their authored order before invoking Dart.
    final values = inputs.toList();
    final descriptor = _options(options);
    final args = (descriptor['arguments']! as List)
        .cast<int>()
        .map((i) => values[i])
        .toList();
    final callbacks = _callbacks(descriptor);
    final programs = callbacks.map((c) => _program(c, context)).toList();
    Object? call(int index, List<Object?> arguments) =>
        _invokeCollectionCallback(
            programs[index],
            arguments,
            (callbacks[index]['bindings']! as List)
                .cast<int>()
                .map((i) => values[i])
                .toList(),
            context);
    if (method == 'compareTo')
      return values.first is String
          ? (values.first! as String).compareTo(args.single! as String)
          : (values.first! as num).compareTo(args.single! as num);
    final source = _reifyBorrowedValue(values.first)! as Iterable<Object?>;
    bool predicate(Object? item) => call(0, [item])! as bool;
    final item = ValueType.fromJson(
        (descriptor['item']! as Map).cast<String, Object?>());
    if (descriptor['equality'] case final String domain) {
      Object? native(Object? value) {
        if (value == null) return null;
        final record = value as Map<String, Object?>;
        return domain == 'datetime'
            ? DateTime.fromMicrosecondsSinceEpoch(
                record['microsecondsSinceEpoch']! as int,
                isUtc: record['isUtc']! as bool)
            : Duration(microseconds: record['microseconds']! as int);
      }

      final target = native(args.first);
      bool equals(Object? value) => native(value) == target;
      return switch (method) {
        'contains' => source.any(equals),
        'indexOf' =>
          (source as List<Object?>).indexWhere(equals, args[1]! as int),
        'lastIndexOf' =>
          (source as List<Object?>).lastIndexWhere(equals, args[1] as int?),
        _ =>
          throw const FormatException('Invalid collection equality operation'),
      };
    }
    switch (method) {
      case 'map':
        return withValueType(
            item,
            <T>() =>
                source.map<T>((v) => _reifyBorrowedValue(call(0, [v])) as T));
      case 'expand':
        return typedValueList(
            source.expand((v) => call(0, [v])! as Iterable<Object?>), item);
      case 'where':
        return withValueType(item, <T>() => source.cast<T>().where(predicate));
      case 'take':
        return withValueType(
            item, <T>() => source.cast<T>().take(args.single! as int));
      case 'skip':
        return withValueType(
            item, <T>() => source.cast<T>().skip(args.single! as int));
      case 'takeWhile':
        return withValueType(
            item, <T>() => source.cast<T>().takeWhile(predicate));
      case 'skipWhile':
        return withValueType(
            item, <T>() => source.cast<T>().skipWhile(predicate));
      case 'reversed':
        return withValueType(
            item, <T>() => (source as List<Object?>).cast<T>().reversed);
      case 'copy':
      case 'toList':
        return typedValueList(source, item, growable: args.single! as bool);
      case 'concat':
        return typedValueList([
          ...source,
          for (final arg in args) ...(arg as Iterable<Object?>?) ?? const []
        ], item);
      case 'length':
        return source.length;
      case 'isEmpty':
        return source.isEmpty;
      case 'isNotEmpty':
        return source.isNotEmpty;
      case 'first':
        return source.first;
      case 'last':
        return source.last;
      case 'single':
        return source.single;
      case 'elementAt':
        return source.elementAt(args.single! as int);
      case 'any':
        return source.any(predicate);
      case 'every':
        return source.every(predicate);
      case 'contains':
        return source.contains(args.single);
      case 'indexOf':
        return (source as List<Object?>).indexOf(args[0], args[1]! as int);
      case 'lastIndexOf':
        return (source as List<Object?>).lastIndexOf(args[0], args[1] as int?);
      case 'indexWhere':
        return (source as List<Object?>)
            .indexWhere(predicate, args.single! as int);
      case 'lastIndexWhere':
        return (source as List<Object?>)
            .lastIndexWhere(predicate, args.single as int?);
      case 'firstWhere':
        return withValueType(
            item,
            <T>() => source.cast<T>().firstWhere(predicate,
                orElse: callbacks.length == 2
                    ? () => _reifyBorrowedValue(call(1, [])) as T
                    : null));
      case 'lastWhere':
        return withValueType(
            item,
            <T>() => source.cast<T>().lastWhere(predicate,
                orElse: callbacks.length == 2
                    ? () => _reifyBorrowedValue(call(1, [])) as T
                    : null));
      case 'singleWhere':
        return withValueType(
            item,
            <T>() => source.cast<T>().singleWhere(predicate,
                orElse: callbacks.length == 2
                    ? () => _reifyBorrowedValue(call(1, [])) as T
                    : null));
      case 'fold':
        return _reifyBorrowedValue(
            source.fold<Object?>(args.single, (a, b) => call(0, [a, b])));
      case 'reduce':
        return withValueType(
            item,
            <T>() => source
                .cast<T>()
                .reduce((a, b) => _reifyBorrowedValue(call(0, [a, b])) as T));
      case 'join':
        return source.join(args.single! as String);
      case 'sort':
        if (_ownedLists[source] != true)
          throw StateError('Sort requires an explicit fresh list');
        (source as List<Object?>)
            .sort(callbacks.isEmpty ? null : (a, b) => call(0, [a, b])! as int);
        return null;
      default:
        throw StateError('Unknown collection operation');
    }
  }
}
