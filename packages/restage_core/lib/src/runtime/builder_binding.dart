import 'dart:collection';
import 'dart:convert';
import 'package:restage_core/src/runtime/intl_value_operations.dart';

import 'package:flutter/widgets.dart';
import 'package:restage_core/src/runtime/builder_context.dart';
import 'package:restage_core/src/runtime/native_values.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart';

part 'builder_binding_lifetime.dart';
part 'builder_continuation.dart';
part 'builder_context_scope.dart';

const Map<String, ValueOperation> _defaultValueOperations = {
  ...kCollectionValueOperations,
  ...kGridValueOperations,
  ...kNativeIntlValueOperations,
};

/// Binds a typed callback program to an RFW slot.
final class RestageBuilderBinding {
  RestageBuilderBinding(DataSource source, List<Object> path,
      {this.contract,
      this.scalarContract,
      BuildContext? context,
      Map<String, ValueOperation> operations = _defaultValueOperations})
      : operations = _nativeOperations(source, context, operations),
        _nativeBindings = _nativeBindingsOf(source, context),
        _parentFrame = _lexicalContext(
                context ?? (source is _ValueDataSource ? source.context : null),
                operations,
                source: source)
            .frame,
        _continuation = _BuilderContinuation(source.child(path));

  RestageBuilderBinding._(Widget helper,
      {ValueLocalFrame? parentFrame,
      Map<String, NativeBinding<Object?>> nativeBindings = const {},
      this.contract,
      this.scalarContract,
      this.operations = _defaultValueOperations})
      : _nativeBindings = nativeBindings,
        _parentFrame = parentFrame,
        _continuation = _BuilderContinuation(helper);

  final WidgetBuilderContract? contract;
  final ScalarCallbackContract? scalarContract;
  final Map<String, ValueOperation> operations;
  final _BuilderContinuation _continuation;
  final ValueLocalFrame? _parentFrame;
  final Map<String, NativeBinding<Object?>> _nativeBindings;
  ValueOperationContext get _operationContext => ValueOperationContext(
      operations: operations,
      locals: _parentFrame?.visibleTypes ?? {},
      frame: _parentFrame);

  /// Binds a present callback without constructing an absent one.
  static RestageBuilderBinding? optional(DataSource source, List<Object> path,
      {WidgetBuilderContract? contract,
      BuildContext? context,
      ScalarCallbackContract? scalarContract,
      Map<String, ValueOperation> operations = _defaultValueOperations}) {
    operations = _nativeOperations(source, context, operations);
    final helper = source.optionalChild(path);
    if (helper == null &&
        (source.isMap(path) ||
            source.isList(path) ||
            source.v<bool>(path) != null ||
            source.v<int>(path) != null ||
            source.v<double>(path) != null ||
            source.v<String>(path) != null)) {
      throw const FormatException('Expected a callback continuation or null');
    }
    return helper == null
        ? null
        : RestageBuilderBinding._(helper,
            nativeBindings: _nativeBindingsOf(source, context),
            parentFrame: _lexicalContext(
                    context ??
                        (source is _ValueDataSource ? source.context : null),
                    operations,
                    source: source)
                .frame,
            contract: contract,
            scalarContract: scalarContract,
            operations: operations);
  }

  /// Owns the bindings for an already constructed native widget.
  static Widget retain(List<RestageBuilderBinding> bindings,
          {required Widget child}) =>
      _BuilderBindingLifetime(
          bindings: List.unmodifiable(bindings), child: child);

  /// Releases initialized bindings when native construction fails.
  static Widget construct(
      Widget Function(List<RestageBuilderBinding> bindings) create) {
    final bindings = <RestageBuilderBinding>[];
    try {
      final child = create(bindings);
      return bindings.isEmpty ? child : retain(bindings, child: child);
    } catch (_) {
      for (final binding in bindings) {
        binding.dispose();
      }
      rethrow;
    }
  }

  Widget build(BuildContext context, Map<String, Object?> parameters) =>
      buildNullable(context, parameters) ??
      (throw StateError('Nonnullable widget builder returned null'));

  Widget? buildNullable(
          BuildContext context, Map<String, Object?> parameters) =>
      _continuation.invoke(
          context, (source) => _buildNullable(source, context, parameters));

