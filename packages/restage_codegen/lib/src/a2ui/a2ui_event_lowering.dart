import 'package:meta/meta.dart';

import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';

/// How one interactive widget callback lowers to a declarative A2UI action.
///
/// The reflector classifies a callback parameter (a `FunctionType`) into one
/// of three dispositions, which the A2UI emitter reads to wire the generated
/// widget builder. The set is closed:
///
/// * a 0-argument callback ([A2uiCallbackDispatch]) dispatches an outward
///   event;
/// * a single-value `ValueChanged<T>` ([A2uiCallbackWriteBack]) writes its
///   value back into the bound data path;
/// * any other callback shape ([A2uiCallbackUnsupported]) fails closed — loud —
///   before lowering, and is never silently treated as a dispatch.
@immutable
sealed class A2uiCallbackSignature {
  /// Const base constructor for the sealed disposition hierarchy.
  const A2uiCallbackSignature();
}

/// A 0-argument callback (`void Function()` / `VoidCallback`) — lowers to an
/// outward event dispatch.
@immutable
final class A2uiCallbackDispatch extends A2uiCallbackSignature {
  /// Creates the dispatch disposition.
  const A2uiCallbackDispatch();

  @override
  bool operator ==(Object other) => other is A2uiCallbackDispatch;

  @override
  int get hashCode => (A2uiCallbackDispatch).hashCode;

  @override
  String toString() => 'A2uiCallbackDispatch()';
}

/// A single-value callback (`ValueChanged<T>`, i.e. `void Function(T)`) —
/// lowers to a write-back of [valueType] into the bound data path.
@immutable
final class A2uiCallbackWriteBack extends A2uiCallbackSignature {
  /// Creates a write-back disposition for a value of [valueType].
  const A2uiCallbackWriteBack(
    this.valueType, {
    required this.nullable,
    required this.isList,
  });

  /// The JSON scalar category of the written-back value — the scalar itself for
  /// a `ValueChanged<scalar>`, or the element scalar for a
  /// `ValueChanged<List<scalar>>`.
  final A2uiScalarType valueType;

  /// Whether the callback's value argument (`T`) is nullable
  /// (e.g. `ValueChanged<bool?>`).
  final bool nullable;

  /// Whether the value argument is a `List<scalar>` (list write-back) rather
  /// than a bare scalar.
  final bool isList;

  @override
  bool operator ==(Object other) =>
      other is A2uiCallbackWriteBack &&
      other.valueType == valueType &&
      other.nullable == nullable &&
      other.isList == isList;

  @override
  int get hashCode => Object.hash(valueType, nullable, isList);

  @override
  String toString() =>
      'A2uiCallbackWriteBack($valueType, nullable: $nullable, isList: $isList)';
}

/// A callback whose shape cannot be lowered to a declarative action — a
/// multi-argument callback, a single argument that is neither a scalar nor a
/// `List<scalar>`, or a bare `Function` with no signature.
///
/// The lowering fails closed — loud — on this disposition rather than guessing
/// one (the governing fail-closed-LOUD invariant, extended to callbacks).
@immutable
final class A2uiCallbackUnsupported extends A2uiCallbackSignature {
  /// Creates the unsupported disposition with a human-readable [reason].
  const A2uiCallbackUnsupported(this.reason);

  /// Why the callback could not be lowered, for the diagnostic.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is A2uiCallbackUnsupported && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'A2uiCallbackUnsupported($reason)';
}

/// A map from `(widgetName, propertyName)` to the classified callback signature
/// for that interactive property — the reflector's output, threaded into the
/// emitter alongside the serialized catalog (which discards customer callback
/// signatures). A property present here is a customer `@RestageWidget` callback
/// whose disposition the interactivity lowering reads; everything else takes
/// the unchanged catalog-fed path, so the built-in catalogs are byte-neutral.
typedef A2uiEventSeam = Map<(String, String), A2uiCallbackSignature>;

/// A map from `(widgetName, callbackPropertyName)` to the name of the value
/// property that callback explicitly writes back to — the A2UI-local carrier
/// for the `@RestageProperty(writeBackValue:)` pairing hint.
///
/// An entry here OVERRIDES the auto single-pair rule for that callback: the
/// emitter resolves the named pair directly (still validated + fail-closed on a
/// bad pairing), which enables write-back on a widget with more than one
/// interactive control (where the value↔callback pairing cannot be inferred
/// from the type list). Threaded into the emitter beside the [A2uiEventSeam];
/// the catalog never carries it, so the built-in catalogs stay byte-neutral and
/// the standard widget path is unaffected.
typedef A2uiPairingSeam = Map<(String, String), String>;
