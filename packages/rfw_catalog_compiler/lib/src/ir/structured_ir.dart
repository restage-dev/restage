import 'package:analyzer/dart/element/element.dart' show ClassElement, Element;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/ir/factory_variant_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/policy_decision.dart';
import 'package:rfw_catalog_compiler/src/ir/property_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/provenance.dart';
import 'package:rfw_catalog_compiler/src/ir/type_ir.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Internal representation of one structured value type.
@immutable
final class StructuredIR {
  /// Creates a structured type IR entry.
  const StructuredIR({
    required this.wireId,
    required this.source,
    required this.name,
    required this.library,
    required this.description,
    required this.fields,
    required this.variants,
    required this.stability,
    required this.diagnostics,
    required this.provenance,
    required this.policyTrace,
    this.referencedUnionFqns = const {},
    this.deprecated,
  });

  /// Stable structured-type wire identity.
  final WireId wireId;

  /// Analyzer class element.
  final ClassElement source;

  /// Catalog display name.
  final String name;

  /// Owning catalog library.
  final WidgetLibrary library;

  /// Human-readable description.
  final String description;

  /// Structured field IR entries.
  final List<StructuredFieldIR> fields;

  /// Factory variants for authoring this value type.
  final List<FactoryVariantIR> variants;

  /// Stability tier.
  final Stability stability;

  /// Diagnostics attached to the structured type.
  final List<DiagnosticIR> diagnostics;

  /// Source and derivation provenance.
  final ProvenanceIR provenance;

  /// Policy decisions that affected this type.
  final List<PolicyDecisionIR> policyTrace;

  /// Fully-qualified names of the registered abstract-union bases this
  /// type's fields reference.
  ///
  /// Populated by the structured walker when a field is typed against a
  /// registered abstract base. A later reference-driven pass resolves
  /// each name into a discriminated union; this set is the channel that
  /// surfaces those references without coupling the walker to the
  /// analyzer-element resolution used to build the unions.
  final Set<String> referencedUnionFqns;

  /// Deprecation metadata.
  final DeprecationInfo? deprecated;
}

/// Internal representation of one structured-type field.
@immutable
final class StructuredFieldIR {
  /// Creates a structured field IR entry.
  const StructuredFieldIR({
    required this.wireId,
    required this.source,
    required this.name,
    required this.type,
    required this.description,
    required this.defaultSource,
    required this.metadata,
    required this.diagnostics,
    this.required = false,
    this.structuredRefFqn,
    this.unionSourceKey,
  });

  /// Stable property-kind wire identity.
  final WireId wireId;

  /// Analyzer source element.
  final Element source;

  /// Source-level field name.
  final String name;

  /// Rich resolved field type.
  final ResolvedType type;

  /// Human-readable description.
  final String description;

  /// Whether the field is required by the canonical constructor.
  final bool required;

  /// Resolved default source, with IR-only provenance.
  final ResolvedDefaultSource? defaultSource;

  /// Editor metadata after policy application.
  final PropertyMetadataIR metadata;

  /// Diagnostics attached to this field.
  final List<DiagnosticIR> diagnostics;

  /// Source FQN of the concrete structured type referenced by this field.
  final String? structuredRefFqn;

  /// Source key of the union referenced by this field.
  final String? unionSourceKey;
}