  Widget? _buildNullable(DataSource source, BuildContext context,
      Map<String, Object?> parameters) {
    final program = _program(source, context);
    if (contract case final contract?) {
      validateBuilderProgramContract(program, contract);
    } else if (program.values.parameters
        .containsKey(callbackParameterName(0))) {
      throw const FormatException(
          'Native context requires a widget callback contract');
    }
    // Retain Flutter's argument before rendering introduces another context.
    if (program.values.parameters.containsKey(callbackParameterName(0))) {
      parameters = {
        ...parameters,
        callbackParameterName(0): NativeBinding<BuildContext>(
            contract: NativeBindingContract(
                type: builderContextNativeValueType.nativeType!),
            value: context),
      };
    }
    final contextFrame = _BuilderContextFrame.callback(context);
    final result = program.invoke(
        captures: _SourceReader(
            source, const ['captures'], context, _nativeBindings, _parentFrame),
        parameters: _ContextParameters(
            contextFrame, parameters, program.values.parameters.keys),
        operations: operations,
        context: _operationContext);
    return _render(source, result, contextFrame);
  }

  BuilderProgram _program(DataSource source, BuildContext context) {
    if (source.v<int>(const ['version']) != valueProgramVersion) {
      throw const FormatException('Unsupported builder slot version');
    }
    final encoded = source.v<String>(const ['program']);
    if (encoded == null) throw const FormatException('Missing builder program');
    final program = BuilderProgram.decode(encoded,
        operations: operations, context: _operationContext);
    if (!source.isList(const ['bodies']) ||
        source.length(const ['bodies']) != program.bodyCount) {
      throw const FormatException('Builder bodies do not match the program');
    }
    return program;
  }

  Widget? _render(DataSource source, BuilderInvocation result,
      _BuilderContextFrame contextFrame) {
    if (result.isNull) return null;
    final body = source.builder([
      'bodies',
      result.bodyIndex!
    ], <String, Object>{
      'values': <String, Object>{
        for (final entry in result.values.entries)
          if (entry.value != null && entry.value is! ValueNative)
            entry.key: entry.value!
      },
      'nulls': <String, Object>{
        for (final entry in result.values.entries)
          entry.key: entry.value == null
      }
    });
    final child = _BuilderContextScope(
        frame: _BuilderContextFrame(contextFrame.context, contextFrame.parent,
            result.frame, _nativeBindings),
        child: body);
    if (!result.hasKey) return child;
    final key = _projectedKey(result);
    return key == null ? child : KeyedSubtree(key: key, child: child);
  }

  Key? _projectedKey(BuilderInvocation result) {
    final value = result.projectedKey;
    if (result.keyType == 'nativeKey') {
      if (value == null) return null;
      if (value is! ValueNative ||
          value.contract.type != 'flutter.Key' ||
          value.contract.call != null ||
          value.value is! Key) {
        throw const FormatException('Invalid native key value');
      }
      return _NativeChildKey(value.value! as Key);
    }
    if (result.keyType == 'nativeBinding') {
      final reference = value as Map;
      if (reference['kind'] != 'nativeBinding' ||
          reference['type'] != 'flutter.Key') {
        throw const FormatException('Invalid native key reference');
      }
      final contract = NativeBindingContract(
          type: 'flutter.Key', nullable: reference['nullable'] as bool);
      final entry = _nativeBindings[reference['key'] as String];
      if (entry == null) {
        reportMissingNativeValue(null, reference['key'] as String);
      }
      if (entry == null || entry.contract != contract) {
        throw const FormatException(
            'Native key binding is unavailable or incompatible');
      }
      final key = entry.value;
      if (key == null && contract.nullable) return null;
      if (key is! Key)
        throw const FormatException(
            'Native key binding has the wrong Dart type');
      return _NativeChildKey(key);
    }
    return switch (result.keyType) {
      'String' => ValueKey<String>(value as String),
      'String?' => ValueKey<String?>(value as String?),
      'int' => ValueKey<int>(value as int),
      'int?' => ValueKey<int?>(value as int?),
      'double' => ValueKey<double>(value as double),
      'double?' => ValueKey<double?>(value as double?),
      'num' => ValueKey<num>(value as num),
      'num?' => ValueKey<num?>(value as num?),
      'bool' => ValueKey<bool>(value as bool),
      'bool?' => ValueKey<bool?>(value as bool?),
      'Object' => ValueKey<Object>(value as Object),
      'Object?' => ValueKey<Object?>(value),
      'dynamic' => ValueKey<dynamic>(value),
      'Null' => ValueKey<Null>(value as Null),
      _ => throw const FormatException('Unknown native key type'),
    };
  }

