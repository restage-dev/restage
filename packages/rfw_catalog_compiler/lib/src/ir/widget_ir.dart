import 'package:analyzer/dart/element/element.dart'
    show ClassElement, ConstructorElement;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/decomposition_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/ir/policy_decision.dart';
import 'package:rfw_catalog_compiler/src/ir/property_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/provenance.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Internal representation of one widget entry.
///
/// Each named constructor on a Flutter widget class becomes a distinct
/// `WidgetIR`; factory variants are reserved for structured types.
@immutable
final class WidgetIR {
  /// Creates a widget IR entry.
  const WidgetIR({
    required this.wireId,
    required this.source,
    required this.constructor,
    required this.name,
    required this.library,
    required this.category,
    required this.description,
    required this.properties,
    required this.decomposes,
    required this.fires,
    required this.childrenSlot,
    required this.stability,
    required this.diagnostics,
    required this.provenance,
    required this.policyTrace,
    this.sinceVersion = kBaselineCatalogVersion,
    this.deprecatedSince,
    this.deprecated,
  });

  /// Stable widget wire identity.
  final WireId wireId;

  /// Analyzer class element.
  final ClassElement source;

  /// Analyzer constructor element for this specific widget entry.
  final ConstructorElement constructor;

  /// Catalog display name.
  final String name;

  /// Owning catalog library.
  final WidgetLibrary library;

  /// Widget category.
  final WidgetCategory category;

  /// Human-readable description.
  final String description;

  /// Property IR entries exposed by this widget.
  final List<PropertyIR> properties;

  /// Structured decomposition recipes for this widget.
  final List<DecompositionIR> decomposes;

  /// Event names this widget can fire.
  final List<WidgetEventName> fires;

  /// Children slot accepted by the widget.
  final ChildrenSlot childrenSlot;

  /// Catalog content version that introduced this widget. Defaults to
  /// [kBaselineCatalogVersion]; preserved end-to-end through lowering so a
  /// non-baseline entry keeps its version into the public schema.
  final int sinceVersion;

  /// Stability tier.
  final Stability stability;

  /// Diagnostics attached to this widget.
  final List<DiagnosticIR> diagnostics;

  /// Source and derivation provenance.
  final ProvenanceIR provenance;

  /// Policy decisions that affected this widget.
  final List<PolicyDecisionIR> policyTrace;

  /// Legacy v2 deprecation marker.
  final String? deprecatedSince;

  /// Deprecation metadata.
  final DeprecationInfo? deprecated;
}
