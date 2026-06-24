import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/default_value_source.dart';
import 'package:rfw_catalog_schema/src/property_metadata.dart';
import 'package:rfw_catalog_schema/src/validation_expr.dart';

/// Marks a field on a `@RestageWidget`-annotated class as a catalog
/// property.
///
/// Property type is inferred from the field's static Dart type by the
/// code-generation builder. Three mutually-exclusive defaulting strategies
/// are available; supply at most one:
///
/// * [defaultSource] — the preferred, uniform discriminated default
///   (literal, design-token reference, theme binding, or explicit Flutter
///   delegation).
/// * `defaultValue` — **deprecated**; a literal shortcut that folds into a
///   [LiteralDefault] on the resolved entry. Use [defaultSource] with a
///   [LiteralDefault] instead.
/// * [defaultBrandToken] — a distinct, supported strategy: a brand-token
///   name the runtime resolves through the theme. It is *not* a
///   [DefaultValueSource] and is carried through unchanged, not projected
///   into one.
///
/// ```dart
/// @RestageWidget(name: 'PrimaryButton', /* ... */)
/// class PrimaryButton extends StatelessWidget {
///   @RestageProperty(description: 'Button label.', required: true)
///   final String label;
///
///   @RestageProperty(
///     description: 'Background colour.',
///     defaultBrandToken: 'primary',
///   )
///   final Color color;
/// }
/// ```
@immutable
final class RestageProperty {
  /// Const annotation constructor.
  ///
  /// Asserts that at most one of [defaultValue] / [defaultBrandToken] /
  /// [defaultSource] is provided — they are mutually exclusive defaulting
  /// strategies. The assert is debug-only belt-and-suspenders; the binding
  /// enforcement is a hard build error in the code-generation builder, since
  /// a const annotation constructor's assert is stripped in release builds.
  const RestageProperty({
    required this.description,
    this.required = false,
    @Deprecated('Use defaultSource: LiteralDefault(value) instead.')
    this.defaultValue,
    this.defaultBrandToken,
    this.defaultSource,
    this.category,
    this.priority,
    this.validationRule,
    this.minSchemaVersion = 1,
  }) : assert(
          // The mutual-exclusion invariant still counts the deprecated
          // `defaultValue` — a customer may set it, and it remains exclusive
          // with the other two strategies.
          (defaultValue == null ? 0 : 1) +
                  (defaultBrandToken == null ? 0 : 1) +
                  (defaultSource == null ? 0 : 1) <=
              1,
          'Use at most one of defaultValue / defaultBrandToken / '
          'defaultSource.',
        );

  /// Human-readable description used by editor tooltips and docgen.
  final String description;

  /// Whether the property must be supplied at construction. Defaults
  /// to false.
  final bool required;

  /// Literal default value. Codegen omits the field from emitted RFW
  /// when the supplied value matches.
  ///
  /// Deprecated: use [defaultSource] with a [LiteralDefault] — it is the
  /// uniform discriminated default and folds to the same resolved value.
  @Deprecated('Use defaultSource: LiteralDefault(value) instead.')
  final Object? defaultValue;

  /// Brand-token name. The editor surfaces this token in the inspector
  /// and the runtime resolves it via the theme. Common values:
  /// `'primary'`, `'onPrimary'`, `'background'`, `'surface'`.
  final String? defaultBrandToken;

  /// Discriminated default source. Preferred over the deprecated
  /// `defaultValue` and over [defaultBrandToken] for literal defaults —
  /// expresses literal / token-reference / theme-binding /
  /// explicit-Flutter-delegation defaults uniformly.
  final DefaultValueSource? defaultSource;

  /// Editor grouping for this property.
  final PropertyCategory? category;

  /// Editor priority for this property.
  final PropertyPriority? priority;

  /// Validation rule applied to authored values.
  final ValidationExpr? validationRule;

  /// Catalog schema version that introduced this property. Defaults
  /// to 1.
  final int minSchemaVersion;
}
