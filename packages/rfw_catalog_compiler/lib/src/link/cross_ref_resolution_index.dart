import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/factory_variant_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/union_ir.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Plain-data cross-reference resolution keys captured before lowering.
@immutable
final class CrossRefResolutionIndex {
  /// Creates a cross-reference resolution index.
  const CrossRefResolutionIndex({
    this.structuredRefFqnByField = const {},
    this.unionSourceKeyByField = const {},
    this.argTargetFieldNames = const {},
    this.decompositionStructuredSourceByWidget = const {},
    this.decompositionConstructionVariantByWidget = const {},
    this.decompositionFieldMappingNames = const {},
    this.decompositionParameterMappingNames = const {},
    this.decompositionTransformStructuredSourceByMapping = const {},
    this.decompositionTransformVariantByMapping = const {},
    this.decompositionTransformParameterLabels = const {},
    this.decompositionTransformStructuredSourceByPath = const {},
    this.decompositionTransformVariantByPath = const {},
    this.decompositionTransformParameterLabelsByPath = const {},
  });

  /// `(ownerStructuredSourceType, fieldName) -> target structured FQN`.
  final Map<(String, String), String> structuredRefFqnByField;

  /// `(ownerStructuredSourceType, fieldName) -> target union source key`.
  final Map<(String, String), String> unionSourceKeyByField;

  /// `(ownerStructuredSourceType, variantId, argName) -> target field names`.
  final Map<(String, String, String), List<String>> argTargetFieldNames;

  /// `(widgetFlutterType, recipeIndex) -> result structured source FQN`.
  final Map<(String, int), String> decompositionStructuredSourceByWidget;

  /// `(widgetFlutterType, recipeIndex) -> construction variant identity`.
  final Map<(String, int), String> decompositionConstructionVariantByWidget;

  /// `(widgetFlutterType, recipeIndex, mappingIndex) -> field/property names`.
  final Map<(String, int, int), (String, String)>
      decompositionFieldMappingNames;

  /// `(widgetFlutterType, recipeIndex, mappingIndex) -> parameter/property`.
  final Map<(String, int, int), (String, String)>
      decompositionParameterMappingNames;

  /// `(widgetFlutterType, recipeIndex, mappingIndex) -> transform result FQN`.
  final Map<(String, int, int), String>
      decompositionTransformStructuredSourceByMapping;

  /// `(widgetFlutterType, recipeIndex, mappingIndex) -> transform variant`.
  final Map<(String, int, int), String> decompositionTransformVariantByMapping;

  /// `(widgetFlutterType, recipeIndex, mappingIndex, bindingIndex) -> label`.
  final Map<(String, int, int, int), String>
      decompositionTransformParameterLabels;

  /// `(widgetFlutterType, recipeIndex, mappingIndex, transformPath) -> FQN`.
  ///
  /// `transformPath == ''` denotes the top-level mapping transform. Nested
  /// binding transforms use paths such as
  /// `argumentBindings[0].nestedTransform`.
  final Map<(String, int, int, String), String>
      decompositionTransformStructuredSourceByPath;

  /// `(widgetFlutterType, recipeIndex, mappingIndex, transformPath) ->
  /// variant`.
  final Map<(String, int, int, String), String>
      decompositionTransformVariantByPath;

  /// `(widgetFlutterType, recipeIndex, mappingIndex, transformPath,
  /// bindingIndex) -> label`.
  final Map<(String, int, int, String, int), String>
      decompositionTransformParameterLabelsByPath;

  /// Merges two partial indexes.
  ///
  /// Conflict-detecting: a duplicate key whose target *differs* would otherwise
  /// silently last-win and feed the link pass a wrong cross-reference target,
  /// so it throws [CrossRefIndexException] with the site. Identical re-entries
  /// (the deterministic per-library norm — a structured type reachable from two
  /// widgets contributes the same data each time) are allowed.
  CrossRefResolutionIndex merge(CrossRefResolutionIndex other) {
    return CrossRefResolutionIndex(
      structuredRefFqnByField: _mergeStringMap(
        structuredRefFqnByField,
        other.structuredRefFqnByField,
        'structuredRefFqnByField',
      ),
      unionSourceKeyByField: _mergeStringMap(
        unionSourceKeyByField,
        other.unionSourceKeyByField,
        'unionSourceKeyByField',
      ),
      argTargetFieldNames: _mergeListMap(
        argTargetFieldNames,
        other.argTargetFieldNames,
        'argTargetFieldNames',
      ),
      decompositionStructuredSourceByWidget: _mergeValueMap(
        decompositionStructuredSourceByWidget,
        other.decompositionStructuredSourceByWidget,
        'decompositionStructuredSourceByWidget',
      ),
      decompositionConstructionVariantByWidget: _mergeValueMap(
        decompositionConstructionVariantByWidget,
        other.decompositionConstructionVariantByWidget,
        'decompositionConstructionVariantByWidget',
      ),
      decompositionFieldMappingNames: _mergeValueMap(
        decompositionFieldMappingNames,
        other.decompositionFieldMappingNames,
        'decompositionFieldMappingNames',
      ),
      decompositionParameterMappingNames: _mergeValueMap(
        decompositionParameterMappingNames,
        other.decompositionParameterMappingNames,
        'decompositionParameterMappingNames',
      ),
      decompositionTransformStructuredSourceByMapping: _mergeValueMap(
        decompositionTransformStructuredSourceByMapping,
        other.decompositionTransformStructuredSourceByMapping,
        'decompositionTransformStructuredSourceByMapping',
      ),
      decompositionTransformVariantByMapping: _mergeValueMap(
        decompositionTransformVariantByMapping,
        other.decompositionTransformVariantByMapping,
        'decompositionTransformVariantByMapping',
      ),
      decompositionTransformParameterLabels: _mergeValueMap(
        decompositionTransformParameterLabels,
        other.decompositionTransformParameterLabels,
        'decompositionTransformParameterLabels',
      ),
      decompositionTransformStructuredSourceByPath: _mergeValueMap(
        decompositionTransformStructuredSourceByPath,
        other.decompositionTransformStructuredSourceByPath,
        'decompositionTransformStructuredSourceByPath',
      ),
      decompositionTransformVariantByPath: _mergeValueMap(
        decompositionTransformVariantByPath,
        other.decompositionTransformVariantByPath,
        'decompositionTransformVariantByPath',
      ),
      decompositionTransformParameterLabelsByPath: _mergeValueMap(
        decompositionTransformParameterLabelsByPath,
        other.decompositionTransformParameterLabelsByPath,
        'decompositionTransformParameterLabelsByPath',
      ),
    );
  }

