import 'package:meta/meta.dart';

/// Curated widget libraries shipped by Restage, plus customer-registered
/// libraries.
///
/// The built-in libraries (`core`, `material`, `cupertino`) are sibling
/// packages: `restage_core`, `restage_material`, `restage_cupertino`.
/// Customer-defined libraries register a custom namespace via
/// [WidgetLibrary.custom] or by extending [WidgetLibrary] directly for
/// type-per-library identity.
///
/// Every widget entry in the catalog declares which library it belongs to.
/// The runtime translates [namespace] to the rendering layer's wire-format
/// library identifier by splitting on `.` (e.g. `'restage.core'` becomes
/// `LibraryName(['restage', 'core'])`).
///
/// Equality is namespace-based: a customer subclass and a
/// `WidgetLibrary.custom(...)` carrying the same namespace compare equal
/// and hash equal, so `Map<WidgetLibrary, ...>` lookups round-trip across
/// JSON decode (which always produces `WidgetLibrary.custom`) regardless
/// of how the library was originally constructed.
///
/// **Subclassing.** Customer subclasses must declare `namespace` as a
/// final field (initialized at declaration), not as a getter —
/// build-time analyzer passes read namespaces via `DartObject.getField`,
/// which only sees fields.
///
/// ```dart
/// final class AcmeDesignSystem extends WidgetLibrary {
///   const AcmeDesignSystem();
///   @override
///   final String namespace = 'acme.design_system';
/// }
/// ```
@immutable
abstract base class WidgetLibrary {
  /// Const constructor for built-in singletons and customer subclasses.
  const WidgetLibrary();

  /// Construct a customer library identifier from a [namespace] string.
  ///
  /// ```dart
  /// const acmeDesignSystem = WidgetLibrary.custom('acme.design_system');
  /// ```
  ///
  /// Customers who want type-per-library identity (e.g. multiple internal
  /// design systems with separate namespaces) extend [WidgetLibrary]
  /// directly with a `final class` subclass.
  const factory WidgetLibrary.custom(String namespace) = _CustomLibrary;

  /// Resolve a library by namespace, falling back to a customer library
  /// when the namespace is not built-in. Used by the catalog JSON decoder
  /// which doesn't know whether a library is built-in until it has the
  /// list of built-ins.
  factory WidgetLibrary.fromNamespace(String namespace) =>
      builtInByNamespace(namespace) ?? WidgetLibrary.custom(namespace);

  /// The library namespace as a dotted string.
  ///
  /// Built-in namespaces are well-known: `'restage.core'`,
  /// `'restage.material'`, `'restage.cupertino'`. Customer namespaces
  /// typically follow a reverse-domain convention (`'acme.design_system'`).
  String get namespace;

  /// Cross-platform primitives — `Container`, `Column`, `Row`, etc.
  static const WidgetLibrary core = _BuiltinCoreLibrary();

  /// Material design widgets — `FilledButton`, `Scaffold`, etc.
  static const WidgetLibrary material = _BuiltinMaterialLibrary();

  /// Cupertino (Apple HIG) widgets — `CupertinoButton`, etc.
  static const WidgetLibrary cupertino = _BuiltinCupertinoLibrary();

  /// All built-in libraries shipped by Restage. Iteration order is stable:
  /// `core`, `material`, `cupertino`.
  static const List<WidgetLibrary> builtInLibraries = <WidgetLibrary>[
    core,
    material,
    cupertino,
  ];

  /// Look up a built-in library by its [namespace] string. Returns `null`
  /// for unknown namespaces — callers handle customer libraries separately
  /// via [WidgetLibrary.custom].
  static WidgetLibrary? builtInByNamespace(String namespace) {
    for (final lib in builtInLibraries) {
      if (lib.namespace == namespace) return lib;
    }
    return null;
  }

  /// Whether [namespace] follows the dotted-lowercase convention every
  /// catalog library uses (e.g. `restage.core`, `acme.design_system`).
  /// Codec and emitter call sites validate constructed namespaces against
  /// this predicate so malformed values fail at the boundary instead of
  /// silently round-tripping.
  static bool isValidNamespace(String namespace) =>
      _namespacePattern.hasMatch(namespace);

  @override
  bool operator ==(Object other) =>
      other is WidgetLibrary && other.namespace == namespace;

  @override
  int get hashCode => namespace.hashCode;

  @override
  String toString() => 'WidgetLibrary($namespace)';
}

final _namespacePattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$');

// Field initializers (rather than constructor parameters) are deliberate.
// Build-time analyzer passes read namespaces via `DartObject.getField`,
// which sees fields declared on the leaf class but does not traverse
// super-constructor-set fields. The trade-off is one suppressed lint per
// built-in subclass, in exchange for namespace introspection working
// correctly for `@RestageWidget(library: WidgetLibrary.core)` annotations.
// ignore_for_file: avoid_field_initializers_in_const_classes

final class _BuiltinCoreLibrary extends WidgetLibrary {
  const _BuiltinCoreLibrary();
  @override
  final String namespace = 'restage.core';
}

final class _BuiltinMaterialLibrary extends WidgetLibrary {
  const _BuiltinMaterialLibrary();
  @override
  final String namespace = 'restage.material';
}

final class _BuiltinCupertinoLibrary extends WidgetLibrary {
  const _BuiltinCupertinoLibrary();
  @override
  final String namespace = 'restage.cupertino';
}

final class _CustomLibrary extends WidgetLibrary {
  const _CustomLibrary(this.namespace);
  @override
  final String namespace;
}
