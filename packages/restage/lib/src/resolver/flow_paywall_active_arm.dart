import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        FlowActiveRenderGate,
        FlowContentHash,
        FlowDocument,
        FlowDocumentCodec,
        FlowDocumentValidation,
        FlowSurfacePayload,
        LibraryRequirement;

import '../flow/flow_resolver.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import 'resolved_paywall_payload.dart';

/// The outcome of evaluating a hosted active flow-paywall document against the
/// client's bundled contract. Sealed: exactly one of accepted or rejected.
@internal
sealed class FlowPaywallActiveResolution {
  const FlowPaywallActiveResolution();
}

/// The active document is safe to render; carries the renderable payload.
@internal
final class FlowPaywallActiveAccepted extends FlowPaywallActiveResolution {
  const FlowPaywallActiveAccepted(this.payload);

  final FlowPaywallPayload payload;
}

/// The active document is unsafe; the caller fails closed to the bundled flow.
@internal
final class FlowPaywallActiveRejected extends FlowPaywallActiveResolution {
  const FlowPaywallActiveRejected(this.reason);

  /// A short, stable reason marker for diagnostics (mirrors the ServerFlow
  /// resolver reason vocabulary + the render-gate reason).
  final String reason;
}

/// Evaluates a server-resolved (active) flow-paywall document against the
/// client's [bundled] contract and, if safe, returns a renderable
/// [FlowPaywallPayload] carrying the served version + experiment arm.
///
/// Fail-closed: a retained-check failure or a render-gate rejection returns a
/// [FlowPaywallActiveRejected] so the caller falls back to the bundled flow — an
/// unsafe active document is NEVER rendered. (Content that rewires a charge
/// control is not gated here — parity with the blob-OTA path: entitlement is
/// granted only on a real purchase success, so a rewired control simply doesn't
/// charge, exactly like a customer content bug in a bundled paywall.)
///
/// The paywall path synthesizes its flow ref FROM the active document, so the
/// flow controller provides no independent backstop — this arm is the SOLE line
/// of defense. Its retained checks are exact-parity with `ServerFlowResolver`'s
/// (pinned by the retained-check census group in `flow_paywall_active_arm_test.dart`);
/// if that check set changes, re-census here.
@internal
FlowPaywallActiveResolution resolveFlowActiveArm({
  required FlowSurfacePayload activePayload,
  required FlowDocument bundledDocument,
  required String paywallId,
  required int activeVersion,
  String? experimentId,
  String? variantId,
  bool cacheHit = false,
}) {
  final active = activePayload.flowDocument;

  // Retained backstop checks on the active document (version-relaxed). These
  // mirror ServerFlowResolver._passesRetainedChecks; the client ref is the
  // bundled contract document (there is no OnboardingFlowRef on this path). They
  // run BEFORE and independently of the render gate — a gate-self-relative-
  // acceptable but runtime-invalid active document is still rejected.
  final retained = _retainedCheckReject(
    active: active,
    bundled: bundledDocument,
    requiredLibraries: activePayload.requiredLibraries,
    paywallId: paywallId,
  );
  if (retained != null) return FlowPaywallActiveRejected(retained);

  // The compatibility gate: the active client-observable contract must be a
  // subset of the client's. Reused verbatim (surface-generic, security-critical).
  final verdict = FlowActiveRenderGate.evaluate(
    client: bundledDocument,
    active: active,
  );
  if (!verdict.accepted) return const FlowPaywallActiveRejected('render_gate');

  final resolvedFlow = ResolvedFlow(
    document: active,
    screenBlobs: activePayload.screenBlobs,
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(active),
    ),
    cacheHit: cacheHit,
  );
  return FlowPaywallActiveAccepted(
    FlowPaywallPayload(
      flow: resolvedFlow,
      paywallId: paywallId,
      paywallPublishedVersion: activeVersion,
      experimentId: experimentId,
      variantId: variantId,
      resolvedFromActiveArm: true,
    ),
  );
}

/// Runs the retained backstop checks; returns a reject reason marker or null.
/// Mirrors ServerFlowResolver._checkCompatibility(checkVersion:false) +
/// _checkRequiredLibraries + _checkValidation. Envelope identity (surface type +
/// slug, version-relaxed) is checked by the resolver before this arm is entered.
String? _retainedCheckReject({
  required FlowDocument active,
  required FlowDocument bundled,
  required List<LibraryRequirement> requiredLibraries,
  required String paywallId,
}) {
  final installed = RestageBuiltInCatalogCapabilities.currentVersion;

  // Flow-document identity (version-relaxed).
  if (active.flow != paywallId) return 'flow_mismatch';

  // Schema version.
  if (active.schemaVersion != 1) return 'unsupported_schema_version';

  // Document capability floor: at or below both the client ref (bundled) AND the
  // installed built-in catalog version.
  if (active.minClient > bundled.minClient || active.minClient > installed) {
    return 'unsupported_min_client';
  }

  // Per-artifact schema + capability floors.
  for (final entry in active.screenArtifacts.entries) {
    final artifact = entry.value;
    if (artifact.schemaVersion != 1) return 'unsupported_schema_version';
    if (artifact.minClient > bundled.minClient ||
        artifact.minClient > installed) {
      return 'unsupported_min_client';
    }
  }

  // Required custom libraries (the envelope manifest) against the registry.
  for (final requirement in requiredLibraries) {
    if (!LibraryRuntimeRegistry.satisfies(requirement)) {
      return 'unsupported_required_library';
    }
  }

  // Document validation (the shared structural contract).
  if (FlowDocumentValidation.validate(active).isNotEmpty) {
    return 'validation_failed';
  }

  return null;
}
