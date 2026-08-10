import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The source position whose Widgetbook native-lowering vocabulary applies.
enum WidgetbookPropertyContext {
  /// A direct property on a customer `@RestageWidget`.
  widgetProperty,

  /// A field inside a customer structured value.
  structuredField,
}

/// Whether a catalog property kind has a Widgetbook native-lowering strategy.
enum WidgetbookPropertyCapability {
  /// The backend has a native Dart plan for this kind in this context.
  native,

  /// Automatic stories reject this kind before source rendering.
  rejected,
}

/// Native transport used by a nonempty Widgetbook finite-choice domain.
///
/// This is the exhaustive admission seam shared by constraint validation and
/// constructor-default canonicalization. Nullable `null` is orthogonal to the
/// property's non-null transport.
enum WidgetbookFiniteChoiceTransport {
  /// JSON boolean.
  boolean,

  /// JSON integer.
  integer,

  /// Finite JSON number, normalized for the resolved Dart numeric type.
  real,

  /// JSON string.
  string,

  /// Color transport accepted by [PropertyType.color].
  color,

  /// Integer milliseconds accepted by [PropertyType.duration].
  durationMilliseconds,

  /// Font-weight member transport accepted by [PropertyType.fontWeight].
  fontWeight,

  /// Member name of the exact resolved enum.
  enumMember,
}

/// Returns the finite-choice transport for [type], or `null` when the backend
/// must not admit `allowedValues` for that property family.
WidgetbookFiniteChoiceTransport? widgetbookFiniteChoiceTransport(
  PropertyType type,
) =>
    switch (type) {
      PropertyType.boolean => WidgetbookFiniteChoiceTransport.boolean,
      PropertyType.integer => WidgetbookFiniteChoiceTransport.integer,
      PropertyType.real => WidgetbookFiniteChoiceTransport.real,
      PropertyType.string => WidgetbookFiniteChoiceTransport.string,
      PropertyType.color => WidgetbookFiniteChoiceTransport.color,
      PropertyType.duration =>
        WidgetbookFiniteChoiceTransport.durationMilliseconds,
      PropertyType.fontWeight => WidgetbookFiniteChoiceTransport.fontWeight,
      PropertyType.enumValue => WidgetbookFiniteChoiceTransport.enumMember,
      PropertyType.length ||
      PropertyType.alignmentXY ||
      PropertyType.stringList ||
      PropertyType.booleanList ||
      PropertyType.widget ||
      PropertyType.widgetList ||
      PropertyType.event ||
      PropertyType.structured ||
      PropertyType.dataReference ||
      PropertyType.edgeInsets ||
      PropertyType.alignment ||
      PropertyType.offset ||
      PropertyType.gradient ||
      PropertyType.border ||
      PropertyType.boxShadowList ||
      PropertyType.locale ||
      PropertyType.paint ||
      PropertyType.shadowList ||
      PropertyType.fontFeatureList ||
      PropertyType.fontVariationList ||
      PropertyType.textDecoration ||
      PropertyType.shapeBorder ||
      PropertyType.inlineSpan ||
      PropertyType.decorationImage ||
      PropertyType.selectionOptionList ||
      PropertyType.curve ||
      PropertyType.unknown =>
        null,
    };

/// Classifies every catalog property kind for the Widgetbook backend.
///
/// Keep this exhaustive. Admission and strict analyzer-type validation both
/// consume this function so an accepted kind cannot drift from the backend's
/// declared lowering vocabulary.
WidgetbookPropertyCapability widgetbookPropertyCapability(
  PropertyType type, {
  required WidgetbookPropertyContext context,
}) =>
    switch (context) {
      WidgetbookPropertyContext.widgetProperty => switch (type) {
          PropertyType.widget ||
          PropertyType.widgetList ||
          PropertyType.color ||
          PropertyType.edgeInsets ||
          PropertyType.alignment ||
          PropertyType.offset ||
          PropertyType.fontWeight ||
          PropertyType.duration ||
          PropertyType.curve ||
          PropertyType.boolean ||
          PropertyType.integer ||
          PropertyType.real ||
          PropertyType.string ||
          PropertyType.event ||
          PropertyType.enumValue ||
          PropertyType.structured =>
            WidgetbookPropertyCapability.native,
          PropertyType.length ||
          PropertyType.alignmentXY ||
          PropertyType.stringList ||
          PropertyType.booleanList ||
          PropertyType.dataReference ||
          PropertyType.gradient ||
          PropertyType.border ||
          PropertyType.boxShadowList ||
          PropertyType.locale ||
          PropertyType.paint ||
          PropertyType.shadowList ||
          PropertyType.fontFeatureList ||
          PropertyType.fontVariationList ||
          PropertyType.textDecoration ||
          PropertyType.shapeBorder ||
          PropertyType.inlineSpan ||
          PropertyType.decorationImage ||
          PropertyType.selectionOptionList ||
          PropertyType.unknown =>
            WidgetbookPropertyCapability.rejected,
        },
      WidgetbookPropertyContext.structuredField => switch (type) {
          PropertyType.color ||
          PropertyType.edgeInsets ||
          PropertyType.alignment ||
          PropertyType.offset ||
          PropertyType.fontWeight ||
          PropertyType.duration ||
          PropertyType.curve ||
          PropertyType.boolean ||
          PropertyType.integer ||
          PropertyType.real ||
          PropertyType.string ||
          PropertyType.stringList ||
          PropertyType.enumValue ||
          PropertyType.structured =>
            WidgetbookPropertyCapability.native,
          PropertyType.length ||
          PropertyType.alignmentXY ||
          PropertyType.booleanList ||
          PropertyType.widget ||
          PropertyType.widgetList ||
          PropertyType.event ||
          PropertyType.dataReference ||
          PropertyType.gradient ||
          PropertyType.border ||
          PropertyType.boxShadowList ||
          PropertyType.locale ||
          PropertyType.paint ||
          PropertyType.shadowList ||
          PropertyType.fontFeatureList ||
          PropertyType.fontVariationList ||
          PropertyType.textDecoration ||
          PropertyType.shapeBorder ||
          PropertyType.inlineSpan ||
          PropertyType.decorationImage ||
          PropertyType.selectionOptionList ||
          PropertyType.unknown =>
            WidgetbookPropertyCapability.rejected,
        },
    };