  /// Builds a finite child collection through the same continuation.
  List<Widget> buildList(
          BuildContext context, Map<String, Object?> parameters) =>
      _continuation.invoke(context, (source) {
        if (contract != null) {
          throw const FormatException('Widget callback cannot return a list');
        }
        final program = _program(source, context);
        final contextFrame = _BuilderContextFrame.borrow(context);
        final results = program.invokeAll(
            captures: _SourceReader(source, const ['captures'], context,
                _nativeBindings, _parentFrame),
            parameters: _ContextParameters(
                contextFrame, parameters, program.values.parameters.keys),
            operations: operations,
            context: _operationContext);
        return [
          for (final result in results) _render(source, result, contextFrame)!
        ];
      });

  /// Evaluates a scalar callback using the same subscription lifecycle.
  Object? evaluate(BuildContext context, Map<String, Object?> parameters) =>
      _continuation.invoke(
          context, (source) => _evaluateScalar(source, context, parameters));

  /// Recovers the native key before invoking a child-index callback.
  static Key originalKey(Key key) => key is _NativeChildKey ? key.value : key;

  /// Applies the callback's native ValueKey cast before projecting its value.
  Object? evaluateKey(BuildContext context, Key key) =>
      _continuation.invoke(context, (source) {
        final program = _scalarProgram(source, context);
        final parameter = program.parameters[callbackParameterName(0)];
        return _evaluateScalar(
            source,
            context,
            parameter == null
                ? const {}
                : {
                    callbackParameterName(0):
                        _NativeKeyProjection(originalKey(key), parameter.fields)
                  },
            program: program);
      });

  ValueProgram _scalarProgram(DataSource source, BuildContext context) {
    if (contract != null) {
      throw const FormatException('Widget callback cannot return a value');
    }
    if (source.v<int>(const ['version']) != valueProgramVersion) {
      throw const FormatException('Unsupported value slot version');
    }
    final encoded = source.v<String>(const ['program']);
    if (encoded == null) throw const FormatException('Missing scalar program');
    final program = ValueProgram.decode(encoded,
        operations: operations, context: _operationContext);
    if (scalarContract case final scalar?) {
      validateScalarCallbackProgramContract(program, scalar);
    }
    return program;
  }

  Object? _evaluateScalar(
      DataSource source, BuildContext context, Map<String, Object?> parameters,
      {ValueProgram? program}) {
    program ??= _scalarProgram(source, context);
    return RestageValueBinding(source, const [], operations: operations)
        ._evaluateProgram(
            program, context, parameters, _operationContext, _nativeBindings);
  }

  /// Releases subscriptions held by this callback.
  void dispose() => _continuation.dispose();

  /// Projects the actual callback constraints, preserving native infinity.
  static Map<String, Object?> constraints(BoxConstraints value) => {
        'minWidth': value.minWidth,
        'maxWidth': value.maxWidth,
        'minHeight': value.minHeight,
        'maxHeight': value.maxHeight,
        'hasBoundedWidth': value.hasBoundedWidth,
        'hasBoundedHeight': value.hasBoundedHeight,
        'hasTightWidth': value.hasTightWidth,
        'hasTightHeight': value.hasTightHeight,
        'isTight': value.isTight,
        'biggest': {
          'width': value.biggest.width,
          'height': value.biggest.height
        },
        'smallest': {
          'width': value.smallest.width,
          'height': value.smallest.height
        },
      };
}

/// Uses the callback expression engine for ordinary constructor values.
final class RestageValueBinding {
  RestageValueBinding(this.source, this.path,
      {this.operations = _defaultValueOperations});

  final DataSource source;
  final List<Object> path;
  final Map<String, ValueOperation> operations;

