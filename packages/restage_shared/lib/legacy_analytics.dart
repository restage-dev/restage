/// The legacy behavioral-analytics event taxonomy: the wire envelope, its app
/// context, the reserved-key and clock-skew helpers, the event registry, and
/// the wire enums.
///
/// Deliberately kept out of the default `restage_shared.dart` barrel. This
/// vocabulary is retained only for the legacy analytics runtime the SDK still
/// ships; the replacement measurement contracts live in
/// `package:restage_measurement_schema/restage_measurement_schema.dart` and are
/// what new code should reach for. This entrypoint is removed together with
/// that runtime.
///
/// Importing it opts in to a surface that is going away, so import it directly
/// and only where the legacy runtime is being served.
library;

export 'src/legacy_analytics/analytics_app_context.dart';
export 'src/legacy_analytics/analytics_event.dart';
export 'src/legacy_analytics/analytics_reserved_keys.dart';
export 'src/legacy_analytics/analytics_skew.dart';
export 'src/legacy_analytics/analytics_taxonomy_registry.dart';
export 'src/legacy_analytics/analytics_wire_enums.dart';
