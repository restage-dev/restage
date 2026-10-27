import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

/// Decoded inert programs retain their captures and deferred RFW bodies.
final class RfwProgramEnvelope {
  /// Creates an already validated envelope.
  const RfwProgramEnvelope(
    this.values,
    this.builder,
    this.captures,
    this.bodies,
    this.capability,
  );

  /// Closed expression graph.
  final ValueProgram values;

  /// Deferred control flow, absent for an ordinary value.
  final BuilderProgram? builder;

  /// Capture nodes whose types the program declares.
  final Map<String, Object?> captures;

  /// Deferred bodies in program index order.
  final List<rfw.WidgetBuilderDeclaration> bodies;

  /// Highest installed operation requirement.
  final int capability;

  /// Types projected by every control-flow path selecting this body.
  Map<String, List<ValueType>> frameTypes(int bodyIndex) {
    final types = <String, List<ValueType>>{};
    var firstBody = true;
    void visit(BuilderResult result) {
      if (result.kind == 'body' && result.bodyIndex == bodyIndex) {
        if (!firstBody) {
          types.removeWhere((name, _) => !result.values.containsKey(name));
        }
        for (final entry in result.values.entries) {
          if (firstBody || types.containsKey(entry.key)) {
            types
                .putIfAbsent(entry.key, () => [])
                .add(values.nodes[entry.value].type);
          }
        }
        firstBody = false;
      }
      for (final child in result.descendants) {
        visit(child);
      }
    }

    if (builder case final program?) visit(program.result);
    return types;
  }
}

/// Validates lexical ownership once for the envelopes in a complete RFW tree.
final class RfwProgramScope {
  RfwProgramScope(Iterable<Object?> roots,
      {required this.operations, this.validateNativeBindingReferences = true}) {
    for (final root in roots) {
      _visit(root, ValueOperationContext(operations: operations));
    }
  }
  final Map<String, ValueOperation> operations;

  /// Capability inspection may classify unresolved references without admitting them.
  final bool validateNativeBindingReferences;

  /// Installed declarations actually used by a call in this lexical tree.
  final Map<String, NativeBindingContract> nativeCalls = {};

  /// Installed declarations used by calls or inline borrowed references.
  final Map<String, NativeBindingContract> nativeBindings = {};

  void _requireNative(String key, NativeBindingContract contract) {
    final previous = nativeBindings[key];
    if (previous != null && previous != contract) {
      throw FormatException('Conflicting native binding "$key"');
    }
    nativeBindings[key] = contract;
  }

  /// Capability required by programs and lexical native references.
  int requiredCapability = 1;
  final Map<Object, RfwProgramEnvelope> _envelopes = Map.identity();

  RfwProgramEnvelope? decode(Object? value) => value == null
      ? null
      : _envelopes[value] ??
          decodeRfwProgramEnvelope(value, operations: operations);

  void _collectNativeCalls(
      ValueProgram program, ValueOperationContext context) {
    final local = ValueOperationContext(
        operations: operations,
        locals: {...program.outerLocals, ...program.locals},
        depth: context.depth);
    for (final node in program.nodes) {
      if (node.op == 'native.call') {
        final options = node.value! as Map;
        final key = options['binding'] as String;
        final contract = NativeBindingContract.fromJson(options['contract']);
        nativeCalls[key] = contract;
        _requireNative(key, contract);
      }
      final operation = operations[node.op];
      if (operation is RegistryValueOperation) {
        for (final nested in operation.nestedPrograms(node, local)) {
          _collectNativeCalls(nested, local.nested());
        }
      }
    }
  }

  /// Validates a value reached by a declared native consumer in its own frame.
  void requireNativeValue(Object? value, ValueType expected,
      {ValueOperationContext? context}) {
    final lexical = context ?? ValueOperationContext(operations: operations);
    if (value == null && expected.nullable) return;
    if (value is rfw.Switch) {
      for (final output in value.outputs.values) {
        requireNativeValue(output, expected, context: lexical);
      }
      return;
    }
    // Host and forwarded values are checked against their installed schema.
    if (value is rfw.Reference) return;
    final envelope = decodeRfwProgramEnvelope(value,
        operations: operations, context: lexical);
    if (envelope != null) {
      if (envelope.builder != null ||
          !expected.accepts(envelope.values.nodes[envelope.values.root].type)) {
        throw const FormatException('Native result differs from its consumer.');
      }
      return;
    }
    if (value is! Map ||
        value.length != 4 ||
        value['type'] is! String ||
        value['nullable'] is! bool) {
      throw const FormatException('Malformed native reference');
    }
    final actual = ValueType.native(value['type'] as String,
        nullable: value['nullable'] as bool);
    if (!expected.accepts(actual)) {
      throw const FormatException(
          'Native reference differs from its consumer.');
    }
    if (value['kind'] == 'nativeBinding') {
      if (!validateNativeBindingReferences) return;
      if (value['key'] is! String) {
        throw const FormatException('Malformed native binding reference');
      }
      _requireNative(
          value['key'] as String,
          NativeBindingContract(
              type: actual.nativeType!, nullable: actual.nullable));
    } else if (value['kind'] == 'nativeLocal') {
      if (value['slot'] is! String) {
        throw const FormatException('Malformed native local reference');
      }
      final declared = lexical.locals[value['slot']];
      if (declared == null ||
          !declared.accepts(actual) ||
          !actual.accepts(declared)) {
        throw const FormatException(
            'Native local reference is outside its declared scope');
      }
    } else {
      throw const FormatException('Unknown native reference');
    }
    requiredCapability = 24;
  }

