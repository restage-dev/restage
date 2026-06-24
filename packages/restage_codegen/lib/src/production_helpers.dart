import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';

/// The helper registry the production paywall build step registers — the single
/// source of truth for "what the build recognises" on the paywall feature-kind.
///
/// Called by both the build (`codegen_builder.dart`) and the coverage scanner's
/// default (`real_package_scanner.dart`), so the meter mirrors the build by
/// construction: a helper added here reaches both at once, and the scanner can
/// never silently measure against a stale helper set.
///
/// src-internal: NOT exported from the package barrel. This is the home a
/// future feature-kind registry (e.g. an onboarding helper set) would join, so
/// the build and any matching meter stay a single source of truth.
HelperRegistry productionPaywallHelperRegistry() =>
    HelperRegistry()..registerAll(paywallHelpers);
