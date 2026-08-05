import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/element_fqn.dart';
import 'package:rfw_catalog_compiler/src/walker/type_alias_unwrapper.dart';

/// Three-way verdict for [classifyStructured].
enum StructuredKind {
  /// A concrete value type the walker should recurse INTO.
  concrete,

  /// An abstract base whose subtypes are catalogued separately via
  /// the union registry. The walker short-circuits here.
  abstractBase,

  /// Any other type — scalars, collections, function types, records,
  /// type parameters, etc. The walker treats these via non-structured
  /// handling.
  notStructured,
}

/// Classifies [type] against the structured-walk policy in [policy].
///
/// Only [InterfaceType] is eligible. Type aliases are unwrapped to
/// their underlying type so an alias to a structured type classifies
/// the same as the target. The match key is the canonical
/// `<library identifier>#<class name>` for the element.
///
/// Alias unwrapping is iterative and bounded: the analyzer's
/// instantiated type may itself carry an `.alias` back-pointer to the
/// same alias element, so naive recursion would loop. We walk at most
/// a small fixed number of unique alias elements and stop when we revisit one
/// (or hit the depth budget), yielding `notStructured` rather than blowing the
/// stack.
StructuredKind classifyStructured(DartType type, PolicyLedger policy) {
  final current = unwrapTypeAliases(type);

  if (current is! InterfaceType) return StructuredKind.notStructured;

  final fqn = interfaceFqnOrNull(current.element);
  if (fqn == null) return StructuredKind.notStructured;

  if (policy.structuredWalk.concreteTypes.contains(fqn)) {
    return StructuredKind.concrete;
  }
  if (policy.structuredWalk.abstractTypes.contains(fqn)) {
    return StructuredKind.abstractBase;
  }
  return StructuredKind.notStructured;
}