  void _nativeCapture(
      Object? value, ValueType type, ValueOperationContext context) {
    if (type.kind == 'native') {
      if (!validateNativeBindingReferences &&
          value is Map &&
          value['kind'] == 'nativeBinding') return;
      requireNativeValue(value, type, context: context);
    } else if (value is rfw.Switch) {
      for (final output in value.outputs.values)
        _nativeCapture(output, type, context);
    } else if (type.kind == 'record' && value is Map) {
      for (final field in type.fields.entries) {
        _nativeCapture(value[field.key], field.value, context);
      }
    } else if (type.kind == 'list' && value is List) {
      for (final item in value) _nativeCapture(item, type.item!, context);
    }
  }

  void _nativeKeys(RfwProgramEnvelope envelope, ValueOperationContext context) {
    void visit(BuilderResult result) {
      if (result.keyType == 'nativeBinding' && result.key != null) {
        final node = envelope.values.nodes[result.key!];
        final Object? value;
        if (node.op == 'capture') {
          value = envelope.captures[node.name];
        } else if (node.op == 'literal') {
          value = node.value;
        } else {
          throw const FormatException(
              'Native key output requires a proven native reference');
        }
        if (value is! Map || value['kind'] != 'nativeBinding') {
          throw const FormatException(
              'Native key output requires a proven installed binding reference');
        }
        requireNativeValue(
            value, const ValueType.native('flutter.Key', nullable: true),
            context: context);
      }
      for (final child in result.descendants) visit(child);
    }

    if (envelope.builder case final builder?) visit(builder.result);
  }

  void _visit(Object? value, ValueOperationContext context) {
    final envelope = decodeRfwProgramEnvelope(value,
        operations: operations, context: context);
    if (envelope != null) {
      if (envelope.capability > requiredCapability)
        requiredCapability = envelope.capability;
      _collectNativeCalls(envelope.values, context);
      _envelopes[value!] = envelope;
      if (value is rfw.ConstructorCall) _envelopes[value.arguments] = envelope;
      for (final capture in envelope.captures.entries) {
        _nativeCapture(
            capture.value, envelope.values.captures[capture.key]!, context);
        _visit(capture.value, context);
      }
      _nativeKeys(envelope, context);
      final child = context.nested(locals: envelope.values.locals);
      for (final body in envelope.bodies) {
        _visit(body.widget, child);
      }
      return;
    }
    switch (value) {
      case rfw.ConstructorCall(:final arguments):
        _visit(arguments, context);
      case rfw.WidgetBuilderDeclaration(:final widget):
        _visit(widget, context);
      case rfw.Loop(:final input, :final output):
        _visit(input, context);
        _visit(output, context);
      case rfw.Switch(:final input, :final outputs):
        _visit(input, context);
        for (final output in outputs.values) {
          _visit(output, context);
        }
      case rfw.EventHandler(:final eventArguments):
        _visit(eventArguments, context);
      case rfw.SetStateHandler(:final value):
        _visit(value, context);
      case Map():
        for (final child in value.values) {
          _visit(child, context);
        }
      case List():
        for (final child in value) {
          _visit(child, context);
        }
    }
  }
}

