import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'builder_binding.dart';
import 'island_stage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart';

export 'package:restage_shared/restage_shared.dart'
    show NativeBindingContract, NativeCallContract, ValueType, ValueNative;

/// An actual installed value borrowed for the lifetime of its native owner.
@immutable
final class NativeBinding<T> implements ValueNative {
  /// Binds [value] without taking ownership or evaluating a callback.
  NativeBinding({required this.contract, required this.value}) {
    if (contract.type.isEmpty || (value == null && !contract.nullable)) {
      throw ArgumentError('The native value does not satisfy its declaration.');
    }
  }

  /// The declaration included in the surface contract.
  @override
  final NativeBindingContract contract;

  /// The exact object or callback supplied by the app.
  @override
  final T value;
}

/// Native values computed by one surface mount at its authored context.
class RestageNativeValues extends InheritedWidget {
  /// Takes an immutable snapshot without acquiring ownership of any value.
  RestageNativeValues({
    super.key,
    Map<String, TextScaler?> textScalers = const {},
    Map<String, NativeBinding<Object?>> bindings = const {},
    this.labels = const {},
    required super.child,
  })  : textScalers = Map.unmodifiable(textScalers),
        // A live view stays live: a builder that runs later adds to it.
        bindings =
            bindings is UnmodifiableMapBase<String, NativeBinding<Object?>>
                ? bindings
                : Map.unmodifiable(bindings);

  /// The source expression of each native value, empty in release builds.
  final Map<String, String> labels;

  /// The exact Flutter scalers associated with this mount's reference keys.
  final Map<String, TextScaler?> textScalers;

  /// Declared borrowed values, keyed by their compiled slot identifiers.
  final Map<String, NativeBinding<Object?>> bindings;

  /// Captures this scope's immutable map for a retained callback.
  static Map<String, NativeBinding<Object?>> bindingsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RestageNativeValues>()
          ?.bindings ??
      const {};

  /// Resolves a declared slot, rejecting missing, retyped and invalid values.
  static T? bindingOf<T extends Object>(BuildContext context, String key,
      {required NativeBindingContract contract}) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RestageNativeValues>();
    final entry = scope?.bindings[key];
    if (entry == null) reportMissingNativeValue(context, key);
    if (entry == null || entry.contract != contract) {
      throw FormatException(
          'Native binding "$key" is unavailable or incompatible.');
    }
    final value = entry.value;
    if (value == null && contract.nullable) return null;
    if (withheldWhileStaged(value, context)) return null;
    if (value is! T) {
      throw FormatException('Native binding "$key" has the wrong Dart type.');
    }
    return value;
  }

  /// Reads an inert reference using a type fixed by the native consumer.
  static T? read<T extends Object>(
      BuildContext context, DataSource source, List<Object> path,
      {required String type}) {
    return RestageValueBinding.readNative<T>(source, path, context, type: type);
  }

  /// Installs the declared call operation without invoking any adapter.
  static Map<String, ValueOperation> operationsOf(
      BuildContext context, Map<String, ValueOperation> base,
      {Map<String, NativeBinding<Object?>>? bindings}) {
    final installed = bindings ?? bindingsOf(context);
    return {
      ...base,
      'native.call': NativeCallValueOperation(
          installed.map((key, binding) => MapEntry(key, binding.contract)),
          invoke: (key, contract, inputs, slots, frame) {
        final entry = installed[key];
        final adapter = entry?.value;
        if (entry?.contract != contract ||
            adapter is! NativeCallAdapter ||
            adapter.contract != contract) {
          throw const FormatException(
              'Native call implementation is incompatible');
        }
        return adapter.invoke(inputs, {
          for (final capture in contract.call!.captures.entries)
            capture.key: NativeCapture<Object?>(
                frame, slots[capture.key]!, capture.value)
        });
      })
    };
  }

  /// Resolves a native scaler and subscribes to replacement of this scope.
  static TextScaler? textScalerOf(BuildContext context, String key) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RestageNativeValues>();
    if (scope == null || !scope.textScalers.containsKey(key)) {
      reportMissingNativeValue(context, key);
      throw FormatException('Native TextScaler binding "$key" is unavailable.');
    }
    return scope.textScalers[key];
  }

  @override
  bool updateShouldNotify(RestageNativeValues oldWidget) =>
      !mapEquals(textScalers, oldWidget.textScalers) ||
      bindings.length != oldWidget.bindings.length ||
      bindings.entries.any((entry) {
        final previous = oldWidget.bindings[entry.key];
        return previous == null ||
            previous.contract != entry.value.contract ||
            !identical(previous.value, entry.value.value);
      });
}

/// Whether [value] waits until the version [context] sits in is shown: a
/// staged version takes the app's controllers and focus nodes only once it
/// is shown, as it does islands, so none attaches in two versions at once.
bool withheldWhileStaged(Object? value, BuildContext context) =>
    (value is ScrollController || value is FocusNode) &&
    RestageIslandStage.isCandidate(context);

/// Explains in debug builds why a widget reading native value [key] fails.
void reportMissingNativeValue(BuildContext? context, String key) {
  assert(() {
    final labels =
        context?.getInheritedWidgetOfExactType<RestageNativeValues>()?.labels;
    // Labels use the value's key; a per-item key adds the item's position.
    final label = labels?[key.split('#').first];
    final name = context is StatefulElement
        ? RegExp(r'name: \S+?:(\w+)').firstMatch('${context.state}')?.group(1)
        : null;
    final widget = name ?? 'widget';
    final message = label == null
        ? "[restage] This app build doesn't compute a value this design uses. "
            "The $widget that uses it isn't shown."
        : "[restage] '$label' threw while the app computed it. The $widget "
            "that uses it isn't shown.";
    if (_reportedMissing.add(message)) debugPrint(message);
    return true;
  }());
}

final Set<String> _reportedMissing = {};

/// An installed implementation; creating this adapter never executes its body.
final class NativeCallAdapter {
  NativeCallAdapter(this.contract, this.invoke) {
    if (contract.call == null)
      throw ArgumentError('Expected a callable contract');
  }
  final NativeBindingContract contract;
  final Object? Function(
          List<Object?> inputs, Map<String, NativeCapture<Object?>> captures)
      invoke;
}

/// A typed view of the existing lexical cell retained at closure creation.
final class NativeCapture<T> {
  NativeCapture(this.frame, this.slot, this.type) {
    final actual = frame.visibleTypes[slot];
    if (actual == null || !type.accepts(actual) || !actual.accepts(type)) {
      throw const FormatException(
          'Native capture type does not match its cell');
    }
  }
  final ValueLocalFrame frame;
  final String slot;
  final ValueType type;
  NativeCapture<U> cast<U>() => NativeCapture<U>(frame, slot, type);
  T get value {
    final value = frame.read(slot);
    return (value is ValueNative ? value.value : value) as T;
  }

  set value(T value) {
    frame.write(
        slot,
        type.kind == 'native' && value != null
            ? NativeBinding<T>(
                contract: NativeBindingContract(
                    type: type.nativeType!, nullable: type.nullable),
                value: value)
            : value);
  }
}
