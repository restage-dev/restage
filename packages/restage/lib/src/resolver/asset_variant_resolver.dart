import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:meta/meta.dart';

import '../flow/bundled_flow_loader.dart';
import '../flow/flow_resolver.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/paywall_error.dart';
import 'resolved_paywall_payload.dart';
import 'resolved_variant.dart';
import 'variant_resolver.dart';

/// Resolves variants by loading `assets/paywalls/<id>.rfw` from `rootBundle`.
///
/// This is the bundled paywall delivery path. Use it as a per-paywall resolver
/// or configure it as the default resolver when paywalls are bundled at compile
/// time. Restage-hosted (over-the-air) delivery is provided by
/// `RestageVariantResolver`, which also falls back to a bundled asset like this
/// one when the hosted fetch is unavailable.
///
/// ```dart
/// // Loads `assets/paywalls/pro_upgrade.rfw` from rootBundle.
/// RestagePaywall(
///   id: 'pro_upgrade',
///   resolver: const AssetVariantResolver(),
/// )
/// ```
final class AssetVariantResolver
    implements VariantResolver, FlowCapableVariantResolver {
  /// Creates an [AssetVariantResolver]. Override [assetPathPrefix] when
  /// paywalls are bundled under a non-default folder.
  const AssetVariantResolver({
    this.assetPathPrefix = 'assets/paywalls',
    AssetBundle? bundle,
  }) : _bundle = bundle;

  /// Path prefix joined to `<id>.rfw` to form the asset key.
  final String assetPathPrefix;

  final AssetBundle? _bundle;

  AssetBundle get _effectiveBundle => _bundle ?? rootBundle;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    return _loadBlob(id);
  }

  // Internal flow-capable seam (the [FlowCapableVariantResolver] override) — not
  // part of the public resolver API. The public SPI stays [resolve] (blob-only);
  // this carries the blob-or-flow payload for the built-in resolvers and may
  // change without a public-API break.
  @internal
  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    try {
      final artifacts = await loadBundledFlowArtifacts(
        bundle: _effectiveBundle,
        flowJsonPath: '$assetPathPrefix/$id.flow.json',
        screenAssetPathPrefix: 'assets/onboarding/screens',
        flowId: id,
        supportedMinClient: RestageBuiltInCatalogCapabilities.currentVersion,
        clientDescription: 'supported client',
        buildError: (reason, message, [cause]) {
          if (reason == 'missing_flow_json') {
            return _MissingBundledPaywallFlow();
          }
          return RestagePaywallError(
            code: RestageErrorCodes.deliveryUnavailable,
            message: 'Bundled flow paywall "$id" is unavailable '
                '($reason): $message',
            cause: cause,
          );
        },
      );
      return FlowPaywallPayload(
        flow: ResolvedFlow(
          document: artifacts.document,
          screenBlobs: artifacts.screenBlobs,
          contentHash: artifacts.documentHash,
          cacheHit: false,
        ),
        paywallId: id,
      );
    } on _MissingBundledPaywallFlow {
      final variant = await _loadBlob(id);
      return BlobPaywallPayload(variant);
    }
  }

  Future<ResolvedVariant> _loadBlob(String id) async {
    final path = '$assetPathPrefix/$id.rfw';
    try {
      final data = await _effectiveBundle.load(path);
      return ResolvedVariant(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        paywallId: id,
      );
    } on FlutterError catch (e) {
      throw RestagePaywallError(
        code: RestageErrorCodes.assetNotFound,
        message: 'No asset at "$path". Add it to pubspec.yaml flutter:assets '
            'or pass an explicit resolver: parameter to RestagePaywall.',
        cause: e,
      );
    }
  }
}

final class _MissingBundledPaywallFlow implements Exception {}
