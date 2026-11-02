import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/foundation.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryCompatibility;

import 'a2ui_payload_scan.dart';
import 'installed_capability.dart';
import 'restage_a2ui_sidecar.dart';

/// The outcome of a pre-render check.
@immutable
sealed class A2uiPreRenderResult {
  const A2uiPreRenderResult();
}

/// The payload is safe to hand to the A2UI render seam.
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

/// Checks a complete cached v1 message bundle against the registered catalogs.
///
/// Upstream parsing and validation resolve each component against its explicit
/// catalog or its surface default. Validation tracks surface creation, updates,
/// and deletion, and checks schemas without invoking functions or building UI.
/// Each message is validated with the renderer's [validationConfig], as the
/// renderer's processor would, and the finished bundle must also leave every
/// surface with a root and no dangling reference.
///
/// Restage sidecars additionally require [installed], the capability descriptor
/// for the registered Restage capability set. Catalog IDs are routing identities,
/// never authority for the two-axis library/version comparison.
@immutable
final class RestageA2uiPreRenderCheck {
  /// Creates a check over [catalogs]. Supply [installed] to verify stamped
  /// Restage payloads; without it those payloads are rejected as unverifiable.
  const RestageA2uiPreRenderCheck({
    required this.catalogs,
    this.installed,
    this.validationConfig,
  });

  /// The upstream catalogs registered by the host renderer.
  final Iterable<Catalog> catalogs;

  /// The capability set supplied by the registered Restage catalogs.
  final A2uiInstalledCapability? installed;

  /// The `ValidationConfig` the renderer's `MessageProcessor` uses; null means
  /// the processor was given none.
  final ValidationConfig? validationConfig;

  String get _rootId => validationConfig?.rootId ?? 'root';

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

    // Use upstream's non-executing processor: it owns catalog resolution,
    // schema checks and surface lifecycle, including inline create components.
    MessageProcessor<ComponentApi>? processor;
    try {
      final messages = parseA2uiV1Messages(payload);
      processor = MessageProcessor<ComponentApi>.forAgent(
        catalogs: catalogs.toList(),
        defaultVersion: A2uiProtocolVersion.v1_0,
        validationConfig: _perMessageConfig(),
      );
      processor.processMessages(messages);
      _checkFinalGraph(processor);
    } on Object catch (error) {
      return A2uiRejected('invalid A2UI v1 payload: $error');
    } finally {
      processor?.dispose();
    }

    // Part (b): version — only for a Restage-stamped payload.
    if (required != null) {
      return _checkCapability(required);
    }
    return const A2uiRenderable();
  }

  // The renderer's graph rules, or none without a config; unknown elements
  // are always rejected and nothing outside v1 is accepted.
  ValidationConfig _perMessageConfig() {
    final host = validationConfig;
    return ValidationConfig(
      targetVersion: A2uiProtocolVersion.v1_0,
      rootId: _rootId,
      allowOrphanComponents: host?.allowOrphanComponents ?? true,
      allowDanglingReferences: host?.allowDanglingReferences ?? true,
      allowMissingRoot: host?.allowMissingRoot ?? true,
      allowedMessages: host?.allowedMessages,
      maxDepth: host?.maxDepth,
    );
  }

  // A bundle the renderer could only show as a placeholder is not renderable.
  void _checkFinalGraph(MessageProcessor<ComponentApi> processor) {
    final finalGraph = ValidationConfig(
      targetVersion: A2uiProtocolVersion.v1_0,
      rootId: _rootId,
      allowOrphanComponents: true,
      maxDepth: validationConfig?.maxDepth,
    );
    final surfaces = processor.model.allSurfaces.toList();
    if (surfaces.isEmpty) {
      throw A2uiValidationError('the bundle leaves no surface to render');
    }
    for (final surface in surfaces) {
      if (surface.componentsModel.keys.isEmpty) {
        throw A2uiValidationError("surface '${surface.id}' has no components");
      }
      surface.componentsModel.validateTopology(finalGraph);
    }
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
      final match = _availableLibrary(
        available,
        requirement.namespace,
      )?.asInstalledLibrary;
      final compatibility = LibraryCompatibility.evaluate(match, requirement);
      if (compatibility == LibraryCompatibility.satisfied) continue;
      final have = match == null
          ? 'absent'
          : LibraryCompatibility.describeInstalled(match);
      return A2uiRejected(
        compatibility == LibraryCompatibility.contractBroken
            ? 'A2UI payload requires a custom library version this build no '
                  'longer renders'
            : 'A2UI payload requires a custom library this build does not '
                  'provide at the needed version',
        gap:
            'requires library "${requirement.namespace}" '
            '>= v${requirement.minVersion} ($have)',
      );
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
