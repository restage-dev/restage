// packages/rfw_catalog_compiler/lib/src/walker/structured_type_predicate.dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/element_fqn.dart';

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
/// [_maxAliasDepth] unique alias elements and stop when we revisit one
/// (or hit the depth budget) — yielding `notStructured` rather than
/// blowing the stack.
StructuredKind classifyStructured(DartType type, PolicyLedger policy) {
  var current = type;
  final seenAliases = <TypeAliasElement>{};
  for (var i = 0; i < _maxAliasDepth; i++) {
    final alias = current.alias;
    if (alias == null) break;
    if (!seenAliases.add(alias.element)) break;
    current = alias.element.instantiate(
      typeArguments: alias.typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

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

/// Maximum chained alias unwraps before the classifier gives up.
///
/// In practice aliases rarely chain more than one or two levels; the
/// budget is a defense against the analyzer returning self-referential
/// alias-bearing types from `TypeAliasElement.instantiate`.
const int _maxAliasDepth = 8;
