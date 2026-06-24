import 'package:rfw_catalog_compiler/src/wire_ids/events.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Returns the catalog-lifecycle deprecation for [id] by scanning [events]
/// for [DeprecateWireIdEvent]s that target [id], or `null` when none exist.
///
/// [events] is typically the full wire-ID event log, but may be any
/// synthesized slice covering the entry of interest.
///
/// When multiple `deprecate` events target the same [id], replay semantics
/// apply: the **last** event wins.
///
/// This function uses a direct scan rather than the full replay machinery in
/// `current_state.dart` because [events] may represent any sub-list of an
/// event log, not necessarily a complete, ordered library log. The full
/// replayer enforces library-level invariants (unique allocs, sequence
/// ordering, owner resolution) that are correct for materializing current
/// state but inappropriate here, where callers may pass a minimal synthesized
/// slice for a single entry.
CatalogDeprecationInfo? catalogDeprecationFor(
  WireId id,
  List<WireIdEvent> events,
) {
  CatalogDeprecationInfo? result;
  for (final event in events) {
    if (event is DeprecateWireIdEvent && event.id == id) {
      result = CatalogDeprecationInfo(
        reason: event.reason,
        at: event.at,
      );
    }
  }
  return result;
}
