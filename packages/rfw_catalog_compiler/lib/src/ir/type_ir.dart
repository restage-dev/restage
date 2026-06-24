import 'package:analyzer/dart/element/element.dart' show EnumElement;
import 'package:analyzer/dart/element/type.dart' show DartType;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Resolved property or structured-field type before schema lowering.
@immutable
final class ResolvedType {
  /// Creates a resolved type.
  const ResolvedType({
    required this.kind,
    this.dartType,
    this.enumElement,
    this.structuredRef,
    this.unionRef,
    this.elementType,
    this.callbackSignature,
    this.valueShape,
  });

  /// Compiler-level type kind.
  final ResolvedTypeKind kind;

  /// Analyzer Dart type, when one exists.
  final DartType? dartType;

  /// Analyzer enum element for enum-valued properties.
  final EnumElement? enumElement;

  /// Structured entry reference for structured-valued properties.
  final WireIdRef? structuredRef;

  /// Union entry reference for union-valued properties.
  final WireIdRef? unionRef;

  /// Element type for list-like resolved types.
  final ResolvedType? elementType;

  /// Callback signature for event properties.
  final String? callbackSignature;

  /// Native semantic value shape carried to schema lowering.
  final CatalogValueShape? valueShape;

  /// Converts this resolved type to the public schema property type.
  PropertyType get loweredPropertyType {
    return switch (kind) {
      ResolvedTypeKind.boolean => PropertyType.boolean,
      ResolvedTypeKind.integer => PropertyType.integer,
      ResolvedTypeKind.real => PropertyType.real,
      ResolvedTypeKind.length => PropertyType.length,
      ResolvedTypeKind.string => PropertyType.string,
      ResolvedTypeKind.stringList => PropertyType.stringList,
      ResolvedTypeKind.booleanList => PropertyType.booleanList,
      ResolvedTypeKind.color => PropertyType.color,
      ResolvedTypeKind.edgeInsets => PropertyType.edgeInsets,
      ResolvedTypeKind.alignment => PropertyType.alignment,
      ResolvedTypeKind.alignmentXY => PropertyType.alignmentXY,
      ResolvedTypeKind.offset => PropertyType.offset,
      ResolvedTypeKind.fontWeight => PropertyType.fontWeight,
      ResolvedTypeKind.duration => PropertyType.duration,
      ResolvedTypeKind.curve => PropertyType.curve,
      ResolvedTypeKind.locale => PropertyType.locale,
      ResolvedTypeKind.paint => PropertyType.paint,
      ResolvedTypeKind.shadowList => PropertyType.shadowList,
      ResolvedTypeKind.fontFeatureList => PropertyType.fontFeatureList,
      ResolvedTypeKind.fontVariationList => PropertyType.fontVariationList,
      ResolvedTypeKind.textDecoration => PropertyType.textDecoration,
      ResolvedTypeKind.enumValue => PropertyType.enumValue,
      ResolvedTypeKind.widget => PropertyType.widget,
      ResolvedTypeKind.widgetList => PropertyType.widgetList,
      ResolvedTypeKind.event => PropertyType.event,
      ResolvedTypeKind.dataReference => PropertyType.dataReference,
      ResolvedTypeKind.gradient => PropertyType.gradient,
      ResolvedTypeKind.border => PropertyType.border,
      ResolvedTypeKind.shapeBorder => PropertyType.shapeBorder,
      ResolvedTypeKind.boxShadowList => PropertyType.boxShadowList,
      ResolvedTypeKind.structured => PropertyType.structured,
      ResolvedTypeKind.inlineSpan => PropertyType.inlineSpan,
      ResolvedTypeKind.decorationImage => PropertyType.decorationImage,
      ResolvedTypeKind.selectionOptionList => PropertyType.selectionOptionList,
      ResolvedTypeKind.union ||
      ResolvedTypeKind.listOfStructured ||
      ResolvedTypeKind.listOfPrimitive ||
      ResolvedTypeKind.generic =>
        throw UnsupportedError(
          'ResolvedTypeKind.${kind.name} cannot lower to the current '
          'PropertyType schema.',
        ),
    };
  }
}

/// Compiler-level property type taxonomy.
enum ResolvedTypeKind {
  /// Boolean value.
  boolean,

  /// Integer scalar.
  integer,

  /// Floating-point scalar.
  real,

  /// Length or dimension scalar.
  length,

  /// String literal.
  string,

  /// List of string literals.
  stringList,

  /// List of boolean literals (a multi-toggle widget's per-child selection
  /// flags).
  booleanList,

  /// Color value.
  color,

  /// EdgeInsets-like value.
  edgeInsets,

  /// Alignment value.
  alignment,

  /// Concrete Alignment value.
  alignmentXY,

  /// Offset value (a `{x, y}` map).
  offset,

  /// FontWeight value.
  fontWeight,

  /// Duration value.
  duration,

  /// Curve value.
  curve,

  /// Locale value.
  locale,

  /// Paint value.
  paint,

  /// List of Shadow values.
  shadowList,

  /// List of FontFeature values.
  fontFeatureList,

  /// List of FontVariation values.
  fontVariationList,

  /// TextDecoration value.
  textDecoration,

  /// Dart enum value.
  enumValue,

  /// Single child widget slot.
  widget,

  /// List child widget slot.
  widgetList,

  /// Event callback.
  event,

  /// Runtime data reference.
  dataReference,

  /// Gradient value.
  gradient,

  /// Box border value.
  border,

  /// ShapeBorder / OutlinedBorder value.
  shapeBorder,

  /// List of box-shadow values.
  boxShadowList,

  /// Structured value.
  structured,

  /// Inline-span tree value (a `Text.rich` / `TextSpan` recursive span map).
  inlineSpan,

  /// DecorationImage value (a `BoxDecoration.image` self-describing image map).
  decorationImage,

  /// Single-select option-list value (a list of `{value, label}` maps).
  selectionOptionList,

  /// Discriminated union value.
  union,

  /// List of structured values.
  listOfStructured,

  /// List of primitive values.
  listOfPrimitive,

  /// Generic type parameter before specialization.
  generic,
}
