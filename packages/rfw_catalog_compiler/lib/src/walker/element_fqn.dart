import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Fully-qualified-name helpers for analyzer elements.
///
/// The FQN string is the wire-identity key threaded through the compiler's
/// analysis passes, so its exact shape — `<library-identifier>#<ClassName>` —
/// must stay stable.
///
/// Two name-fallback conventions coexist and are both intentional:
///
/// * [elementFqn] / [interfaceFqn] substitute `'<unnamed>'` for a null
///   element name, always returning a non-null string. Identity comparisons
///   that already work against `'<unnamed>'`-bearing FQNs rely on this.
/// * [interfaceFqnOrNull] returns null for a null element name. Callers that
///   treat an un-nameable type as simply non-matching use this form.
///
/// Do not unify the two — collapsing them would change call-site semantics.

/// The `<library-identifier>#<ClassName>` identity for [element].
///
/// A null class name is substituted with `'<unnamed>'`; the result is always
/// non-null.
String elementFqn(ClassElement element) =>
    '${element.library.identifier}#${element.name ?? '<unnamed>'}';

/// The `<library-identifier>#<ClassName>` identity for [element].
///
/// A null element name is substituted with `'<unnamed>'`; the result is
/// always non-null.
String interfaceFqn(InterfaceElement element) =>
    '${element.library.identifier}#${element.name ?? '<unnamed>'}';

/// The `<library-identifier>#<ClassName>` identity for [element], or null
/// when the element has no name.
String? interfaceFqnOrNull(InterfaceElement element) {
  final name = element.name;
  if (name == null) return null;
  return '${element.library.identifier}#$name';
}

/// The [ClassElement] backing [type], or null when [type] is not an
/// interface type with a resolvable class element.
ClassElement? classElementFor(DartType type) {
  if (type is! InterfaceType) return null;
  final element = type.element;
  return element is ClassElement ? element : null;
}

/// The `<library-identifier>#<ClassName>` identity for [type], or null when
/// [type] is not an interface type with a resolvable [ClassElement].
///
/// Nullability is irrelevant to identity, so a nullable field type
/// (`Gradient?`) resolves to the same identity as its non-nullable form.
String? typeFqn(DartType type) {
  final element = classElementFor(type);
  return element != null ? elementFqn(element) : null;
}
