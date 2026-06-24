import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/property_type.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Source-qualified Dart type identity used by native catalog metadata.
@immutable
final class DartTypeRef {
  /// Creates a source-qualified Dart type reference.
  const DartTypeRef({required this.libraryUri, required this.symbolName});

  /// Import URI that defines the type.
  final String libraryUri;

  /// Public symbol name inside [libraryUri].
  final String symbolName;

  @override
  bool operator ==(Object other) =>
      other is DartTypeRef &&
      other.libraryUri == libraryUri &&
      other.symbolName == symbolName;

  @override
  int get hashCode => Object.hash(libraryUri, symbolName);

  @override
  String toString() => '$libraryUri#$symbolName';
}

/// Extra wire-level codec hints for values whose semantic shape is not enough.
enum CatalogWireCodec {
  /// Remote Flutter Widgets gradient map shape.
  rfwGradient,

  /// Remote Flutter Widgets border map shape.
  rfwBorder,

  /// Remote Flutter Widgets boxed `BoxShadow` list shape.
  rfwBoxShadowList,

  /// Restage/RFW-compatible shape-border map shape.
  rfwShapeBorder,
}

/// Semantic shape of a catalog value.
///
/// Sealed hierarchy: each concrete subtype is one shape category. The
/// per-category reference fields (enum/structured/union/item) live on the
/// subtype that uses them, where they are non-null by construction.
///
/// [propertyType] and [wireCodec] stay on the base because they are
/// cross-cutting: [propertyType] is the finer-grained runtime/editor type
/// (a `ScalarShape` is still `color` vs `string` vs `double`), and
/// [wireCodec] is a hint that applies wherever the value shape is not
/// implied by the category (it appears on scalar, union, and list values).
sealed class CatalogValueShape {
  /// Creates a value shape descriptor.
  const CatalogValueShape({required this.propertyType, this.wireCodec});

  /// Existing coarse property type used by runtime/editor decoders.
  final PropertyType propertyType;

  /// Wire codec hint when the RFW/editor value shape is not implied by the
  /// shape category.
  final CatalogWireCodec? wireCodec;
}

/// Scalar or opaque value.
@immutable
final class ScalarShape extends CatalogValueShape {
  /// Creates a scalar value shape.
  ///
  /// The assert mirrors the codec's propertyType-compat rule
  /// (`_validatePropertyTypeForKind`): a scalar is the catch-all single-value
  /// category, so it may carry any [PropertyType] except the two with a
  /// dedicated subtype (`enumValue` → [EnumShape], `structured` →
  /// [StructuredShape]). Debug-mode best-effort; the codec is canonical.
  const ScalarShape({
    required super.propertyType,
    this.dartTypeRef,
    super.wireCodec,
  }) : assert(
          propertyType != PropertyType.enumValue &&
              propertyType != PropertyType.structured,
          'ScalarShape must not carry PropertyType.enumValue/structured',
        );

  /// Source-qualified Dart type for scalar/source-backed values.
  final DartTypeRef? dartTypeRef;

  @override
  bool operator ==(Object other) =>
      other is ScalarShape &&
      other.propertyType == propertyType &&
      other.wireCodec == wireCodec &&
      other.dartTypeRef == dartTypeRef;

  @override
  int get hashCode => Object.hash(propertyType, wireCodec, dartTypeRef);
}

/// Source-qualified enum value.
@immutable
final class EnumShape extends CatalogValueShape {
  /// Creates an enum value shape.
  ///
  /// The assert mirrors the codec's propertyType-compat rule: an enum shape's
  /// propertyType is constant-redundant with the subtype.
  const EnumShape({
    required super.propertyType,
    required this.enumRef,
    super.wireCodec,
  }) : assert(
          propertyType == PropertyType.enumValue ||
              propertyType == PropertyType.unknown,
          'EnumShape must carry PropertyType.enumValue (or unknown)',
        );

  /// Source-qualified enum type.
  final DartTypeRef enumRef;

  @override
  bool operator ==(Object other) =>
      other is EnumShape &&
      other.propertyType == propertyType &&
      other.wireCodec == wireCodec &&
      other.enumRef == enumRef;

  @override
  int get hashCode => Object.hash(propertyType, wireCodec, enumRef);
}

