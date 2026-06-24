import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/discriminator_spec.dart';
import 'package:rfw_catalog_schema/src/native_decompose.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Recipe for flattening a structured parameter type into the flat
/// property surface the rendering layer consumes.
///
/// **Canonical identity is wire-ID-based.** [structuredRef] points at
/// the structured type via its `(library, wireId)` tuple, and
/// [flatProperties] maps structured-field wire IDs to consuming
/// property wire IDs. Renames on either side preserve the recipe.
///
/// Recipes are recursive: a structured type whose fields contain other
/// structured types (e.g. `BoxDecoration` containing a `BorderRadius`)
/// decomposes top-down — outer recipe first, then inner factory
/// translation.
@immutable
final class DecompositionRecipe {
  /// Const constructor.
  const DecompositionRecipe({
    required this.structuredRef,
    required this.flatProperties,
    this.targetArg,
    this.construction,
    this.fieldMappings = const [],
    this.parameterMappings = const [],
    this.discriminator,
  });

  /// Wire-ID reference to the structured type this recipe decomposes.
  /// Cross-library tuple so structured types defined in one library
  /// can be decomposed onto widgets in another. Renames of the
  /// structured type don't churn recipes.
  final WireIdRef structuredRef;

  /// Maps structured-type field wire IDs to flat property wire IDs on
  /// the consuming widget. Renames on either side preserve the recipe.
  final Map<WireId, WireId> flatProperties;

  /// Widget constructor argument that receives the reconstructed value.
  final String? targetArg;

  /// Native construction used to reconstruct [structuredRef].
  final FactoryInvocation? construction;

  /// Explicit native field mappings.
  final List<DecompositionFieldMapping> fieldMappings;

  /// Explicit native parameter mappings for constructor-only parameters.
  final List<DecompositionParameterMapping> parameterMappings;

  /// Discriminator selecting which structured-type member of a union
  /// the recipe should decompose. Populated when the consuming property
  /// is union-typed; null for flat structured types.
  final DiscriminatorSpec? discriminator;
}