  /// Decodes scalar expressions throughout native constructor value readers.
  static DataSource dataSource(DataSource source, BuildContext context,
          {Map<String, ValueOperation> operations = _defaultValueOperations}) =>
      source is _ValueDataSource &&
              identical(source.context, context) &&
              (identical(source.requestedOperations, operations) ||
                  identical(source.operations, operations))
          ? source
          : _ValueDataSource(source, context, operations);

  /// Whether this slot carries an installed native object or native program.
  static bool isNativeValue(DataSource source, List<Object> path) {
    final raw = _rawValueSource(source);
    if (!raw.isMap(path)) return false;
    final kind = raw.v<String>([...path, 'kind']);
    if (kind == 'nativeBinding' || kind == 'nativeLocal') return true;
    final encoded = raw.v<String>([...path, 'program']);
    if (encoded == null) return false;
    if (source is! _ValueDataSource) {
      throw const FormatException(
          'Computed values require a bound data source');
    }
    final program = ValueProgram.decode(encoded,
        operations: source.operations,
        context: ValueOperationContext(
            operations: source.operations,
            frame: source.frame,
            locals: source.frame?.visibleTypes ?? const {}));
    return program.nodes[program.root].type.kind == 'native';
  }

  /// Reads through the context and lexical frame retained by a factory source.
  static T? readNativeFromSource<T extends Object>(
      DataSource source, List<Object> path,
      {required String type}) {
    if (source is! _ValueDataSource) {
      throw const FormatException('Native values require a bound data source');
    }
    return readNative<T>(source, path, source.context, type: type);
  }

  /// Reads an installed object without transporting it through RFW data.
  static T? readNative<T extends Object>(
      DataSource source, List<Object> path, BuildContext context,
      {required String type}) {
    final value = _readNativeValue(source, path, context, type: type);
    final native = value?.value;
    if (native == null) return null;
    if (native is! T)
      throw FormatException('Native value at $path has the wrong Dart type');
    return native;
  }

  static ValueNative? _readNativeValue(
      DataSource source, List<Object> path, BuildContext context,
      {required String type,
      bool nullable = false,
      Map<String, NativeBinding<Object?>>? bindings,
      ValueLocalFrame? lexicalFrame}) {
    final raw = _rawValueSource(source);
    if (!raw.isMap(path)) {
      if (nullable &&
          !raw.isList(path) &&
          raw.v<String>(path) == null &&
          raw.v<bool>(path) == null &&
          raw.v<int>(path) == null &&
          raw.v<double>(path) == null) return null;
      throw FormatException('Expected native reference at $path');
    }
    Object? value;
    if (raw.v<String>([...path, 'program']) case final encoded?) {
      bindings ??= _nativeBindingsOf(source, context);
      lexicalFrame ??= source is _ValueDataSource
          ? source.frame
          : _BuilderContextScope.maybeOf(context)?.locals;
      final operations = RestageNativeValues.operationsOf(
          context,
          source is _ValueDataSource
              ? source.operations
              : _defaultValueOperations,
          bindings: bindings);
      final lexicalContext = ValueOperationContext(
          operations: operations,
          frame: lexicalFrame,
          locals: lexicalFrame?.visibleTypes ?? const {});
      final program = ValueProgram.decode(encoded,
          operations: operations, context: lexicalContext);
      final resultType = program.nodes[program.root].type;
      if (resultType.kind != 'native' || resultType.nativeType != type) {
        throw const FormatException(
            'Computed native value has the wrong result type');
      }
      value = source is _ValueDataSource
          ? source._computed(path)
          : RestageValueBinding(raw, path, operations: operations).evaluate(
              context,
              lexicalContext: lexicalContext,
              nativeBindings: bindings);
    } else {
      final kind = raw.v<String>([...path, 'kind']);
      final nullable = raw.v<bool>([...path, 'nullable']);
      if (raw.v<String>([...path, 'type']) != type || nullable == null) {
        throw FormatException('Invalid native reference at $path');
      }
      final contract = NativeBindingContract(type: type, nullable: nullable);
      if (kind == 'nativeBinding') {
        final key = raw.v<String>([...path, 'key']);
        if (key == null)
          throw const FormatException('Missing native binding key');
        final entry = (bindings ?? _nativeBindingsOf(source, context))[key];
        if (entry == null) reportMissingNativeValue(context, key);
        if (entry == null || entry.contract != contract) {
          throw FormatException(
              'Native binding "$key" is unavailable or incompatible');
        }
        value = entry.value == null ? null : entry;
      } else if (kind == 'nativeLocal') {
        final slot = raw.v<String>([...path, 'slot']);
        final frame = lexicalFrame ??
            (source is _ValueDataSource
                ? source.frame
                : _BuilderContextScope.maybeOf(context)?.locals);
        final localType = frame?.visibleTypes[slot];
        final expected = ValueType.native(type, nullable: nullable);
        if (slot == null ||
            frame == null ||
            localType == null ||
            !expected.accepts(localType) ||
            !localType.accepts(expected)) {
          throw const FormatException(
              'Native local is outside its declared scope');
        }
        value = frame.read(slot);
      } else {
        throw const FormatException('Unknown native reference');
      }
    }
    if (value == null) return null;
    if (value is! ValueNative ||
        value.contract.type != type ||
        value.contract.call != null ||
        value.value == null) {
      throw const FormatException(
          'Computed native value has the wrong declaration');
    }
    return value;
  }

