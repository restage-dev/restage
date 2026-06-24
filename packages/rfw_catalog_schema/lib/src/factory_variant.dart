import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/deprecation_info.dart';
import 'package:rfw_catalog_schema/src/native_decompose.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// One factory variant on a structured type. Covers every way a value
/// of the structured type can be authored in source: named constructors,
/// static factory methods, static getters, and static const fields.
///
/// The compiler enumerates each as a discrete variant with its own wire
/// ID so renames or restructures of one variant don't churn other
/// catalog references.
///
/// Sealed hierarchy: each concrete subtype is one authoring kind. The
/// per-kind fields live on the subtype that uses them, where they are
/// constrained by construction — a static getter or const field cannot
/// carry argument mappings or callable parameters, and the three accessor
/// kinds always have a non-null accessor name. [wireId], [description], and
/// [deprecated] are shared by every kind and stay on the base.
///
/// The wire discriminator is the `sourceKind` string
/// ([factoryVariantSourceKind] maps a variant to its [VariantSourceKind]);
/// the subtype is the in-memory representation.
sealed class FactoryVariant {
  /// Const constructor for the shared fields.
  const FactoryVariant({
    required this.wireId,
    this.description,
    this.deprecated,
  });

  /// Wire identity for this variant.
  final WireId wireId;

  /// Human-readable description; defaults to the underlying Dartdoc.
  final String? description;

  /// Lifecycle status for this variant.
  ///
  /// Source-level deprecation flows from an `@Deprecated` annotation on
  /// the underlying ConstructorElement / MethodElement / FieldElement /
  /// PropertyAccessorElement; catalog-level deprecation flows from a
  /// `deprecate` event on this variant's wire ID.
  final DeprecationInfo? deprecated;
}

/// A named or unnamed constructor variant (`EdgeInsets()`,
/// `EdgeInsets.only(...)`, `EdgeInsets.symmetric(...)`).
///
/// Analyzer source is a `ConstructorElement`; [argMappings] is populated
/// from the constructor's parameters.
@immutable
final class ConstructorVariant extends FactoryVariant {
  /// Const constructor.
  const ConstructorVariant({
    required super.wireId,
    this.namedConstructor,
    this.argMappings = const {},
    this.parameters = const [],
    super.description,
    super.deprecated,
  });

  /// Source-level constructor name. `null` for the unnamed canonical ctor;
  /// populated for named ctors (e.g. `'circular'`, `'symmetric'`, `'all'`,
  /// `'fromLTRB'`).
  ///
  /// Note: named constructors like `Color.fromARGB` are constructors (this
  /// subtype) with a [namedConstructor], NOT static methods.
  ///
  /// Advisory only — may shift via a `rename` event on this variant's
  /// wire ID. Wire identity is [wireId].
  final String? namedConstructor;

  /// How this constructor's args populate the structured type's fields.
  ///
  /// Keys are source-level ctor parameter names (labels; params aren't
  /// independently wire-tracked). Values are [ArgMapping]s. Splatting
  /// factories (`BorderRadius.circular(radius)` populating all four corner
  /// fields) are expressed via `ArgMapping.targetFields` carrying multiple
  /// wire IDs. Empty for a zero-argument constructor.
  final Map<String, ArgMapping> argMappings;

  /// Native callable parameter metadata for this constructor.
  final List<FactoryParameter> parameters;

  @override
  bool operator ==(Object other) =>
      other is ConstructorVariant &&
      other.wireId == wireId &&
      other.namedConstructor == namedConstructor &&
      _argMappingsEqual(other.argMappings, argMappings) &&
      _listEquals(other.parameters, parameters) &&
      other.description == description &&
      // `this.` qualifies the field: a bare `deprecated` resolves to the
      // dart:core `deprecated` const, not the inherited field.
      other.deprecated == this.deprecated;

  @override
  int get hashCode => Object.hash(
        wireId,
        namedConstructor,
        _argMappingsHash(argMappings),
        Object.hashAll(parameters),
        description,
        deprecated,
      );
}

