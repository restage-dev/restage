import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The JSON primitive categories a [ScalarNode] projects to.
///
/// [integer] is distinct from [number] so a richer projection can emit an
/// integer-typed schema; the behaviour-neutral leaf set treats numeric fields
/// as [number].
enum A2uiScalarType {
  /// A JSON string.
  string,

  /// A JSON number (integer or fractional).
  number,

  /// A JSON integer.
  integer,

  /// A JSON boolean.
  boolean,
}

/// A node in the A2UI data-shape tree.
///
/// The tree is the structural description of one widget data field: the schema
/// projection (a JSON-Schema fragment) and the typed value binding are both
/// exhaustive walks over this sealed hierarchy, so an unhandled shape is a
/// compile error rather than a silent gap.
///
/// Child slots (a single child id, a list of child ids) are **not** data — a
/// widget child is built through the host builder, not bound as a value — so
/// they live in the separate [A2uiChildSlot] hierarchy and never appear here.
///
/// The whole sealed variant set is declared together (so adding the recursive
/// shapes is never a breaking change to an exported sealed type): the leaf set
/// ([ScalarNode], [EnumNode], [ListNode]) covers the catalog-fed fields the
/// emitter has always carried; the recursive [ObjectNode] / [MapNode] /
/// [UnionNode] / [RefNode] shapes are the analyzer-fed reflector's targets,
/// whose schema projection and widget construction land alongside it (until
/// then the emitter fails loud rather than guessing on them).
@immutable
sealed class A2uiSchemaNode {
  const A2uiSchemaNode({this.nullable = false});

  /// Whether this node accepts a JSON `null`.
  ///
  /// Distinct from a parent object's required-set membership: an optional
  /// field may still be non-nullable when present, and a required field may
  /// still be nullable.
  final bool nullable;
}

/// A scalar value (string, number, integer, or boolean).
@immutable
final class ScalarNode extends A2uiSchemaNode {
  /// Creates a scalar node of [type].
  const ScalarNode(this.type, {super.nullable});

  /// The JSON primitive category.
  final A2uiScalarType type;

  @override
  bool operator ==(Object other) =>
      other is ScalarNode && other.type == type && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(type, nullable);
}

/// A closed set of string-valued members, resolved from a Dart enum.
@immutable
final class EnumNode extends A2uiSchemaNode {
  /// Creates an enum node carrying its [members] and source [dartTypeName].
  ///
  /// [members] is defensively copied to an unmodifiable list so the node's
  /// value-identity (used in `Set`/`Map` keys and golden comparisons) can
  /// never be mutated out from under it.
  EnumNode({
    required List<String> members,
    required this.dartTypeName,
    this.libraryUri,
    super.nullable,
  }) : members = List.unmodifiable(members);

  /// The enum member names, in declaration order.
  final List<String> members;

  /// The Dart enum type name (used to construct a fail-closed member lookup).
  final String dartTypeName;

  /// The import URI that defines the enum, when known.
  final String? libraryUri;

  @override
  bool operator ==(Object other) =>
      other is EnumNode &&
      const ListEquality<String>().equals(other.members, members) &&
      other.dartTypeName == dartTypeName &&
      other.libraryUri == libraryUri &&
      other.nullable == nullable;

  @override
  int get hashCode => Object.hash(
        const ListEquality<String>().hash(members),
        dartTypeName,
        libraryUri,
        nullable,
      );
}

/// A homogeneous list whose items are described by [element].
@immutable
final class ListNode extends A2uiSchemaNode {
  /// Creates a list node over [element].
  const ListNode({required this.element, super.nullable});

  /// The shape of each list item.
  final A2uiSchemaNode element;

  @override
  bool operator ==(Object other) =>
      other is ListNode &&
      other.element == element &&
      other.nullable == nullable;

  @override
  int get hashCode => Object.hash(element, nullable);
}

/// A nested object whose named [fields] each carry their own shape.
///
/// [required] names the fields that must be present. [defId] is set when the
/// object is shared/recursive and emitted once into the schema definitions,
/// referenced elsewhere by a [RefNode]. [construction] records how the Dart
/// value is reconstructed from decoded JSON (the widget-builder side); it is
/// set by the analyzer-fed reflector and absent on schema-only nodes.
@immutable
final class ObjectNode extends A2uiSchemaNode {
  /// Creates an object node over [fields] with the [required] field set.
  ObjectNode({
    required Map<String, A2uiSchemaNode> fields,
    required Set<String> required,
    this.defId,
    this.construction,
    super.nullable,
  })  : fields = Map.unmodifiable(fields),
        required = Set.unmodifiable(required);

  /// The named fields and their shapes.
  final Map<String, A2uiSchemaNode> fields;

  /// The names of the fields that must be present.
  final Set<String> required;

  /// The shared-definition id when this object is emitted into `$defs`.
  final String? defId;

  /// How the Dart value is reconstructed from decoded JSON, when known.
  final A2uiObjectConstruction? construction;

  @override
  bool operator ==(Object other) =>
      other is ObjectNode &&
      const MapEquality<String, A2uiSchemaNode>()
          .equals(other.fields, fields) &&
      const SetEquality<String>().equals(other.required, required) &&
      other.defId == defId &&
      other.construction == construction &&
      other.nullable == nullable;

  @override
  int get hashCode => Object.hash(
        const MapEquality<String, A2uiSchemaNode>().hash(fields),
        const SetEquality<String>().hash(required),
        defId,
        construction,
        nullable,
      );
}

