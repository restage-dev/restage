import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Maps a static Dart type to a [PropertyType], or returns `null` if the
/// type isn't supported in the catalog.
///
/// Supported mappings (display-name based for non-core types):
///   * `bool` → [PropertyType.boolean]
///   * `int` → [PropertyType.integer]
///   * `double` → [PropertyType.real]
///   * `String` → [PropertyType.string]
///   * Function types → [PropertyType.event]
///   * `Widget` → [PropertyType.widget]
///   * `List<Widget>` → [PropertyType.widgetList]
///   * `Color` → [PropertyType.color]
///   * `EdgeInsets`, `EdgeInsetsGeometry`, `EdgeInsetsDirectional`
///     → [PropertyType.edgeInsets]
///   * `Alignment`, `AlignmentGeometry`, `AlignmentDirectional`
///     → [PropertyType.alignment]
///   * `Offset` → [PropertyType.offset]
///   * `FontWeight` → [PropertyType.fontWeight]
///   * `Duration` → [PropertyType.duration]
///   * `Curve` → [PropertyType.curve]
///   * Any Dart `enum` type → [PropertyType.enumValue]
///
/// Nullability is stripped before matching so `Color?` and `Color` map to the
/// same value.
PropertyType? inferPropertyType(DartType t) {
  // Primitives — nullability irrelevant for these checks.
  if (t.isDartCoreBool) return PropertyType.boolean;
  if (t.isDartCoreInt) return PropertyType.integer;
  if (t.isDartCoreDouble) return PropertyType.real;
  if (t.isDartCoreString) return PropertyType.string;

  // Function types → event.
  if (t is FunctionType) return PropertyType.event;

  // Strip nullability for display-name based comparison.
  final displayName = t.getDisplayString();
  final stripped = displayName.endsWith('?')
      ? displayName.substring(0, displayName.length - 1)
      : displayName;

  switch (stripped) {
    case 'Widget':
      return PropertyType.widget;
    case 'List<Widget>':
      return PropertyType.widgetList;
    case 'Color':
      return PropertyType.color;
    case 'EdgeInsets':
    case 'EdgeInsetsGeometry':
    case 'EdgeInsetsDirectional':
      return PropertyType.edgeInsets;
    case 'Alignment':
    case 'AlignmentGeometry':
    case 'AlignmentDirectional':
      return PropertyType.alignment;
    case 'Offset':
      return PropertyType.offset;
    case 'FontWeight':
      return PropertyType.fontWeight;
    case 'Duration':
      return PropertyType.duration;
    case 'Curve':
      return PropertyType.curve;
  }

  // Dart enums — type's element will be an EnumElement.
  final element = t.element;
  if (element is EnumElement) return PropertyType.enumValue;

  return null;
}
