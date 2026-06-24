import 'package:analyzer/dart/element/element.dart' show Element;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/ir/policy_decision.dart';
import 'package:rfw_catalog_compiler/src/ir/type_ir.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Internal representation of one widget property.
@immutable
final class PropertyIR {
  /// Creates a property IR entry.
  const PropertyIR({
    required this.wireId,
    required this.source,
    required this.name,
    required this.type,
    required this.description,
    required this.defaultSource,
    required this.metadata,
    required this.policyTrace,
    required this.diagnostics,
    this.required = false,
    this.legacyDefaultValue,
    this.legacyDefaultBrandToken,
    this.positional = false,
    this.enumType,
    this.widgetType,
    this.callbackSignature,
  });

  /// Stable property wire identity.
  final WireId wireId;

  /// Analyzer source element for the parameter or field.
  final Element source;

  /// Source-level property name.
  final String name;

  /// Rich resolved type.
  final ResolvedType type;

  /// Human-readable description.
  final String description;

  /// Whether the property is required at construction.
  final bool required;

  /// Resolved default source, with IR-only provenance.
  final ResolvedDefaultSource? defaultSource;

  /// Transitional v2 literal default carried until all emitters consume
  /// [defaultSource] directly.
  final Object? legacyDefaultValue;

  /// Transitional v2 brand-token default carried until the compiler
  /// allocates design-token wire IDs; these cannot be losslessly
  /// represented as [TokenRefDefault] yet.
  final String? legacyDefaultBrandToken;

  /// Editor and validation metadata after policy application.
  final PropertyMetadataIR metadata;

  /// Whether this property lowers as a positional argument.
  final bool positional;

  /// Enum type label for enum-valued properties.
  final String? enumType;

  /// Widget slot type override for widget-valued properties.
  final String? widgetType;

  /// Event callback signature override.
  final String? callbackSignature;

  /// Policy decisions that affected the property.
  final List<PolicyDecisionIR> policyTrace;

  /// Diagnostics attached to the property.
  final List<DiagnosticIR> diagnostics;
}

/// Internal default source with public lowering target plus provenance.
@immutable
final class ResolvedDefaultSource {
  /// Creates a resolved default source.
  const ResolvedDefaultSource({
    required this.lowered,
    required this.shape,
    required this.origin,
  });

  /// Public schema default-value source produced during lowering.
  final DefaultValueSource lowered;

  /// Analyzer-level shape before public schema flattening.
  final ResolvedDefaultShape shape;

  /// Source of the default decision.
  final ResolvedDefaultOrigin origin;
}

/// Internal discriminator for resolved default shapes.
enum ResolvedDefaultShape {
  /// Literal default.
  literal,

  /// Constant identifier default, such as `Alignment.center`.
  constIdentifier,

  /// Constant factory default.
  constFactory,

  /// Design token reference.
  tokenReference,

  /// Theme binding.
  themeBinding,

  /// Delegation to Flutter's constructor default.
  flutterCtorDefault,
}

/// Origin of a resolved default decision.
enum ResolvedDefaultOrigin {
  /// Constructor parameter default value.
  paramDefaultValue,

  /// Curation override.
  curationOverride,

  /// Theme-binding inference.
  themeBindingInference,

  /// Design-token inference.
  tokenInference,

  /// Customer annotation.
  customerAnnotation,
}

/// Metadata attached to a property after inference and overrides.
@immutable
final class PropertyMetadataIR {
  /// Creates property metadata.
  const PropertyMetadataIR({
    this.mutuallyExclusiveWith,
    this.requiresAncestor,
    this.category,
    this.priority,
    this.validationRule,
    this.deprecated,
    this.synthetic,
    this.firesAs,
  });

  /// Properties on the same owner that this property excludes.
  final List<WireId>? mutuallyExclusiveWith;

  /// Required ancestor label, if one applies.
  final String? requiresAncestor;

  /// Editor category.
  final PropertyCategory? category;

  /// Editor priority.
  final PropertyPriority? priority;

  /// Validation rule for authored values.
  final ValidationExpr? validationRule;

  /// Deprecation metadata.
  final DeprecationInfo? deprecated;

  /// Synthetic property lowering strategy.
  final String? synthetic;

  /// Event taxonomy name used by `fires`.
  final String? firesAs;
}