/// A static factory method returning the structured type (e.g. a
/// customer's `AcmeColor.fromHex(String hex)`, or Flutter's
/// `Color.lerp(Color? a, Color? b, double t)`).
///
/// Analyzer source is a `MethodElement` with `isStatic == true`;
/// [argMappings] is populated from the method's parameters.
///
/// Note: named constructors (`Color.fromARGB`, `EdgeInsets.symmetric`) are
/// NOT static methods — they're [ConstructorVariant]s with a
/// [ConstructorVariant.namedConstructor].
@immutable
final class StaticMethodVariant extends FactoryVariant {
  /// Const constructor.
  const StaticMethodVariant({
    required super.wireId,
    required this.staticAccessor,
    this.argMappings = const {},
    this.parameters = const [],
    super.description,
    super.deprecated,
  });

  /// Source-level static method name (e.g. `'fromHex'`, `'lerp'`,
  /// `'styleFrom'`). Non-null by construction.
  ///
  /// Advisory only; wire identity is [wireId].
  final String staticAccessor;

  /// How this method's args populate the structured type's fields. See
  /// [ConstructorVariant.argMappings]. Empty for a zero-argument method.
  final Map<String, ArgMapping> argMappings;

  /// Native callable parameter metadata for this method.
  final List<FactoryParameter> parameters;

  @override
  bool operator ==(Object other) =>
      other is StaticMethodVariant &&
      other.wireId == wireId &&
      other.staticAccessor == staticAccessor &&
      _argMappingsEqual(other.argMappings, argMappings) &&
      _listEquals(other.parameters, parameters) &&
      other.description == description &&
      // `this.` qualifies the field: a bare `deprecated` resolves to the
      // dart:core `deprecated` const, not the inherited field.
      other.deprecated == this.deprecated;

  @override
  int get hashCode => Object.hash(
        wireId,
        staticAccessor,
        _argMappingsHash(argMappings),
        Object.hashAll(parameters),
        description,
        deprecated,
      );
}

/// A static getter accessor (`Foo.bar` where `bar` is a `get` accessor).
///
/// Analyzer source is a `PropertyAccessorElement` with `isStatic == true`
/// and `isGetter == true`. A zero-arg accessor evaluates directly to a
/// value, so there are no argument mappings or callable parameters.
@immutable
final class StaticGetterVariant extends FactoryVariant {
  /// Const constructor.
  const StaticGetterVariant({
    required super.wireId,
    required this.staticAccessor,
    super.description,
    super.deprecated,
  });

  /// Source-level getter name. Non-null by construction.
  ///
  /// Advisory only; wire identity is [wireId].
  final String staticAccessor;

  @override
  bool operator ==(Object other) =>
      other is StaticGetterVariant &&
      other.wireId == wireId &&
      other.staticAccessor == staticAccessor &&
      other.description == description &&
      // `this.` qualifies the field: a bare `deprecated` resolves to the
      // dart:core `deprecated` const, not the inherited field.
      other.deprecated == this.deprecated;

  @override
  int get hashCode =>
      Object.hash(wireId, staticAccessor, description, deprecated);
}

/// A static const field (`EdgeInsets.zero`, `Alignment.center`,
/// `Colors.transparent`).
///
/// Analyzer source is a `FieldElement` with `isStatic == true` and
/// `isConst == true`; the field's evaluated const value supplies the
/// structured-field values directly, so there are no argument mappings or
/// callable parameters.
@immutable
final class ConstValueVariant extends FactoryVariant {
  /// Const constructor.
  const ConstValueVariant({
    required super.wireId,
    required this.staticAccessor,
    super.description,
    super.deprecated,
  });

  /// Source-level const field name (e.g. `'zero'`, `'center'`). Non-null
  /// by construction.
  ///
  /// Advisory only; wire identity is [wireId].
  final String staticAccessor;

  @override
  bool operator ==(Object other) =>
      other is ConstValueVariant &&
      other.wireId == wireId &&
      other.staticAccessor == staticAccessor &&
      other.description == description &&
      // `this.` qualifies the field: a bare `deprecated` resolves to the
      // dart:core `deprecated` const, not the inherited field.
      other.deprecated == this.deprecated;

