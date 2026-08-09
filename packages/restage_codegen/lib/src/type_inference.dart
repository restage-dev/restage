import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The framework value types [inferPropertyType] recognises by name.
///
/// Shared with [frameworkLookalike] so a rejection can explain a familiar name
/// using the same mapping as the classifier.
const Map<String, PropertyType> _frameworkValueTypes = {
  'Widget': PropertyType.widget,
  'Color': PropertyType.color,
  'EdgeInsets': PropertyType.edgeInsets,
  'EdgeInsetsGeometry': PropertyType.edgeInsets,
  'EdgeInsetsDirectional': PropertyType.edgeInsets,
  'Alignment': PropertyType.alignment,
  'AlignmentGeometry': PropertyType.alignment,
  'AlignmentDirectional': PropertyType.alignment,
  'Offset': PropertyType.offset,
  'FontWeight': PropertyType.fontWeight,
  'Duration': PropertyType.duration,
  'Curve': PropertyType.curve,
};

/// A customer type whose name matches a framework value type but whose
/// defining library is not a framework library.
@immutable
final class FrameworkLookalike {
  /// Creates a lookalike record.
  const FrameworkLookalike({required this.name, required this.library});

  /// The framework type name the customer type shares.
  final String name;

  /// The resolved defining library of the customer type.
  final String library;
}

/// Returns a [FrameworkLookalike] when [t] is a customer type sharing its name
/// with a framework value type, or null otherwise.
///
/// Property classification matches on resolved defining library, not on name,
/// so a customer class called Color is correctly not Flutter's Color. This
/// reports that case so a rejection can say why a familiar name was refused.
FrameworkLookalike? frameworkLookalike(DartType t) {
  final element = t.element;
  final name = element?.name;
  if (element == null ||
      name == null ||
      !_frameworkValueTypes.containsKey(name) ||
      isFrameworkValueTypeLibrary(element)) {
    return null;
  }

  return FrameworkLookalike(
    name: name,
    library: element.library?.identifier ?? '<unresolved>',
  );
}

/// Maps a static Dart type to a [PropertyType], or returns `null` if the
/// type isn't supported in the catalog.
///
/// Supported mappings (resolved defining-library identity plus name for
/// non-core types):
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
/// A customer class with the same name as one of these framework types
/// deliberately does not match. Nullability does not affect the result, so
/// `Color?` and `Color` map to the same value.
// Framework-versus-customer identity is decided here. The resulting pairing
// is defensively verified again in widgetbook_native_value_plan.dart.
PropertyType? inferPropertyType(DartType t) {
  // Primitives — nullability irrelevant for these checks.
  if (t.isDartCoreBool) return PropertyType.boolean;
  if (t.isDartCoreInt) return PropertyType.integer;
  if (t.isDartCoreDouble) return PropertyType.real;
  if (t.isDartCoreString) return PropertyType.string;

  // Function types → event.
  if (t is FunctionType) return PropertyType.event;

  if (t is InterfaceType && t.isDartCoreList && t.typeArguments.length == 1) {
    final itemElement = t.typeArguments.single.element;
    if (itemElement?.name == 'Widget' &&
        isFrameworkValueTypeLibrary(itemElement)) {
      return PropertyType.widgetList;
    }
  }

  final element = t.element;
  final frameworkType = isFrameworkValueTypeLibrary(element)
      ? _frameworkValueTypes[element?.name]
      : null;
  if (frameworkType != null) return frameworkType;

  // Dart enums — type's element will be an EnumElement.
  if (element is EnumElement) return PropertyType.enumValue;

  return null;
}