/// How an [ObjectNode]'s Dart value is reconstructed from decoded JSON.
///
/// A class object is built through a named constructor; a record is built
/// through an inline named-record literal. Used only by the widget-builder
/// projection; the schema projection ignores it.
@immutable
sealed class A2uiObjectConstruction {
  const A2uiObjectConstruction();
}

/// A named data class built through its constructor — `TypeName(p1: …)` /
/// `TypeName(v1, …)`, or `TypeName.constructorName(…)` for a named constructor.
@immutable
final class A2uiClassConstruction extends A2uiObjectConstruction {
  /// Creates a class construction descriptor.
  A2uiClassConstruction({
    required this.dartTypeName,
    required List<A2uiConstructorParameter> parameters,
    this.libraryUri,
    this.constructorName,
  }) : parameters = List.unmodifiable(parameters);

  /// The Dart class name to construct.
  final String dartTypeName;

  /// The import URI that defines the class, when known.
  final String? libraryUri;

  /// The named-constructor name, or null for the unnamed (default) constructor.
  final String? constructorName;

  /// The constructor parameters, in declaration order.
  final List<A2uiConstructorParameter> parameters;

  @override
  bool operator ==(Object other) =>
      other is A2uiClassConstruction &&
      other.dartTypeName == dartTypeName &&
      other.libraryUri == libraryUri &&
      other.constructorName == constructorName &&
      const ListEquality<A2uiConstructorParameter>()
          .equals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(
        dartTypeName,
        libraryUri,
        constructorName,
        const ListEquality<A2uiConstructorParameter>().hash(parameters),
      );
}

/// A named record built through an inline record literal `(f1: …, f2: …)`.
@immutable
final class A2uiRecordConstruction extends A2uiObjectConstruction {
  /// Creates a record construction descriptor.
  const A2uiRecordConstruction();

  @override
  bool operator ==(Object other) => other is A2uiRecordConstruction;

  @override
  int get hashCode => (A2uiRecordConstruction).hashCode;
}

/// One constructor parameter: its [name] (matching the object field key) and
/// whether it is passed by name (`name: value`) or positionally.
@immutable
final class A2uiConstructorParameter {
  /// Creates a constructor-parameter descriptor.
  const A2uiConstructorParameter({required this.name, required this.named});

  /// The parameter name (also the object's field key).
  final String name;

  /// Whether the parameter is named (`name: value`) rather than positional.
  final bool named;

  @override
  bool operator ==(Object other) =>
      other is A2uiConstructorParameter &&
      other.name == name &&
      other.named == named;

  @override
  int get hashCode => Object.hash(name, named);
}

/// A String-keyed open dictionary whose values all carry [valueType].
///
/// Projects to JSON `additionalProperties`.
@immutable
final class MapNode extends A2uiSchemaNode {
  /// Creates a map node whose values carry [valueType].
  const MapNode({required this.valueType, super.nullable});

  /// The shape of every value in the dictionary.
  final A2uiSchemaNode valueType;

  @override
  bool operator ==(Object other) =>
      other is MapNode &&
      other.valueType == valueType &&
      other.nullable == nullable;

  @override
  int get hashCode => Object.hash(valueType, nullable);
}

/// A discriminated union over a closed set of [variants].
///
/// [discriminatorField] names the field whose value selects the variant; each
/// variant carries a constant discriminator value (derived during projection).
@immutable
final class UnionNode extends A2uiSchemaNode {
  /// Creates a union node over [variants] keyed by [discriminatorField].
  UnionNode({
    required List<A2uiSchemaNode> variants,
    required this.discriminatorField,
    this.defId,
    super.nullable,
  }) : variants = List.unmodifiable(variants);

  /// The closed set of variant shapes.
  final List<A2uiSchemaNode> variants;

  /// The field whose value selects the variant.
  final String discriminatorField;

  /// The shared-definition id when this union is emitted into `$defs`.
  final String? defId;

  @override
  bool operator ==(Object other) =>
      other is UnionNode &&
      const ListEquality<A2uiSchemaNode>().equals(other.variants, variants) &&
      other.discriminatorField == discriminatorField &&
      other.defId == defId &&
      other.nullable == nullable;

  @override
  int get hashCode => Object.hash(
        const ListEquality<A2uiSchemaNode>().hash(variants),
        discriminatorField,
        defId,
        nullable,
      );
}

/// A reference to a shared/recursive shape emitted once into the schema
/// definitions under [defId].
@immutable
final class RefNode extends A2uiSchemaNode {
  /// Creates a reference to the shared definition [defId].
  const RefNode(this.defId, {super.nullable});

  /// The id of the referenced shared definition.
  final String defId;

  @override
  bool operator ==(Object other) =>
      other is RefNode && other.defId == defId && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(defId, nullable);
}

/// A widget child slot.
///
/// A child is built through the host's child builder by id, never bound as a
/// data value, so the child slots form their own sealed hierarchy distinct
/// from [A2uiSchemaNode].
@immutable
sealed class A2uiChildSlot {
  const A2uiChildSlot();
}

/// A single child slot (one child id).
@immutable
final class A2uiChildNode extends A2uiChildSlot {
  /// Creates a single-child slot.
  const A2uiChildNode();

  @override
  bool operator ==(Object other) => other is A2uiChildNode;

  @override
  int get hashCode => (A2uiChildNode).hashCode;
}

/// A list child slot (a list of child ids).
@immutable
final class A2uiChildrenNode extends A2uiChildSlot {
  /// Creates a list-child slot.
  const A2uiChildrenNode();

  @override
  bool operator ==(Object other) => other is A2uiChildrenNode;

  @override
  int get hashCode => (A2uiChildrenNode).hashCode;
}