  static T? read<T extends Object>(
          DataSource source, List<Object> path, BuildContext? context,
          {Map<String, ValueOperation> operations = _defaultValueOperations}) =>
      _read<T>(source, path, context, operations, strict: true);

  static T? _read<T extends Object>(DataSource source, List<Object> path,
      BuildContext? context, Map<String, ValueOperation> operations,
      {required bool strict}) {
    if (source is _ValueDataSource) {
      if ((context == null || identical(context, source.context)) &&
          (identical(operations, _defaultValueOperations) ||
              identical(operations, source.requestedOperations) ||
              identical(operations, source.operations))) {
        return source.readValue<T>(path, strict: strict);
      }
      return _ValueDataSource(source, context ?? source.context, operations)
          .readValue<T>(path, strict: strict);
    }

    if (!source.isMap(path) || source.v<String>([...path, 'program']) == null) {
      return source.v<T>(path);
    }
    final result = RestageValueBinding(source, path, operations: operations)
        .evaluate(context);
    if (result == null) return null;
    if (result is! T) {
      if (strict) throw StateError('Computed value does not match $T');
      return null;
    }
    return result;
  }

  Object? evaluate(BuildContext? context,
      {Map<String, Object?> parameters = const {},
      ValueOperationContext? lexicalContext,
      Map<String, NativeBinding<Object?>>? nativeBindings}) {
    nativeBindings ??= _nativeBindingsOf(source, context);
    final operations = lexicalContext?.operations ??
        (context == null
            ? this.operations
            : RestageNativeValues.operationsOf(context, this.operations,
                bindings: nativeBindings));
    lexicalContext ??= _lexicalContext(context, operations, source: source);
    final encoded = source.v<String>([...path, 'program']);
    if (encoded == null) throw const FormatException('Missing value program');
    if (source.v<int>([...path, 'version']) != valueProgramVersion) {
      throw const FormatException('Unsupported value slot version');
    }
    final program = ValueProgram.decode(encoded,
        operations: operations, context: lexicalContext);
    return _evaluateProgram(
        program, context, parameters, lexicalContext, nativeBindings);
  }

  Object? _evaluateProgram(
          ValueProgram program,
          BuildContext? context,
          Map<String, Object?> parameters,
          ValueOperationContext lexicalContext,
          Map<String, NativeBinding<Object?>> nativeBindings) =>
      ValueEvaluator(program,
              captures: _SourceReader(
                  _rawValueSource(source),
                  [...path, 'captures'],
                  context,
                  nativeBindings,
                  lexicalContext.frame),
              parameters: _ContextParameters(
                  context == null ? null : _BuilderContextFrame.borrow(context),
                  parameters,
                  program.parameters.keys),
              operations: lexicalContext.operations,
              context: lexicalContext)
          .evaluate();
}

final class _ValueDataSource implements DataSource {
  _ValueDataSource(
      DataSource source, this.context, Map<String, ValueOperation> operations)
      : source = _rawValueSource(source),
        requestedOperations = operations,
        operations = _nativeOperations(source, context, operations),
        nativeBindings = _nativeBindingsOf(source, context),
        frame = source is _ValueDataSource
            ? source.frame
            : _BuilderContextScope.maybeOf(context)?.locals;
  final Map<String, ValueOperation> requestedOperations;
  final Map<String, NativeBinding<Object?>> nativeBindings;
  final ValueLocalFrame? frame;
  final DataSource source;
  final BuildContext context;
  final Map<String, ValueOperation> operations;
  final Map<String, Object?> _values = {};
  bool _isComputed(List<Object> path) =>
      source.isMap(path) && source.v<String>([...path, 'program']) != null;