/// Structured value.
@immutable
final class StructuredShape extends CatalogValueShape {
  /// Creates a structured value shape.
  ///
  /// The assert mirrors the codec's propertyType-compat rule: a structured
  /// shape's propertyType is constant-redundant with the subtype.
  const StructuredShape({
    required super.propertyType,
    required this.structuredRef,
    super.wireCodec,
  }) : assert(
          propertyType == PropertyType.structured ||
              propertyType == PropertyType.unknown,
          'StructuredShape must carry PropertyType.structured (or unknown)',
        );

  /// Structured catalog entry.
  final WireIdRef structuredRef;

  @override
  bool operator ==(Object other) =>
      other is StructuredShape &&
      other.propertyType == propertyType &&
      other.wireCodec == wireCodec &&
      other.structuredRef == structuredRef;

  @override
  int get hashCode => Object.hash(propertyType, wireCodec, structuredRef);
}

/// Discriminated union value.
@immutable
final class UnionShape extends CatalogValueShape {
  /// Creates a union value shape.
  ///
  /// The assert mirrors the codec's propertyType-compat rule: a union shape
  /// carries one of the discriminated-union types.
  const UnionShape({
    required super.propertyType,
    required this.unionRef,
    super.wireCodec,
  }) : assert(
          propertyType == PropertyType.border ||
              propertyType == PropertyType.gradient ||
              propertyType == PropertyType.shapeBorder ||
              propertyType == PropertyType.unknown,
          'UnionShape must carry PropertyType.border/gradient/shapeBorder '
          '(or unknown)',
        );

  /// Union catalog entry.
  final WireIdRef unionRef;

  @override
  bool operator ==(Object other) =>
      other is UnionShape &&
      other.propertyType == propertyType &&
      other.wireCodec == wireCodec &&
      other.unionRef == unionRef;

  @override
  int get hashCode => Object.hash(propertyType, wireCodec, unionRef);
}

/// List value.
@immutable
final class ListShape extends CatalogValueShape {
  /// Creates a list value shape.
  ///
  /// The assert mirrors the codec's propertyType-compat rule: a list shape
  /// carries one of the list-category types.
  const ListShape({
    required super.propertyType,
    required this.itemShape,
    super.wireCodec,
  }) : assert(
          propertyType == PropertyType.widgetList ||
              propertyType == PropertyType.stringList ||
              propertyType == PropertyType.booleanList ||
              propertyType == PropertyType.boxShadowList ||
              propertyType == PropertyType.shadowList ||
              propertyType == PropertyType.fontFeatureList ||
              propertyType == PropertyType.fontVariationList ||
              propertyType == PropertyType.unknown,
          'ListShape must carry a list-category PropertyType (or unknown)',
        );

  /// Item value shape.
  final CatalogValueShape itemShape;

  @override
  bool operator ==(Object other) =>
      other is ListShape &&
      other.propertyType == propertyType &&
      other.wireCodec == wireCodec &&
      other.itemShape == itemShape;

  @override
  int get hashCode => Object.hash(propertyType, wireCodec, itemShape);
}

/// Wire `kind` discriminator string for a [CatalogValueShape] — the single
/// authoritative spelling (`scalar` / `enumValue` / `structured` / `union` /
/// `list`) shared by the JSON codec and the catalog tooling. The strings are
/// part of the wire contract; do not change them without a schema revision.
String catalogValueShapeKindName(CatalogValueShape shape) => switch (shape) {
      ScalarShape() => 'scalar',
      EnumShape() => 'enumValue',
      StructuredShape() => 'structured',
      UnionShape() => 'union',
      ListShape() => 'list',
    };

/// Parameter metadata for one callable factory variant.
@immutable
final class FactoryParameter {
  /// Creates a factory parameter descriptor.
  const FactoryParameter({
    required this.wireId,
    required this.kind,
    required this.required,
    required this.nullable,
    required this.defaultPolicy,
    required this.valueShape,
    this.name,
    this.position,
    this.defaultValue,
  });

  /// Stable parameter wire ID (`a*`).
  final WireId wireId;

  /// Named parameter label, if [kind] is [FactoryParameterKind.named].
  final String? name;

  /// Positional parameter index, if [kind] is
  /// [FactoryParameterKind.positional].
  final int? position;

  /// Source parameter kind.
  final FactoryParameterKind kind;

  /// Whether the callable requires this parameter.
  final bool required;

  /// Whether the parameter type accepts null.
  final bool nullable;

  /// How native emitters handle absent/null values.
  final FactoryParameterDefaultPolicy defaultPolicy;

