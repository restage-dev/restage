import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

/// Unwraps analyzer type aliases without following a repeated alias forever.
///
/// Alias instantiation deliberately discards outer nullability; callers that
/// need it must inspect the original type first.
DartType unwrapTypeAliases(DartType type) {
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
  return current;
}

/// Maximum chained alias unwraps before classification gives up.
///
/// In practice aliases rarely chain more than one or two levels; the budget
/// defends against self-referential alias-bearing types returned by the
/// analyzer.
const int _maxAliasDepth = 8;