  Object? _computed(List<Object> path) {
    final key = jsonEncode(path);
    if (!_values.containsKey(key)) {
      _values[key] = RestageValueBinding(source, path, operations: operations)
          .evaluate(context,
              nativeBindings: nativeBindings,
              lexicalContext: ValueOperationContext(
                  operations: operations,
                  frame: frame,
                  locals: frame?.visibleTypes ?? const {}));
    }
    final value = _values[key];
    // Ordinary constructor envelopes project scalars. Aggregate builder values
    // travel as native RFW frame data, not as an object-valued slot envelope.
    if (value is Map || value is List) {
      throw const FormatException('Computed constructor values must be scalar');
    }
    return value;
  }

  T? readValue<T extends Object>(List<Object> path, {required bool strict}) {
    if (!_isComputed(path)) return source.v<T>(path);
    final value = _computed(path);
    if (value is ValueNative) {
      if (strict) throw StateError('Native values require the native reader');
      return null;
    }
    if (value == null || value is T) return value as T?;
    if (strict) throw StateError('Computed value does not match $T');
    return null;
  }

  @override
  T? v<T extends Object>(List<Object> path) =>
      readValue<T>(path, strict: false);
  @override
  bool isMap(List<Object> path) {
    if (!_isComputed(path)) return source.isMap(path);
    _computed(path);
    return false;
  }

  @override
  bool isList(List<Object> path) {
    if (!_isComputed(path)) return source.isList(path);
    _computed(path);
    return false;
  }

  @override
  int length(List<Object> path) {
    if (!_isComputed(path)) return source.length(path);
    _computed(path);
    return 0;
  }

  @override
  Widget child(List<Object> path) => source.child(path);
  @override
  Widget? optionalChild(List<Object> path) => source.optionalChild(path);
  @override
  List<Widget> childList(List<Object> path) => source.childList(path);
  @override
  Widget builder(List<Object> path, DynamicMap arguments) =>
      source.builder(path, arguments);
  @override
  Widget? optionalBuilder(List<Object> path, DynamicMap arguments) =>
      source.optionalBuilder(path, arguments);
  @override
  T? handler<T extends Function>(
          List<Object> path, HandlerGenerator<T> generator) =>
      source.handler<T>(path, generator);
  @override
  VoidCallback? voidHandler(List<Object> path, [DynamicMap? arguments]) {
    if (!source.isMap(path) || !source.isMap([...path, 'nativeEvent'])) {
      return source.voidHandler(path, arguments);
    }
    final callback = RestageValueBinding.readNative<VoidCallback>(
      this,
      [...path, 'nativeEvent'],
      context,
      type: kNativeVoidCallbackType,
    );
    if (callback == null) return null;
    final measure = source.voidHandler([...path, 'measurement'], arguments);
    if (measure == null) return callback;
    return () {
      callback();
      measure();
    };
  }
}

final class _SourceReader implements ValueReader {
  const _SourceReader(this.source, this.prefix,
      [this.context, this.nativeBindings, this.lexicalFrame]);
  final Map<String, NativeBinding<Object?>>? nativeBindings;
  final ValueLocalFrame? lexicalFrame;
  final BuildContext? context;
  final DataSource source;
  final List<Object> prefix;
  @override
  int length(List<Object> path) {
    final full = [...prefix, ...path];
    if (!source.isList(full)) throw StateError('Expected list at $path');
    return source.length(full);
  }

