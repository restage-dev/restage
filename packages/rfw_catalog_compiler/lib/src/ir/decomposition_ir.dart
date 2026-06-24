import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Internal representation of one structured-type decomposition recipe.
@immutable
final class DecompositionIR {
  /// Creates a decomposition recipe IR.
  const DecompositionIR({
    required this.structuredRef,
    required this.flatPropertyRefs,
    this.targetArg,
    this.construction,
    this.fieldMappings = const [],
    this.parameterMappings = const [],
    this.discriminator,
  });

  /// Structured type being flattened.
  final WireIdRef structuredRef;

  /// Structured-field IDs mapped to flat widget-property IDs.
  final Map<WireId, WireId> flatPropertyRefs;

  /// Widget constructor argument that receives the reconstructed value.
  final String? targetArg;

  /// Native construction used to reconstruct [structuredRef].
  final FactoryInvocation? construction;

  /// Native field mappings for this decompose recipe.
  final List<DecompositionFieldMapping> fieldMappings;

  /// Native parameter mappings for this decompose recipe.
  final List<DecompositionParameterMapping> parameterMappings;

  /// Optional union discriminator used by this recipe.
  final DiscriminatorSpec? discriminator;
}
