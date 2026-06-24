import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The callable fields of a sealed [FactoryVariant] — its argument mappings and
/// parameters — projected flat so the emitter / translator can iterate them
/// uniformly across variants. The accessor kinds (static getter / const field)
/// are zero-arg and carry neither, so this reports empty for them.
typedef FactoryVariantCallableFields = ({
  Map<String, ArgMapping> argMappings,
  List<FactoryParameter> parameters,
});

/// Projects [variant] onto its callable [FactoryVariantCallableFields].
FactoryVariantCallableFields factoryVariantCallableFields(
  FactoryVariant variant,
) =>
    switch (variant) {
      ConstructorVariant(:final argMappings, :final parameters) ||
      StaticMethodVariant(:final argMappings, :final parameters) =>
        (argMappings: argMappings, parameters: parameters),
      StaticGetterVariant() || ConstValueVariant() => (
          argMappings: const {},
          parameters: const [],
        ),
    };
