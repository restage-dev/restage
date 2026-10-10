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
///
/// The legacy behavioral-analytics event taxonomy is no longer exported here.
/// It lives behind `package:restage_shared/legacy_analytics.dart`, is retained
/// only for the legacy analytics runtime the SDK still ships, and retires with
/// it. New code measures through
/// `package:restage_measurement_schema/restage_measurement_schema.dart`.
library;

export 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'src/bundled_measurement_target_profile.dart';
export 'src/capability/blob_render_capability_gate.dart';
export 'src/capability/capability_manifest.dart';
export 'src/capability/capability_sidecar.dart';
export 'src/capability/installed_capability.dart';
export 'src/capability/library_compatibility.dart';
export 'src/capability/library_contract_header.dart';
export 'src/capability/surface_fit.dart';
export 'src/capability/widget_vocabulary.dart';
export 'src/catalog/curve_vocabulary.dart';
export 'src/catalog/formatted_text_props.dart';
export 'src/catalog/inline_span_limits.dart';
export 'src/device/device_data_contract.dart';
export 'src/flow_document/flow_action_schema.dart';
export 'src/flow_document/flow_active_render_gate.dart';
export 'src/flow_document/flow_document.dart';
export 'src/flow_document/flow_document_codec.dart';
export 'src/flow_document/flow_document_compatibility.dart';
export 'src/flow_document/flow_document_hash.dart';
export 'src/flow_document/flow_lifecycle_reachability.dart';
export 'src/flow_document/flow_document_validation.dart';
export 'src/flow_document/flow_predicate_sugar.dart';
export 'src/flow_document/general_render_gate.dart';
export 'src/flow_document/paywall_screen_assets.dart';
export 'src/fonts/sfnt_cmap.dart';
export 'src/generated_output_path_order.dart';
export 'src/identity/surface_slug.dart';
export 'src/placements/placement_delivery.dart';
export 'src/placements/placement_geometry.dart';
export 'src/placements/placement_history.dart';
export 'src/placements/placement_management.dart';
export 'src/placements/placement_screen_sample.dart';
export 'src/render_bundle/bounded_png.dart';
export 'src/render_bundle/render_bundle_engine_set.dart';
export 'src/render_bundle/render_bundle_head.dart';
export 'src/restage_bundle/restage_bundle.dart';
export 'src/rfw_preview_reservation.dart';
export 'src/surface_contract/sample_host_context.dart';
export 'src/surface_contract/surface_publication_contract.dart';
export 'src/surface_contract/surface_screen_contract_fingerprint.dart';
export 'src/surface_contract/surface_screen_event_schema.dart';
export 'src/surface_contract/surface_screen_host_data_schema.dart';
export 'src/surface_delivery/surface_artifact_descriptor.dart';
export 'src/surface_delivery/surface_registration.dart';
export 'src/surface_document/surface_document.dart';
export 'src/surface_document/surface_document_codec.dart';
export 'src/surface_document/surface_payload_publish_validation.dart';
export 'src/surface_feature_client_floor.dart';
export 'src/taps/surface_tap_names.dart';
export 'src/theme/theme_data_contract.dart';
