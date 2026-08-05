import 'dart:async';
import 'dart:collection';

import '../analytics/root_analytics_context.dart';

final _scopeKey = Object();

/// Immutable attribution captured from the content that rendered the buy CTA.
///
/// This file is deliberately not exported. The zone scope lets the
/// paywall pass render-time attribution through the existing public purchase
/// API without adding attribution parameters to that API.
final class PurchaseAttributionSnapshot {
  const PurchaseAttributionSnapshot({
    required this.paywallId,
    required this.paywallPublishedVersion,
    required this.experimentId,
    required this.experimentVariantId,
    required this.experimentEpoch,
    required this.offerId,
    this.rootAnalyticsContext,
  });

  final String paywallId;
  final int? paywallPublishedVersion;
  final String? experimentId;
  final String? experimentVariantId;
  final int? experimentEpoch;
  final String? offerId;
  final RootAnalyticsDeferredContext? rootAnalyticsContext;
}

/// Zone-local bridge around the source-compatible public call.
abstract final class PurchaseAttributionScope {
  static PurchaseAttributionSnapshot? get current =>
      Zone.current[_scopeKey] as PurchaseAttributionSnapshot?;

  static T run<T>(PurchaseAttributionSnapshot snapshot, T Function() action) =>
      runZoned(action, zoneValues: {_scopeKey: snapshot});
}

/// Identity registry for gateways whose completion lifecycle is coordinator
/// owned. It lets the paywall preserve custom gateway behavior without
/// exposing an ownership flag on the public billing SPI.
abstract final class BundledPurchaseOwnership {
  static final Set<Object> _installed = HashSet<Object>.identity();

  static bool isInstalled(Object gateway) => _installed.contains(gateway);

  static void install(Object gateway) => _installed.add(gateway);

  static void uninstall(Object gateway) => _installed.remove(gateway);

  static void debugReset() => _installed.clear();
}