  static Map<(String, String), String> _mergeStringMap(
    Map<(String, String), String> base,
    Map<(String, String), String> incoming,
    String mapName,
  ) {
    final result = Map<(String, String), String>.of(base);
    for (final entry in incoming.entries) {
      final existing = result[entry.key];
      if (existing != null && existing != entry.value) {
        throw CrossRefIndexException(
          'conflicting $mapName entry for ${entry.key}: '
          '"$existing" vs "${entry.value}"',
        );
      }
      result[entry.key] = entry.value;
    }
    return Map.unmodifiable(result);
  }

  static Map<(String, String, String), List<String>> _mergeListMap(
    Map<(String, String, String), List<String>> base,
    Map<(String, String, String), List<String>> incoming,
    String mapName,
  ) {
    final result = <(String, String, String), List<String>>{};
    void put((String, String, String) key, List<String> value) {
      final existing = result[key];
      if (existing != null && !_listEquals(existing, value)) {
        throw CrossRefIndexException(
          'conflicting $mapName entry for $key: $existing vs $value',
        );
      }
      result[key] = List<String>.unmodifiable(value);
    }

    base.forEach(put);
    incoming.forEach(put);
    return Map.unmodifiable(result);
  }

  static Map<K, V> _mergeValueMap<K, V>(
    Map<K, V> base,
    Map<K, V> incoming,
    String mapName,
  ) {
    final result = Map<K, V>.of(base);
    for (final entry in incoming.entries) {
      final existing = result[entry.key];
      if (existing != null && existing != entry.value) {
        throw CrossRefIndexException(
          'conflicting $mapName entry for ${entry.key}: '
          '"$existing" vs "${entry.value}"',
        );
      }
      result[entry.key] = entry.value;
    }
    return Map.unmodifiable(result);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Thrown when [CrossRefResolutionIndex.merge] hits a duplicate key whose
/// targets differ — the upstream capture produced conflicting cross-reference
/// resolution data for one site.
final class CrossRefIndexException implements Exception {
  /// Creates a cross-reference index exception.
  const CrossRefIndexException(this.message);

  /// Diagnostic message containing the conflicting key and both targets.
  final String message;

  @override
  String toString() => 'CrossRefIndexException: $message';
}

/// Stable plain-data identity for a lowered factory variant.
String variantIdentity(FactoryVariant variant) {
  final (namedConstructor, staticAccessor) = switch (variant) {
    ConstructorVariant(:final namedConstructor) => (namedConstructor, null),
    StaticMethodVariant(:final staticAccessor) => (null, staticAccessor),
    StaticGetterVariant(:final staticAccessor) => (null, staticAccessor),
    ConstValueVariant(:final staticAccessor) => (null, staticAccessor),
  };
  return '${factoryVariantSourceKind(variant).name}|'
      '${namedConstructor ?? ''}|'
      '${staticAccessor ?? ''}';
}

/// Stable plain-data identity for a factory variant IR entry.
String variantIdentityIr(FactoryVariantIR variant) {
  return '${variant.sourceKind.name}|'
      '${variant.namedConstructor ?? ''}|'
      '${variant.staticAccessor ?? ''}';
}

/// Builds the cross-reference index for one structured type IR entry.
CrossRefResolutionIndex crossRefIndexForStructured(StructuredIR ir) {
  final owner = ir.provenance.flutterType;
  final structuredRefs = <(String, String), String>{};
  final unionRefs = <(String, String), String>{};
  final argTargets = <(String, String, String), List<String>>{};

  for (final field in ir.fields) {
    final structuredRefFqn = field.structuredRefFqn;
    if (structuredRefFqn != null) {
      structuredRefs[(owner, field.name)] = structuredRefFqn;
    }
    final unionSourceKey = field.unionSourceKey;
    if (unionSourceKey != null) {
      unionRefs[(owner, field.name)] = unionSourceKey;
    }
  }

  for (final variant in ir.variants) {
    final variantId = variantIdentityIr(variant);
    for (final entry in variant.argTargetFieldNames.entries) {
      argTargets[(owner, variantId, entry.key)] =
          List<String>.unmodifiable(entry.value);
    }
  }

  return CrossRefResolutionIndex(
    structuredRefFqnByField: Map.unmodifiable(structuredRefs),
    unionSourceKeyByField: Map.unmodifiable(unionRefs),
    argTargetFieldNames: Map.unmodifiable(argTargets),
  );
}

/// Unions resolve from lowered member source types, so they add no index data.
CrossRefResolutionIndex crossRefIndexForUnion(UnionIR ir) {
  return const CrossRefResolutionIndex();
}
