import 'dart:async';

import 'package:flutter/widgets.dart';

import 'manifest.dart';
import 'protocol.dart';

final _browserGrantPattern = RegExp(r'^[0-9a-f]{64}$');

/// Reveal-once values needed to create one hosted render-bundle frame.
///
/// The grant is intentionally not serializable and is redacted from
/// [toString]. Adapters may use it only as the body of the bootstrap form.
final class HostedRenderBundleBootstrap {
  /// Creates one validated, credential-free URL plus reveal-once grant.
  HostedRenderBundleBootstrap({
    required this.renderBundleId,
    required this.bootstrapUrl,
    required this.bootstrapGrant,
    required this.expiresAt,
  }) : bundleOrigin = _validateBootstrapUrl(bootstrapUrl, renderBundleId) {
    if (!_browserGrantPattern.hasMatch(bootstrapGrant)) {
      throw ArgumentError.value(
        '<redacted>',
        'bootstrapGrant',
        'must be a lowercase 64-character browser grant',
      );
    }
  }

  /// Immutable backend row identifier.
  final int renderBundleId;

  /// Exact credential-free URL that receives the grant by POST.
  final Uri bootstrapUrl;

  /// Reveal-once form value. Never place this in seam protocol data.
  final String bootstrapGrant;

  /// Server-issued grant expiry.
  final DateTime expiresAt;

  /// Exact HTTP(S) origin derived from [bootstrapUrl].
  final Uri bundleOrigin;

  @override
  String toString() =>
      'HostedRenderBundleBootstrap(renderBundleId: $renderBundleId, '
      'bootstrapUrl: $bootstrapUrl, bootstrapGrant: <redacted>, '
      'expiresAt: $expiresAt)';
}

/// Platform-owned hosted frame and exact-origin message transport.
///
/// Browser iframe and native WebView adapters implement this boundary. Frame
/// load and protocol readiness are separate; neither implies the other.
abstract interface class HostedRenderBundleFrame {
  /// Noninteractive, initially concealed renderer view.
  Widget get view;

  /// Exact-origin transport connected only to the hosted child frame.
  RenderMessageTransport get transport;

  /// Completes once the reveal-once form has been submitted.
  Future<void> get bootstrapSubmitted;

  /// Completes after the post-bootstrap child load event.
  Future<void> get loaded;

  /// Conceals child pixels without detaching the frame.
  void concealPixels();

  /// Reveals pixels after the owning render epoch settles.
  void revealPixels();

  /// Sets the backing raster scale while preserving visual bounds.
  void setRasterScale(double scale);

  /// Synchronously removes pixels when concealment cannot be trusted.
  void emergencyRemovePixels();

  /// Clears the child, transport, and any retained bootstrap material.
  Future<void> dispose();
}

/// One hosted frame paired with the shell-side frozen-v1 provider.
final class HostedRenderBundleSession {
  /// Composes a platform frame with one exact-origin seam provider.
  HostedRenderBundleSession({
    required HostedRenderBundleFrame frame,
    required Uri bundleOrigin,
    required RenderFrameScheduler scheduleFrame,
  })  : _frame = frame,
        _provider = SeamRenderProvider(
          transport: frame.transport,
          bundleOrigin: _validateOrigin(bundleOrigin),
          supportedVersions: const <int>[renderProtocolV1],
          scheduleFrame: scheduleFrame,
        ) {
    _ready = _provider.ready.then<void>((_) {});
    _ready.ignore();
  }

  final HostedRenderBundleFrame _frame;
  final SeamRenderProvider _provider;
  late final Future<void> _ready;
  Future<void>? _disposeFuture;

  /// Noninteractive platform view.
  Widget get view => _frame.view;

  /// Frozen-v1 render and snapshot provider.
  SeamRenderProvider get provider => _provider;

  /// Ready manifest after [ready] completes.
  RenderBundleManifest? get manifest => _provider.manifest;

  /// Ready engine after [ready] completes.
  RenderEngine? get engine => _provider.engine;

  /// Reveal-once form submission boundary.
  Future<void> get bootstrapSubmitted => _frame.bootstrapSubmitted;

  /// Platform child-load boundary.
  Future<void> get loaded => _frame.loaded;

  /// Frozen-v1 ready-handshake boundary.
  Future<void> get ready => _ready;

  /// Delegates fail-closed concealment.
  void concealPixels() => _frame.concealPixels();

  /// Delegates post-settle reveal.
  void revealPixels() => _frame.revealPixels();

  /// Delegates backing raster scaling.
  void setRasterScale(double scale) => _frame.setRasterScale(scale);

  /// Delegates synchronous emergency removal.
  void emergencyRemovePixels() => _frame.emergencyRemovePixels();

  /// Disposes the provider and frame exactly once.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    await _provider.dispose();
    if (!identical(_frame.transport, _frame)) await _frame.dispose();
  }
}

Uri _validateBootstrapUrl(Uri value, int renderBundleId) {
  if (renderBundleId < 1 ||
      !_isTrustedHostedUrl(value) ||
      value.hasQuery ||
      value.hasFragment ||
      value.path != '/render-bundles/v1/b/$renderBundleId/bootstrap') {
    throw ArgumentError.value(
      value,
      'bootstrapUrl',
      'must be the exact credential-free bootstrap URL for the bundle',
    );
  }
  return Uri.parse(value.origin);
}

String _validateOrigin(Uri value) {
  if (!_isTrustedHostedUrl(value) ||
      (value.path.isNotEmpty && value.path != '/') ||
      value.hasQuery ||
      value.hasFragment) {
    throw ArgumentError.value(
      value,
      'bundleOrigin',
      'must be a canonical HTTP(S) origin',
    );
  }
  return value.origin;
}

bool _isTrustedHostedUrl(Uri value) {
  if (!value.isAbsolute || value.host.isEmpty || value.userInfo.isNotEmpty) {
    return false;
  }
  if (value.scheme == 'https') return !value.hasPort;
  return value.scheme == 'http' &&
      (value.host == 'localhost' || value.host == '127.0.0.1');
}
