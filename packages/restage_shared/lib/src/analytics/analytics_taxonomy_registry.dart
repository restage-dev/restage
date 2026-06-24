import 'package:meta/meta.dart';
import 'package:restage_shared/src/analytics/analytics_wire_enums.dart';

/// The registry entry for a canonical event name.
@immutable
final class AnalyticsEventSpec {
  /// Creates a spec. [requiredProperties] is copied into an unmodifiable set so
  /// the value type cannot be mutated through the constructor argument.
  AnalyticsEventSpec({
    required this.tier,
    Set<String> requiredProperties = const <String>{},
  }) : requiredProperties = Set<String>.unmodifiable(requiredProperties);

  /// Sampling tier (see [AnalyticsTier]). Server-derived from this registry.
  final String tier;

  /// Property keys an emitter is expected to provide for this event.
  final Set<String> requiredProperties;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsEventSpec &&
      other.tier == tier &&
      _setEquals(other.requiredProperties, requiredProperties);

  @override
  int get hashCode =>
      Object.hash(tier, Object.hashAllUnordered(requiredProperties));
}

final AnalyticsEventSpec _tier1 = AnalyticsEventSpec(tier: AnalyticsTier.tier1);

/// The single-sourced event taxonomy: canonical name → `{tier,
/// requiredProperties}`. Read by the SDK (warn on unknown), the ingest
/// validator (derive `tier`), and the schema docs — the validator==SDK
/// triangle.
///
/// Forward-compat: unknown names are **soft-allowed** as Tier 1 (see
/// [lookupAnalyticsEvent]); they are never rejected here (the abuse budget,
/// not this registry, bounds unknown-name cardinality).
///
/// The exposed map is unmodifiable — callers read the taxonomy, they do not
/// mutate it.
final Map<String, AnalyticsEventSpec> kAnalyticsRegistry =
    Map<String, AnalyticsEventSpec>.unmodifiable(<String, AnalyticsEventSpec>{
  // --- Tier 1: paywall lifecycle / conversion / errors (existing SDK names) ---
  'paywall_load_started': _tier1,
  'paywall_load_completed': _tier1,
  'paywall_load_failed': _tier1,
  // The funnel terminator (a load that never completed nor failed).
  'paywall_load_aborted': _tier1,
  'paywall_viewed': _tier1,
  'paywall_dismissed': _tier1,
  'paywall_custom_event': _tier1,
  'purchase_initiated': _tier1,
  'purchase_succeeded': _tier1,
  'purchase_pending': _tier1,
  'purchase_cancelled': _tier1,
  'purchase_failed': _tier1,
  'restore_initiated': _tier1,
  'restore_succeeded': _tier1,
  'restore_no_purchases': _tier1,
  'restore_failed': _tier1,
  // Registered now, fires at a later milestone.
  'paywall_survey_responded': _tier1,

  // --- Tier 1: entitlement / subscription lifecycle (server + client) ---
  'entitlement_granted': _tier1,
  'entitlement_revoked': _tier1,
  'subscription_renewed': _tier1,
  'subscription_lapsed': _tier1,

  // --- Tier 1: engagement-flow lifecycle (surface-agnostic) ---
  'flow_started': _tier1,
  'flow_completed': _tier1,
  'flow_unavailable': _tier1,
  'flow_custom_event': _tier1,

  // --- Tier 1: onboarding surface events ---
  'onboarding_step_viewed': AnalyticsEventSpec(
    tier: AnalyticsTier.tier1,
    requiredProperties: const <String>{'screenId', 'stepIndex'},
  ),
  'onboarding_skipped': AnalyticsEventSpec(
    tier: AnalyticsTier.tier1,
    requiredProperties: const <String>{'atScreenId', 'stepIndex'},
  ),
  'onboarding_permission_response': AnalyticsEventSpec(
    tier: AnalyticsTier.tier1,
    requiredProperties: const <String>{'permission', 'granted'},
  ),

  // --- Tier 2: the sole coalesced per-session summary ---
  'paywall_session_summary': AnalyticsEventSpec(tier: AnalyticsTier.tier2),
});

/// Resolves [name] to its spec, **soft-allowing** an unknown name as a Tier-1
/// event with no required properties (never null, never a throw).
AnalyticsEventSpec lookupAnalyticsEvent(String name) =>
    kAnalyticsRegistry[name] ?? _tier1;

/// Whether [name] is an explicitly-registered event (false for a soft-allowed
/// unknown).
bool isRegisteredAnalyticsEvent(String name) =>
    kAnalyticsRegistry.containsKey(name);

/// The (server-derived) tier for [name].
String tierForEvent(String name) => lookupAnalyticsEvent(name).tier;

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
