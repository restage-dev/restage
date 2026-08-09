import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

import 'package:rfw_catalog_schema/src/default_value_source.dart';
import 'package:rfw_catalog_schema/src/property_metadata.dart';
import 'package:rfw_catalog_schema/src/restage_constraints.dart';
import 'package:rfw_catalog_schema/src/validation_expr.dart';

/// Adds shared catalog metadata to a constructor-bound widget property.
///
/// The unnamed generative constructor defines the catalog property set, so a
/// supported public input does not need this annotation merely to be included.
/// Use [RestageProperty] when a property needs a shared default source,
/// constraint, editor category/priority, schema version, requiredness
/// strengthening, or an explicit description override. Property type remains
/// inferred from the field's static Dart type.
///
/// Two mutually-exclusive defaulting strategies are available; supply at
/// most one:
///
/// * [defaultSource] — the preferred, uniform discriminated default
///   (literal, design-token reference, theme binding, or explicit Flutter
///   delegation).
/// * [defaultBrandToken] — a distinct, supported strategy: a brand-token
///   name the runtime resolves through the theme. It is *not* a
///   [DefaultValueSource] and is carried through unchanged, not projected
///   into one.
///
/// ```dart
/// /// A customer-owned primary action.
/// @RestageWidget(name: 'PrimaryButton', /* ... */)
/// class PrimaryButton extends StatelessWidget {
///   const PrimaryButton({super.key, required this.label, this.color});
///
///   /// Button label.
///   final String label;
///
///   /// Background color.
///   @RestageProperty(
///     defaultBrandToken: 'primary',
///   )
///   final Color? color;
///
///   @override
///   Widget build(BuildContext context) => Text(label);
/// }
/// ```
@immutable
@Target({TargetKind.field, TargetKind.parameter})
final class RestageProperty {
  /// Const annotation constructor.
  ///
  /// Asserts that at most one of [defaultBrandToken] / [defaultSource] is
  /// provided — they are mutually exclusive defaulting
  /// strategies. The assert is debug-only belt-and-suspenders; the binding
  /// enforcement is a hard build error in the code-generation builder, since
  /// a const annotation constructor's assert is stripped in release builds.
  const RestageProperty({
    this.description = '',
    this.required = false,
    this.defaultBrandToken,
    this.defaultSource,
    this.category,
    this.priority,
    this.validationRule,
    this.constraints = RestageConstraints.empty,
    this.minSchemaVersion = 1,
  }) : assert(
          (defaultBrandToken == null ? 0 : 1) +
                  (defaultSource == null ? 0 : 1) <=
              1,
          'Use at most one of defaultBrandToken / defaultSource.',
        );

  /// Description override for the property.
  ///
  /// When empty, code generation reads Dart documentation from the bound field
  /// or constructor parameter.
  final String description;

  /// Whether the catalog must supply this property.
  ///
  /// `true` can strengthen an optional constructor formal. `false` cannot
  /// weaken a Dart-required formal; constructor truth always wins.
  final bool required;

  /// Brand-token name. The editor surfaces this token in the inspector
  /// and the runtime resolves it via the theme. Common values:
  /// `'primary'`, `'onPrimary'`, `'background'`, `'surface'`.
  final String? defaultBrandToken;

  /// Discriminated default source. Preferred over [defaultBrandToken] for
  /// literal defaults — expresses literal / token-reference / theme-binding /
  /// explicit-Flutter-delegation defaults uniformly.
  final DefaultValueSource? defaultSource;

  /// Editor grouping for this property.
  final PropertyCategory? category;

  /// Editor priority for this property.
  final PropertyPriority? priority;

  /// Validation rule applied to authored values.
  final ValidationExpr? validationRule;

  /// Typed JSON-Schema-shaped constraints applied to authored values.
  ///
  /// Typed constraints and [validationRule] are mutually exclusive. The
  /// code-generation and catalog codec boundaries enforce that invariant with
  /// actionable diagnostics.
  final RestageConstraints constraints;

  /// Catalog schema version that introduced this property. Defaults
  /// to 1.
  final int minSchemaVersion;
}
