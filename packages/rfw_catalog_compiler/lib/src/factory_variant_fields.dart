import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The kind-specific fields of a sealed [FactoryVariant], projected flat.
///
/// The compiler keeps internal flat representations of a variant (the variant
/// IR mirror, the wire-ID event-log shape key, and pairwise diffing) that
/// predate the sealed schema type. This projection is the single place that
/// destructures the sealed subtype onto those nullable fields. The accessor
/// kinds (static getter / const field) are zero-arg, so they carry no argument
/// mappings or callable parameters.
typedef FactoryVariantFields = ({
  String? namedConstructor,
  String? staticAccessor,
  Map<String, ArgMapping> argMappings,
  List<FactoryParameter> parameters,
});

/// Projects [variant] onto its flat [FactoryVariantFields].
FactoryVariantFields factoryVariantFields(FactoryVariant variant) =>
    switch (variant) {
      ConstructorVariant(
        :final namedConstructor,
        :final argMappings,
        :final parameters,
      ) =>
        (
          namedConstructor: namedConstructor,
          staticAccessor: null,
          argMappings: argMappings,
          parameters: parameters,
        ),
      StaticMethodVariant(
        :final staticAccessor,
        :final argMappings,
        :final parameters,
      ) =>
        (
          namedConstructor: null,
          staticAccessor: staticAccessor,
          argMappings: argMappings,
          parameters: parameters,
        ),
      StaticGetterVariant(:final staticAccessor) => (
          namedConstructor: null,
          staticAccessor: staticAccessor,
          argMappings: const {},
          parameters: const [],
        ),
      ConstValueVariant(:final staticAccessor) => (
          namedConstructor: null,
          staticAccessor: staticAccessor,
          argMappings: const {},
          parameters: const [],
        ),
    };