  /// Typed default value/expression for optional non-nullable parameters.
  final FactoryParameterDefaultValue? defaultValue;

  /// Semantic value shape accepted by this parameter.
  final CatalogValueShape valueShape;

  @override
  bool operator ==(Object other) =>
      other is FactoryParameter &&
      other.wireId == wireId &&
      other.name == name &&
      other.position == position &&
      other.kind == kind &&
      other.required == required &&
      other.nullable == nullable &&
      other.defaultPolicy == defaultPolicy &&
      other.defaultValue == defaultValue &&
      other.valueShape == valueShape;

  @override
  int get hashCode => Object.hash(
        wireId,
        name,
        position,
        kind,
        required,
        nullable,
        defaultPolicy,
        defaultValue,
        valueShape,
      );
}

/// Source parameter kind.
enum FactoryParameterKind {
  /// Named callable parameter.
  named,

  /// Positional callable parameter.
  positional,
}

/// Default/null emission policy for factory parameters.
enum FactoryParameterDefaultPolicy {
  /// Omit the argument when the value is null.
  omitWhenNull,

  /// Emit an explicit null argument.
  emitNull,

  /// Let Flutter's default apply by omitting the argument.
  useFlutterDefault,

  /// A value is required.
  requiredValue,
}

/// Typed default value/expression for a factory parameter.
///
/// Sealed hierarchy: a parameter default is either a JSON-compatible literal
/// or a static member on a source-qualified Dart type. Value-equality is
/// preserved per-subtype (consumers compare defaults by value).
///
/// **Naming.** The `…ParameterDefault` suffix distinguishes these from the
/// sibling property-side `DefaultValueSource` hierarchy (which has its own
/// `LiteralDefault`).
sealed class FactoryParameterDefaultValue {
  /// Const base constructor.
  const FactoryParameterDefaultValue();
}

/// JSON-compatible scalar literal default.
@immutable
final class LiteralParameterDefault extends FactoryParameterDefaultValue {
  /// Creates a literal default value. `null` is a legal literal value at the
  /// Dart-type level; the codec enforces the wire-legal literal set.
  const LiteralParameterDefault(this.value);

  /// Literal default value.
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is LiteralParameterDefault && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Static member default on a source-qualified Dart type, e.g.
/// `BorderSide.none`.
@immutable
final class StaticMemberParameterDefault extends FactoryParameterDefaultValue {
  /// Creates a static member default.
  const StaticMemberParameterDefault({
    required this.staticType,
    required this.memberName,
  });

  /// Source-qualified owner type.
  final DartTypeRef staticType;

  /// Static member name.
  final String memberName;

  @override
  bool operator ==(Object other) =>
      other is StaticMemberParameterDefault &&
      other.staticType == staticType &&
      other.memberName == memberName;

  @override
  int get hashCode => Object.hash(staticType, memberName);
}

/// Receiver for a native factory invocation.
///
/// Sealed hierarchy: the receiver is the structured result type, the owning
/// widget type, or an explicit source-qualified Dart type.
sealed class FactoryReceiver {
  /// Const base constructor.
  const FactoryReceiver();
}

/// Invoke on the structured result type.
@immutable
final class ResultStructuredTypeReceiver extends FactoryReceiver {
  /// Creates a result-structured-type receiver.
  const ResultStructuredTypeReceiver();

  @override
  bool operator ==(Object other) => other is ResultStructuredTypeReceiver;

  @override
  int get hashCode => (ResultStructuredTypeReceiver).hashCode;
}

/// Invoke on the widget type that owns the recipe.
@immutable
final class OwningWidgetTypeReceiver extends FactoryReceiver {
  /// Creates an owning-widget-type receiver.
  const OwningWidgetTypeReceiver();

  @override
  bool operator ==(Object other) => other is OwningWidgetTypeReceiver;

  @override
  int get hashCode => (OwningWidgetTypeReceiver).hashCode;
}

/// Invoke on an explicit source-qualified Dart type.
@immutable
final class ExplicitDartTypeReceiver extends FactoryReceiver {
  /// Creates an explicit-Dart-type receiver.
  const ExplicitDartTypeReceiver(this.dartTypeRef);

  /// Explicit receiver type.
  final DartTypeRef dartTypeRef;

  @override
  bool operator ==(Object other) =>
      other is ExplicitDartTypeReceiver && other.dartTypeRef == dartTypeRef;

