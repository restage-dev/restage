import 'package:analyzer/dart/element/element.dart' show Element;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Internal representation of one structured-type factory variant.
@immutable
final class FactoryVariantIR {
  /// Creates a factory variant IR entry.
  const FactoryVariantIR({
    required this.wireId,
    required this.sourceKind,
    required this.source,
    this.namedConstructor,
    this.staticAccessor,
    this.argMappings = const {},
    this.argTargetFieldNames = const {},
    this.parameters = const [],
    this.description,
    this.deprecated,
  });

  /// Stable variant wire identity.
  final WireId wireId;

  /// Source member kind.
  final VariantSourceKind sourceKind;

  /// Analyzer source element for the backing member.
  final Element source;

  /// Source constructor name for constructor variants.
  final String? namedConstructor;

  /// Source accessor name for static members.
  final String? staticAccessor;

  /// Source argument names mapped to structured-field targets.
  final Map<String, ArgMapping> argMappings;

  /// Source argument names mapped to structured-field target names.
  final Map<String, List<String>> argTargetFieldNames;

  /// Native callable parameter metadata.
  final List<FactoryParameter> parameters;

  /// Human-readable description.
  final String? description;

  /// Deprecation metadata.
  final DeprecationInfo? deprecated;
}