  @override
  int get hashCode =>
      Object.hash(wireId, staticAccessor, description, deprecated);
}

/// Discriminator for how a [FactoryVariant] is authored in source.
///
/// This is the `sourceKind` wire-discriminator vocabulary and the kind tag
/// carried by the compiler's internal variant representations (the variant
/// IR, the wire-ID event log, and the built-in seed data). The in-memory
/// [FactoryVariant] is a sealed hierarchy and dispatches on its subtype;
/// use [factoryVariantSourceKind] to map a variant to its kind.
enum VariantSourceKind {
  /// Named or unnamed constructor (`EdgeInsets()`,
  /// `EdgeInsets.only(...)`, `EdgeInsets.symmetric(...)`). Authored as a
  /// [ConstructorVariant]; analyzer source is a `ConstructorElement`.
  constructor,

  /// Static factory method returning the structured type (e.g. a
  /// customer's `AcmeColor.fromHex(String hex)`, or Flutter's
  /// `Color.lerp(Color? a, Color? b, double t)`). Authored as a
  /// [StaticMethodVariant]; analyzer source is a `MethodElement` with
  /// `isStatic == true`.
  ///
  /// Note: named constructors (`Color.fromARGB`, `EdgeInsets.symmetric`)
  /// are NOT static methods — they're [ConstructorVariant]s with a
  /// `namedConstructor`.
  staticMethod,

  /// Static getter accessor (`Foo.bar` where `bar` is a `get`
  /// accessor). Authored as a [StaticGetterVariant]; analyzer source is a
  /// `PropertyAccessorElement` with `isStatic == true` and
  /// `isGetter == true`.
  staticGetter,

  /// Static const field (`EdgeInsets.zero`, `Alignment.center`,
  /// `Colors.transparent`). Authored as a [ConstValueVariant]; analyzer
  /// source is a `FieldElement` with `isStatic == true` and
  /// `isConst == true`.
  constValue,
}

/// The [VariantSourceKind] for [variant] — the single authoritative mapping
/// from the sealed subtype to the `sourceKind` wire discriminator. The
/// enum's `name` is the wire string; do not change those spellings without a
/// schema revision.
VariantSourceKind factoryVariantSourceKind(FactoryVariant variant) =>
    switch (variant) {
      ConstructorVariant() => VariantSourceKind.constructor,
      StaticMethodVariant() => VariantSourceKind.staticMethod,
      StaticGetterVariant() => VariantSourceKind.staticGetter,
      ConstValueVariant() => VariantSourceKind.constValue,
    };

/// How one source-level ctor / factory-method argument maps onto the
/// structured type's fields.
@immutable
final class ArgMapping {
  /// Const constructor.
  const ArgMapping({required this.targetFields});

  /// Structured-field wire IDs this arg populates. Single-element list
  /// for the common one-to-one case; multi-element list for splatting
  /// factories (`BorderRadius.circular(radius)` populates all four
  /// corner fields).
  ///
  /// Serialization lives in the catalog codec alongside the owning
  /// variant's parameters; this type carries no standalone JSON codec.
  final List<WireId> targetFields;

  @override
  bool operator ==(Object other) =>
      other is ArgMapping && _listEquals(other.targetFields, targetFields);

  @override
  int get hashCode => Object.hashAll(targetFields);
}

/// Order-sensitive element-wise list equality (elements compared by `==`).
/// Avoids a `package:collection` dependency in this dependency-light package.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Order-insensitive equality for a variant's argument mappings (values
/// compared by [ArgMapping.==]).
bool _argMappingsEqual(Map<String, ArgMapping> a, Map<String, ArgMapping> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || other != entry.value) return false;
  }
  return true;
}

/// Order-independent hash for an argument-mappings map, consistent with
/// [_argMappingsEqual].
int _argMappingsHash(Map<String, ArgMapping> argMappings) =>
    Object.hashAllUnordered(
      argMappings.entries.map((e) => Object.hash(e.key, e.value)),
    );
