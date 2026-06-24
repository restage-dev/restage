import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/ir/policy_decision.dart';
import 'package:rfw_catalog_compiler/src/ir/provenance.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Internal representation of one design token.
@immutable
final class DesignTokenIR {
  /// Creates a design token IR entry.
  const DesignTokenIR({
    required this.wireId,
    required this.name,
    required this.library,
    required this.type,
    required this.resolver,
    required this.literalFallback,
    required this.stability,
    required this.diagnostics,
    required this.provenance,
    required this.policyTrace,
    this.description,
    this.deprecated,
  });

  /// Stable design-token wire identity.
  final WireId wireId;

  /// Token display name.
  final String name;

  /// Owning catalog library.
  final WidgetLibrary library;

  /// Token value type.
  final DesignTokenType type;

  /// Human-readable token description.
  final String? description;

  /// Runtime theme binding.
  final ThemeBindingPath? resolver;

  /// Literal fallback value.
  final Object? literalFallback;

  /// Stability tier.
  final Stability stability;

  /// Diagnostics attached to this token.
  final List<DiagnosticIR> diagnostics;

  /// Source and derivation provenance.
  final ProvenanceIR provenance;

  /// Policy decisions that affected this token.
  final List<PolicyDecisionIR> policyTrace;

  /// Deprecation metadata.
  final DeprecationInfo? deprecated;
}