  @override
  int get hashCode => dartTypeRef.hashCode;
}

/// Native construction identity for a structured value.
@immutable
final class FactoryInvocation {
  /// Creates a factory invocation.
  const FactoryInvocation({
    required this.variantRef,
    required this.receiver,
    this.memberName,
  });

  /// Factory variant identity.
  final WireIdRef variantRef;

  /// Invocation receiver.
  final FactoryReceiver receiver;

  /// Named constructor/static member name when not implied by [variantRef].
  final String? memberName;

  @override
  bool operator ==(Object other) =>
      other is FactoryInvocation &&
      other.variantRef == variantRef &&
      other.receiver == receiver &&
      other.memberName == memberName;

  @override
  int get hashCode => Object.hash(variantRef, receiver, memberName);
}

/// Mapping from a widget property to a structured field.
@immutable
final class DecompositionFieldMapping {
  /// Creates a field mapping.
  const DecompositionFieldMapping({
    required this.fieldRef,
    required this.propertyRef,
    required this.transform,
  });

  /// Field wire ID on the recipe's structured result type.
  final WireId fieldRef;

  /// Property wire ID on the owning widget.
  final WireId propertyRef;

  /// Value transform used for this mapping.
  final DecompositionValueTransform transform;
}

/// Mapping from a widget property directly to a factory parameter.
@immutable
final class DecompositionParameterMapping {
  /// Creates a parameter mapping.
  const DecompositionParameterMapping({
    required this.parameterRef,
    required this.propertyRef,
    required this.transform,
  });

  /// Factory parameter wire ID on the recipe's construction variant.
  final WireId parameterRef;

  /// Property wire ID on the owning widget.
  final WireId propertyRef;

  /// Value transform used for this mapping.
  final DecompositionValueTransform transform;
}

/// Native value transform for a decompose mapping.
///
/// Sealed hierarchy: identity, construct-variant (recursive via argument
/// bindings), project-list (recursive via the item transform), or
/// coerce-scalar.
sealed class DecompositionValueTransform {
  /// Const base constructor.
  const DecompositionValueTransform();
}

/// Direct value mapping.
@immutable
final class IdentityTransform extends DecompositionValueTransform {
  /// Creates an identity transform.
  const IdentityTransform();

  @override
  bool operator ==(Object other) => other is IdentityTransform;

  @override
  int get hashCode => (IdentityTransform).hashCode;
}

/// Construct a structured value through another factory invocation.
@immutable
final class ConstructVariantTransform extends DecompositionValueTransform {
  /// Creates a construct-variant transform.
  const ConstructVariantTransform({
    required this.resultStructuredRef,
    required this.invocation,
    required this.argumentBindings,
  });

  /// Result structured type for the construction.
  final WireIdRef resultStructuredRef;

  /// Factory invocation that builds the structured value.
  final FactoryInvocation invocation;

  /// Argument bindings mapping sources to the construction's parameters.
  final List<TransformArgumentBinding> argumentBindings;

  @override
  bool operator ==(Object other) =>
      other is ConstructVariantTransform &&
      other.resultStructuredRef == resultStructuredRef &&
      other.invocation == invocation &&
      _listEquals(other.argumentBindings, argumentBindings);

  @override
  int get hashCode => Object.hash(
        resultStructuredRef,
        invocation,
        Object.hashAll(argumentBindings),
      );
}

/// Project each item in a list through [itemTransform].
@immutable
final class ProjectListTransform extends DecompositionValueTransform {
  /// Creates a project-list transform.
  const ProjectListTransform({required this.itemTransform});

  /// Transform applied to each list item.
  final DecompositionValueTransform itemTransform;

  @override
  bool operator ==(Object other) =>
      other is ProjectListTransform && other.itemTransform == itemTransform;

  @override
  int get hashCode => itemTransform.hashCode;
}

/// Coerce a scalar value using [scalarCoercion].
@immutable
final class CoerceScalarTransform extends DecompositionValueTransform {
  /// Creates a coerce-scalar transform.
  const CoerceScalarTransform({required this.scalarCoercion});

  /// Named scalar coercion.
  final String scalarCoercion;

  @override
  bool operator ==(Object other) =>
      other is CoerceScalarTransform && other.scalarCoercion == scalarCoercion;

