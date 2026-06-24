import 'dart:ui' show Locale;

import 'resolved_variant.dart';

/// Resolves a paywall id into a [ResolvedVariant] (the `.rfw` blob + metadata).
///
/// Implementations:
/// - [AssetVariantResolver] — loads bundled `assets/paywalls/<id>.rfw`.
/// - `RestageVariantResolver` — fetches Restage-hosted paywalls from the
///   configured `baseUrl`, with a fail-closed fallback to a bundled asset.
///
/// Host apps can implement this to plug in a custom delivery layer (e.g.
/// fetching `.rfw` blobs from their own CDN):
///
/// ```dart
/// class MyResolver implements VariantResolver {
///   @override
///   Future<ResolvedVariant> resolve(
///     String id, {
///     String? placementId,
///     Locale? locale,
///   }) async {
///     final bytes = await myHttpClient.fetchPaywall(id);
///     return ResolvedVariant(bytes: bytes, paywallId: id);
///   }
/// }
/// ```
abstract class VariantResolver {
  /// Resolves [id] (and optional [placementId] / [locale]) into a
  /// [ResolvedVariant]. Throws [RestagePaywallError] on failure.
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  });
}
