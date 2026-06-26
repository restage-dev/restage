/// Shared paywall format, catalog schema, validation, and value types used by
/// the Restage SDK and the build-time toolchain.
///
/// This barrel re-exports the public catalog schema (catalog data
/// types, annotations, wire identity, JSON codecs) from
/// `package:rfw_catalog_schema/rfw_catalog_schema.dart` for transitional
/// compatibility with existing call sites. New code should import
/// directly from `rfw_catalog_schema`.
///
/// Consumers also have access to a separate
/// `package:restage_shared/rfw_formats.dart` barrel for the vendored rfw
/// formats sublibrary — kept separate to avoid name collisions with
/// `package:rfw/rfw.dart` for consumers that import both.
library;

export 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

// The analytics exports (lines below) are the behavioral-analytics event
// taxonomy contract — the wire envelope every surface emits.
export 'src/analytics/analytics_app_context.dart';
export 'src/analytics/analytics_event.dart';
export 'src/analytics/analytics_reserved_keys.dart';
export 'src/analytics/analytics_skew.dart';
export 'src/analytics/analytics_taxonomy_registry.dart';
export 'src/analytics/analytics_wire_enums.dart';
export 'src/capability/capability_manifest.dart';
export 'src/capability/capability_sidecar.dart';
export 'src/catalog/curve_vocabulary.dart';
export 'src/catalog/formatted_text_props.dart';
export 'src/catalog/inline_span_limits.dart';
export 'src/entitlements/entitlements.dart';
export 'src/flow_document/flow_action_schema.dart';
export 'src/flow_document/flow_document.dart';
export 'src/flow_document/flow_document_codec.dart';
export 'src/flow_document/flow_document_compatibility.dart';
export 'src/flow_document/flow_document_hash.dart';
export 'src/flow_document/flow_document_validation.dart';
export 'src/flow_document/flow_predicate_sugar.dart';
export 'src/offers/offers.dart';
export 'src/products/restage_entitlement.dart';
export 'src/products/restage_product.dart';
export 'src/surface_document/surface_document.dart';
export 'src/surface_document/surface_document_codec.dart';
export 'src/theme/theme_data_contract.dart';