  @override
  int get hashCode => scalarCoercion.hashCode;
}

/// Binding from a transform source to a target factory parameter.
///
/// Sealed hierarchy tagged on the source. [parameterRef]/[nullPolicy]/
/// [missingPolicy] are carried by every binding regardless of source, so
/// they live on the base; only the source-specific payload (the literal
/// value, the nested transform) moves to the subtype.
sealed class TransformArgumentBinding {
  /// Const base constructor.
  const TransformArgumentBinding({
    required this.parameterRef,
    required this.nullPolicy,
    required this.missingPolicy,
  });

  /// Target factory parameter wire ID (`a*`).
  final WireId parameterRef;

  /// Null handling policy.
  final TransformNullPolicy nullPolicy;

  /// Missing-value handling policy.
  final TransformMissingPolicy missingPolicy;
}

/// Use the mapped widget property value.
@immutable
final class PropertyValueArgumentBinding extends TransformArgumentBinding {
  /// Creates a property-value binding.
  const PropertyValueArgumentBinding({
    required super.parameterRef,
    required super.nullPolicy,
    required super.missingPolicy,
  });

  @override
  bool operator ==(Object other) =>
      other is PropertyValueArgumentBinding &&
      other.parameterRef == parameterRef &&
      other.nullPolicy == nullPolicy &&
      other.missingPolicy == missingPolicy;

  @override
  int get hashCode => Object.hash(parameterRef, nullPolicy, missingPolicy);
}

/// Use a literal value. `null` is a legal literal (the intentional Dart
/// `null`).
@immutable
final class LiteralArgumentBinding extends TransformArgumentBinding {
  /// Creates a literal binding.
  const LiteralArgumentBinding({
    required this.literal,
    required super.parameterRef,
    required super.nullPolicy,
    required super.missingPolicy,
  });

  /// Literal value (may be `null`).
  final Object? literal;

  @override
  bool operator ==(Object other) =>
      other is LiteralArgumentBinding &&
      other.literal == literal &&
      other.parameterRef == parameterRef &&
      other.nullPolicy == nullPolicy &&
      other.missingPolicy == missingPolicy;

  @override
  int get hashCode =>
      Object.hash(literal, parameterRef, nullPolicy, missingPolicy);
}

/// Use a nested transform to produce the argument value.
@immutable
final class NestedTransformArgumentBinding extends TransformArgumentBinding {
  /// Creates a nested-transform binding.
  const NestedTransformArgumentBinding({
    required this.nestedTransform,
    required super.parameterRef,
    required super.nullPolicy,
    required super.missingPolicy,
  });

  /// Nested transform producing the argument value.
  final DecompositionValueTransform nestedTransform;

  @override
  bool operator ==(Object other) =>
      other is NestedTransformArgumentBinding &&
      other.nestedTransform == nestedTransform &&
      other.parameterRef == parameterRef &&
      other.nullPolicy == nullPolicy &&
      other.missingPolicy == missingPolicy;

  @override
  int get hashCode =>
      Object.hash(nestedTransform, parameterRef, nullPolicy, missingPolicy);
}

/// Source of a transform argument value.
///
/// The sealed [TransformArgumentBinding] hierarchy encodes this distinction
/// structurally (one subtype per source), so this enum is **not** a
/// discriminator on the binding itself. It is retained as the shared
/// authoring/lowering vocabulary: the curation authoring model tags its
/// bindings with it, and the reflector parses it from annotations before
/// lowering to the corresponding binding subtype.
enum TransformArgumentSource {
  /// Use the mapped widget property value
  /// ([PropertyValueArgumentBinding]).
  propertyValue,

  /// Use a literal value ([LiteralArgumentBinding]).
  literal,

  /// Use a nested transform ([NestedTransformArgumentBinding]).
  nestedTransform,
}

/// Null-value handling for transform argument bindings.
enum TransformNullPolicy {
  /// Whole transform returns null.
  nullResult,

  /// Omit the target argument.
  omitArgument,

  /// Emit explicit null.
  emitNull,

  /// Treat null as invalid.
  error,
}

/// Missing-value handling for transform argument bindings.
enum TransformMissingPolicy {
  /// Whole transform returns null.
  nullResult,

  /// Omit the target argument.
  omitArgument,

  /// Use the target callable default.
  useDefault,

  /// Treat missing as invalid.
  error,
}

/// Order-sensitive element-wise list equality for value-`==` of types that
/// carry a `List` field. Avoids a `package:collection` dependency in this
/// public, dependency-light package.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
