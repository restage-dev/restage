import 'package:analyzer/dart/element/element.dart' show ClassElement;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/ir/policy_decision.dart';
import 'package:rfw_catalog_compiler/src/ir/provenance.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Internal representation of one discriminated union.
@immutable
final class UnionIR {
  /// Creates a union IR entry.
  const UnionIR({
    required this.wireId,
    required this.source,
    required this.name,
    required this.library,
    required this.description,
    required this.sourceType,
    required this.memberSourceTypes,
    required this.discriminator,
    required this.members,
    required this.stability,
    required this.diagnostics,
    required this.provenance,
    required this.policyTrace,
    this.deprecated,
  });

  /// Stable union wire identity.
  final WireId wireId;

  /// Analyzer source element.
  final ClassElement source;

  /// Catalog display name.
  final String name;

  /// Owning catalog library.
  final WidgetLibrary library;

  /// Human-readable description.
  final String description;

  /// Fully-qualified name of the abstract base type this union models
  /// (`'package:flutter/src/painting/gradient.dart#Gradient'`).
  final String sourceType;

  /// Per-member source fully-qualified names, index-aligned with
  /// [members] — `members[i]` has source FQN `memberSourceTypes[i]`.
  final List<String> memberSourceTypes;

  /// Discriminator metadata.
  final DiscriminatorSpec discriminator;

  /// Structured members of the union.
  final List<WireIdRef> members;

  /// Stability tier.
  final Stability stability;

  /// Diagnostics attached to this union.
  final List<DiagnosticIR> diagnostics;

  /// Source and derivation provenance.
  final ProvenanceIR provenance;

  /// Policy decisions that affected this union.
  final List<PolicyDecisionIR> policyTrace;

  /// Deprecation metadata.
  final DeprecationInfo? deprecated;
}
