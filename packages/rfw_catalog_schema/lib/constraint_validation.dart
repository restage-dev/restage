/// Narrow build-tool entrypoint for target-neutral constraint validation.
///
/// Customer authoring APIs remain in `rfw_catalog_schema.dart`; generators
/// import this library explicitly when they need the shared value contract.
library;

export 'src/constraint_value_validation.dart'
    show validateRestageConstraintValues;