/// Recognizes the reserved program envelope, validating its complete structure.
RfwProgramEnvelope? decodeRfwProgramEnvelope(
  Object? value, {
  RfwProgramScope? scope,
  ValueOperationContext? context,
  Map<String, ValueOperation> operations = const {
    ...kCollectionValueOperations,
    ...kGridValueOperations,
    ...kIntlValueOperations
  },
}) {
  if (scope != null) return scope.decode(value);
  final continuation = value is rfw.ConstructorCall &&
      value.name == kBuilderContinuationWidgetName;
  if (continuation) value = value.arguments;
  if (value is! Map ||
      !value.containsKey('program') ||
      !(value.containsKey('captures') || value.containsKey('bodies'))) {
    if (continuation)
      throw const FormatException('Malformed builder continuation.');
    return null;
  }
  try {
    final isBuilder = value.containsKey('bodies');
    final allowed = {'version', 'program', 'captures', if (isBuilder) 'bodies'};
    if (value.length != allowed.length ||
        value.keys.any((key) => !allowed.contains(key)) ||
        value['version'] != valueProgramVersion ||
        value['program'] is! String ||
        value['captures'] is! Map<String, Object?>) {
      throw const FormatException('Malformed expression envelope.');
    }
    final encoded = value['program'] as String;
    final builder = isBuilder
        ? BuilderProgram.decode(encoded,
            operations: operations, context: context)
        : null;
    final program = builder?.values ??
        ValueProgram.decode(encoded, operations: operations, context: context);
    final iterationTypes = <String, ValueType>{};
    void collectIterations(BuilderResult result) {
      if (result.kind == 'forEach') {
        iterationTypes[result.parameter!] = ValueType.integer;
      } else if (result.kind == 'forEachItem') {
        iterationTypes[result.parameter!] =
            program.nodes[result.condition!].type.item!;
      }
      for (final child in result.descendants) collectIterations(child);
    }

    if (builder?.collection == true) collectIterations(builder!.result);
    for (final parameter in program.parameters.entries) {
      final contextType = builderContextValueType(parameter.key);
      if (contextType != null && parameter.value.accepts(contextType)) continue;
      if (builder != null && !builder.collection) {
        if (parameter.key == callbackParameterName(1)) continue;
        // Catalog admission subsequently checks the actual callback contract.
        if (parameter.key == callbackParameterName(0) &&
            builderContextNativeValueType.accepts(parameter.value) &&
            !parameter.value.nullable) continue;
      }
      if (builder?.collection == true &&
          iterationTypes[parameter.key]?.accepts(parameter.value) == true &&
          parameter.value.accepts(iterationTypes[parameter.key]!)) continue;
      if (builder == null &&
          isScalarCallbackParameterValueType(parameter.key, parameter.value))
        continue;
      throw const FormatException('Unknown expression parameter shape.');
    }
    final captures = value['captures'] as Map<String, Object?>;
    if (captures.length != program.captures.length ||
        !captures.keys.every(program.captures.containsKey)) {
      throw const FormatException(
        'Expression captures differ from their types.',
      );
    }
    final bodies = <rfw.WidgetBuilderDeclaration>[];
    if (builder != null) {
      final raw = value['bodies'];
      if (raw is! List ||
          raw.length != builder.bodyCount ||
          raw.any((body) => body is! rfw.WidgetBuilderDeclaration)) {
        throw const FormatException(
          'Builder bodies differ from their program.',
        );
      }
      bodies.addAll(raw.cast<rfw.WidgetBuilderDeclaration>());
    }
    var capability = valueProgramCapability;
    if (builder == null &&
        program.parameters.entries.any(
          (parameter) => isScalarCallbackParameterValueType(
            parameter.key,
            parameter.value,
          ),
        )) {
      capability = 20;
    }
    bool nativeIteration(BuilderResult result) =>
        result.kind == 'forEachItem' || result.descendants.any(nativeIteration);
    if (builder != null && nativeIteration(builder.result)) capability = 24;
    final required = valueProgramRequiredCapability(program,
        operations: operations, context: context);
    if (required > capability) capability = required;
    return RfwProgramEnvelope(program, builder, captures, bodies, capability);
    // The JSON codec's checked casts reject malformed wire values.
    // ignore: avoid_catching_errors
  } on TypeError {
    throw const FormatException('Malformed expression program.');
    // The JSON codec rejects malformed collection shapes with checked casts.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    throw const FormatException('Malformed expression program.');
  }
}

/// Checks the native callback identity against its declared inert inputs.
void validateRfwBuilderContract(
  Object? value,
  WidgetBuilderContract contract, {
  RfwProgramScope? scope,
  Map<String, ValueOperation> operations = const {
    ...kCollectionValueOperations,
    ...kGridValueOperations,
    ...kIntlValueOperations
  },
}) {
  final envelope =
      decodeRfwProgramEnvelope(value, operations: operations, scope: scope);
  final builder = envelope?.builder;
  if (builder == null)
    throw const FormatException('Missing native builder program');
  validateBuilderProgramContract(builder, contract);
}