  @override
  Object? read(List<Object> path, ValueType type) {
    final full = [...prefix, ...path];
    final Object? result = switch (type.kind) {
      'bool' => source.v<bool>(full),
      'int' => source.v<int>(full),
      'double' => source.v<double>(full),
      'num' => source.v<double>(full) ?? source.v<int>(full),
      'String' => source.v<String>(full),
      'Null' => null,
      'native' => RestageValueBinding._readNativeValue(source, full,
          context ?? (throw StateError('Native capture requires context')),
          type: type.nativeType!,
          nullable: type.nullable,
          bindings: nativeBindings,
          lexicalFrame: lexicalFrame),
      'record' =>
        source.isMap(full) ? ValueRecordView(this, path, type.fields) : null,
      'list' =>
        source.isList(full) ? ValueListView(this, path, type.item!) : null,
      _ => throw FormatException('Unknown capture type ${type.kind}'),
    };
    if (result == null && !type.nullable) {
      throw StateError('Missing or incorrectly typed capture $path');
    }
    return result;
  }
}

final class _ContextParameters extends MapBase<String, Object?> {
  _ContextParameters(this.contextFrame, this.native, this.declared);
  final _BuilderContextFrame? contextFrame;
  final Map<String, Object?> native;
  final Iterable<String> declared;
  @override
  Iterable<String> get keys => {...native.keys, ...declared};
  @override
  Object? operator [](Object? key) {
    if (key is! String || !key.startsWith('context:')) return native[key];
    final location = builderContextLocation(key);
    if (location == null || builderContextValueType(key) == null) {
      throw FormatException('Unknown native context projection $key');
    }
    return readBuilderContext(
        (contextFrame ??
                (throw StateError('A context value requires BuildContext')))
            .at(location.ancestorDepth),
        location.name);
  }

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Immutable callback frame');
  @override
  void clear() => throw UnsupportedError('Immutable callback frame');
  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Immutable callback frame');
}

DataSource _rawValueSource(DataSource source) {
  while (source is _ValueDataSource) source = source.source;
  return source;
}

final class _NativeKeyProjection extends MapBase<String, Object?> {
  _NativeKeyProjection(this.key, this.fields);
  final Key key;
  final Map<String, ValueType> fields;
  final Map<String, Object?> _values = {};
  Object? _read(ValueType type) => switch ((type.kind, type.nullable)) {
        ('String', false) => (key as ValueKey<String>).value,
        ('String', true) => (key as ValueKey<String?>).value,
        ('int', false) => (key as ValueKey<int>).value,
        ('int', true) => (key as ValueKey<int?>).value,
        ('double', false) => (key as ValueKey<double>).value,
        ('double', true) => (key as ValueKey<double?>).value,
        ('num', false) => (key as ValueKey<num>).value,
        ('num', true) => (key as ValueKey<num?>).value,
        ('bool', false) => (key as ValueKey<bool>).value,
        ('bool', true) => (key as ValueKey<bool?>).value,
        _ => throw const FormatException('Unknown native key projection'),
      };
  @override
  Iterable<String> get keys => fields.keys;
  @override
  Object? operator [](Object? name) {
    final type = fields[name];
    if (type == null) return null;
    return _values.putIfAbsent(name! as String, () => _read(type));
  }

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Immutable key projection');
  @override
  void clear() => throw UnsupportedError('Immutable key projection');
  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Immutable key projection');
}

Map<String, ValueOperation> _nativeOperations(DataSource source,
    BuildContext? context, Map<String, ValueOperation> operations) {
  context ??= source is _ValueDataSource ? source.context : null;
  return context == null
      ? operations
      : RestageNativeValues.operationsOf(context, operations,
          bindings: _nativeBindingsOf(source, context));
}

Map<String, NativeBinding<Object?>> _nativeBindingsOf(
    DataSource source, BuildContext? context) {
  context ??= source is _ValueDataSource ? source.context : null;
  if (source is _ValueDataSource) return source.nativeBindings;
  if (context == null) return const {};
  Map<String, NativeBinding<Object?>>? bindings;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is _BuilderContextScope && widget.frame.nativeBindings != null) {
      bindings = widget.frame.nativeBindings;
    } else if (widget is RestageNativeValues) {
      bindings = widget.bindings;
    } else {
      return true;
    }
    context!.dependOnInheritedElement(element as InheritedElement);
    return false;
  });
  return bindings ?? const {};
}

final class _NativeChildKey extends LocalKey {
  const _NativeChildKey(this.value);
  final Key value;
  @override
  bool operator ==(Object other) =>
      other is _NativeChildKey && value == other.value;
  @override
  int get hashCode => Object.hash(_NativeChildKey, value);
}
