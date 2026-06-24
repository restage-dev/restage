import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:restage_shared/restage_shared.dart' show CapabilityManifest;

import 'a2ui_payload_scan.dart';
import 'installed_capability.dart';
import 'restage_a2ui_sidecar.dart';

/// The outcome of a pre-render check.
@immutable
sealed class A2uiPreRenderResult {
  const A2uiPreRenderResult();
}

/// The payload is safe to hand to the genui render seam.
@immutable
final class A2uiRenderable extends A2uiPreRenderResult {
  /// Creates a renderable result.
  const A2uiRenderable();
}

/// The payload must not be rendered. [diagnostic] is a clean, actionable
/// message; [gap] is the structured capability gap when the rejection is a
/// version/library shortfall (null for an existence or malformed-input
/// rejection).
@immutable
final class A2uiRejected extends A2uiPreRenderResult {
  /// Creates a rejection with a [diagnostic] and an optional capability [gap].
  const A2uiRejected(this.diagnostic, {this.gap});

  /// A clean, actionable description of why the payload was rejected.
  final String diagnostic;

  /// The capability shortfall, when the rejection is a version/library gap.
  final String? gap;

  @override
  String toString() =>
      'A2uiRejected($diagnostic${gap == null ? '' : ' [$gap]'})';
}

/// The app-side pre-render capability check: verifies a cached A2UI payload
/// against the catalog the app registered, BEFORE handing it to genui's render
/// seam — so a payload this build cannot render faithfully fails with a clean
/// diagnostic instead of genui's mid-render hard-fail.
///
/// Two parts:
///  * **(a) existence** — every component type the payload references must
///    exist in [catalog]'s items. Universal: runs for any payload, including a
///    raw model-generated one, and pre-empts genui's `CatalogItemNotFoundException`.
///  * **(b) version** — when the payload is a Restage sidecar, its required
///    [CapabilityManifest] must be satisfied by [installed] (the registered
///    catalog's capability), mirroring the native delivery path's two-axis
///    relation. **Fail-closed:** a stamped payload with no [installed]
///    descriptor cannot be verified and is rejected — never skipped.
///
/// Every path fails closed: any decode/shape error yields an [A2uiRejected],
/// never a throw at the render seam.
@immutable
final class RestageA2uiPreRenderCheck {
  /// Creates a check over the registered [catalog]. [installed] is the
  /// registered catalog's capability descriptor (normally
  /// [A2uiInstalledCapability.fromStampJson] of its `restageCapability` block);
  /// supply it to verify Restage-stamped payloads. Without it, only part (a)
  /// can run and stamped payloads are rejected as unverifiable.
  const RestageA2uiPreRenderCheck({required this.catalog, this.installed});

  /// The genui catalog the app registered — the render-truth for part (a).
  final Catalog catalog;

  /// What the registered catalog provides — the available side for part (b).
  final A2uiInstalledCapability? installed;

  /// Checks [cached] (a raw A2UI payload, or a Restage sidecar wrapping one).
  A2uiPreRenderResult check(Object? cached) {
    final Object? payload;
    final CapabilityManifest? required;
    if (RestageA2uiSidecar.isRestageSidecar(cached)) {
      final RestageA2uiSidecar sidecar;
      try {
        // isRestageSidecar confirmed `cached is Map`; coerce its key/value
        // types defensively — a host may hand-build the envelope as
        // Map<Object?, Object?> — then decode.
        sidecar = RestageA2uiSidecar.fromJson(
          Map<String, Object?>.from(cached! as Map),
        );
      } on FormatException catch (error) {
        return A2uiRejected('malformed Restage A2UI sidecar: ${error.message}');
      } on Object catch (error) {
        // Fail closed at the render seam: any other decode error — a non-string
        // key, or a wire decoder's blind cast rejecting a loosely-typed shape —
        // is treated as malformed input, never a throw the host must handle.
        return A2uiRejected('malformed Restage A2UI sidecar: $error');
      }
      payload = sidecar.a2ui;
      required = sidecar.capability;
    } else {
      payload = cached;
      required = null;
    }

    // Part (a): existence — universal, the render-truth is the registered items.
    final referenced = a2uiReferencedWidgetTypes(payload);
    final known = {for (final item in catalog.items) item.name};
    final missing = referenced.difference(known);
    if (missing.isNotEmpty) {
      final sorted = missing.toList()..sort();
      return A2uiRejected(
        'A2UI payload references component(s) not in the installed catalog: '
        '${sorted.join(', ')}',
      );
    }

    // Part (b): version — only for a Restage-stamped payload.
    if (required != null) {
      return _checkCapability(required);
    }
    return const A2uiRenderable();
  }

  A2uiPreRenderResult _checkCapability(CapabilityManifest required) {
    final available = installed;
    if (available == null) {
      // FAIL-CLOSED: a stamped payload asserts a versioned requirement; with no
      // installed descriptor it cannot be verified, so it must not render.
      return const A2uiRejected(
        'A2UI payload carries a Restage capability requirement that cannot be '
        'verified: no installed catalog capability descriptor was supplied',
      );
    }
    if (required.builtInFloor > available.catalogContentVersion) {
      return A2uiRejected(
        'A2UI payload requires a newer built-in catalog than this build '
        'provides',
        gap:
            'requires built-in catalog version ${required.builtInFloor}, '
            'installed ${available.catalogContentVersion}',
      );
    }
    for (final requirement in required.requiredLibraries) {
      final match = _availableLibrary(available, requirement.namespace);
      if (match == null || match.version < requirement.minVersion) {
        final have = match == null ? 'absent' : 'installed v${match.version}';
        return A2uiRejected(
          'A2UI payload requires a custom library this build does not provide '
          'at the needed version',
          gap:
              'requires library "${requirement.namespace}" '
              '>= v${requirement.minVersion} ($have)',
        );
      }
    }
    return const A2uiRenderable();
  }

  /// The installed library with [namespace], or null if none is provided.
  A2uiAvailableLibrary? _availableLibrary(
    A2uiInstalledCapability available,
    String namespace,
  ) {
    for (final library in available.availableLibraries) {
      if (library.namespace == namespace) {
        return library;
      }
    }
    return null;
  }
}
