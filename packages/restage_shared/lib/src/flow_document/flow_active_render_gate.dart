import 'package:meta/meta.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_compatibility.dart';

const String _screenArtifactChangedCode = 'screenArtifactChanged';

/// Decides whether a server-resolved (active) [FlowDocument] is safe to render
/// under a client's bundled [FlowDocument].
///
/// The render gate is the linchpin of content-OTA flow delivery: it lets a
/// server ship new screen content for an existing flow (copy, layout, the RFW
/// bytes of a screen) to already-installed clients, while refusing any change
/// that would alter the **client-observable contract** the installed client was
/// built and submitted under — declared host actions, reachable terminal-result
/// shapes, outbound data fields, the flow graph, or the capability floor.
///
/// The gate is a strict re-interpretation of the existing
/// [FlowDocumentCompatibility.diff] change-set (NOT
/// [FlowDocumentCompatibility.classify], which marks contract-expanding changes
/// as `additive`). It is **fail-closed**: the only accepted change is a
/// content-only screen-artifact change at an unchanged capability floor; every
/// other change — and any invalid input — rejects. A false reject costs an OTA
/// opportunity (the client keeps running its bundled document — safe); a false
/// accept would render a broken or over-permissioned surface to a real user.
/// When in doubt, reject.
///
/// This predicate is pure and total: it performs no IO and **never throws to
/// the caller** — an invalid document rejects with
/// [FlowActiveRenderRejectionReason.documentInvalid].
///
/// **Contract domain — this is a COMPATIBILITY gate over a runtime-valid
/// baseline, not a VALIDITY gate.** It decides only whether the active
/// document's client-observable contract is a subset of the client's (the
/// *compatibility* question), evaluated against a client baseline that is
/// itself runtime-valid. Document *validity* — schema-version support,
/// action/result-predicate consistency, and the rest of the runtime
/// invariants — is owned by `FlowDocumentValidation` (the shared structural
/// contract) and the runtime controller, which run independently on the active
/// document. The gate deliberately does not re-check those: for a runtime-valid
/// client, an accepted active document inherits the client's validity by
/// construction (any change to a validity-bearing dimension is itself a
/// non-content change code, which rejects). The only documents this gate
/// accepts that the runtime would reject are ones whose *client* baseline is
/// already runtime-invalid — a client that cannot render its own bundled
/// document — which is unreachable in production and rejected by the runtime's
/// validity checks regardless. Those checks are a **binding downstream
/// dependency**: the consumer must keep the runtime's schema/floor/action
/// validity gates running on the active document, replacing only the
/// exact-version pin with this predicate.
abstract final class FlowActiveRenderGate {
  /// Evaluates whether [active] renders safely under [client].
  ///
  /// [client] is the client's bundled/generated contract; [active] is the
  /// server-resolved document. The two are compared as
  /// `diff(from: client, to: active)`: the direction matters.
  static FlowActiveRenderVerdict evaluate({
    required FlowDocument client,
    required FlowDocument active,
  }) {
    // Total + fail-closed: any throw — a validation failure inside `diff()`
    // (which runs `checkValid` on both documents), or any unexpected error in
    // the body — becomes a `documentInvalid` reject. The gate never throws to
    // the caller, so the resolver fails closed to the bundled document rather
    // than crashing.
    try {
      final report = FlowDocumentCompatibility.diff(from: client, to: active);

      final floorRejection = _screenArtifactFloorRejection(
        client: client,
        active: active,
      );
      if (floorRejection != null) return floorRejection;

      final blocking = <FlowDocumentCompatibilityChange>[];
      for (final change in report.changes) {
        if (change.code == _screenArtifactChangedCode) continue;
        if (change.classification == FlowCompatibilityClassification.free) {
          continue;
        }
        blocking.add(change);
      }

      if (blocking.isNotEmpty) {
        return FlowActiveRenderRejected(
          reason: FlowActiveRenderRejectionReason.contractSurfaceExpanded,
          message: _summarizeBlockingChanges(blocking),
          blockingChanges: List.unmodifiable(blocking),
        );
      }

      return const FlowActiveRenderAccepted();
    } on Object catch (error) {
      return FlowActiveRenderRejected(
        reason: FlowActiveRenderRejectionReason.documentInvalid,
        message: 'Flow document evaluation failed: $error',
      );
    }
  }
}

FlowActiveRenderRejected? _screenArtifactFloorRejection({
  required FlowDocument client,
  required FlowDocument active,
}) {
  // The baseline is the client DOCUMENT's `minClient`, mirroring the runtime
  // gate `artifact.minClient > flow.minClient` (the resolver's validation).
  // Codegen emits the bundled document's `minClient` and the generated flow
  // ref's `minClient` from the same source, so `client.minClient` equals the
  // installed client's capability. (A client whose bundled document declares a
  // floor above its own capability cannot render its bundled fallback either,
  // so it is non-renderable independently of this gate.) An artifact present
  // only in `active` is caught as `screenArtifactAdded` (rejected) before its
  // floor matters, so iterating the shared keys is sufficient.
  for (final entry in client.screenArtifacts.entries) {
    final activeArtifact = active.screenArtifacts[entry.key];
    if (activeArtifact == null) continue;

    // The runtime hardcodes `artifact.schemaVersion != 1`; the self-relative
    // check here and that hardcoded check must move together at schema v2.
    if (activeArtifact.minClient > client.minClient ||
        activeArtifact.schemaVersion != entry.value.schemaVersion) {
      return FlowActiveRenderRejected(
        reason: FlowActiveRenderRejectionReason.capabilityFloorRaised,
        message: 'Screen artifact "${entry.key}" raised its capability floor.',
      );
    }
  }

  return null;
}

String _summarizeBlockingChanges(
  List<FlowDocumentCompatibilityChange> changes,
) {
  final codes = changes.map((change) => change.code).toSet().join(', ');
  return 'Active document changes are not content-only: $codes.';
}

/// The render-gate decision. Sealed: a verdict is exactly one of
/// [FlowActiveRenderAccepted] or [FlowActiveRenderRejected].
sealed class FlowActiveRenderVerdict {
  const FlowActiveRenderVerdict();

  /// Whether the active document is safe to render under the client.
  bool get accepted;
}

/// The active document renders safely under the client (content-only change,
/// or the two documents are identical).
@immutable
final class FlowActiveRenderAccepted extends FlowActiveRenderVerdict {
  /// Creates an accepted verdict.
  const FlowActiveRenderAccepted();

  @override
  bool get accepted => true;

  @override
  bool operator ==(Object other) => other is FlowActiveRenderAccepted;

  @override
  int get hashCode => (FlowActiveRenderAccepted).hashCode;

  @override
  String toString() => 'FlowActiveRenderAccepted()';
}

/// The active document is unsafe to render under the client; the SDK fails
/// closed to the bundled document (in P3).
@immutable
final class FlowActiveRenderRejected extends FlowActiveRenderVerdict {
  /// Creates a rejected verdict with a typed [reason] and diagnostics.
  const FlowActiveRenderRejected({
    required this.reason,
    required this.message,
    this.blockingChanges = const [],
  });

  /// Why the active document was rejected.
  final FlowActiveRenderRejectionReason reason;

  /// A human-readable diagnostic (for logs/events; not localized).
  final String message;

  /// The `diff()` changes that caused the rejection, for diagnostics. Empty for
  /// [FlowActiveRenderRejectionReason.capabilityFloorRaised] and
  /// [FlowActiveRenderRejectionReason.documentInvalid] (not change-derived).
  final List<FlowDocumentCompatibilityChange> blockingChanges;

  @override
  bool get accepted => false;

  @override
  bool operator ==(Object other) {
    return other is FlowActiveRenderRejected &&
        other.reason == reason &&
        other.message == message &&
        _changesEqual(other.blockingChanges, blockingChanges);
  }

  @override
  int get hashCode => Object.hash(
        reason,
        message,
        Object.hashAll(blockingChanges.map((c) => c.code)),
      );

  @override
  String toString() =>
      'FlowActiveRenderRejected(reason: $reason, message: $message)';
}

/// The category of a [FlowActiveRenderRejected] verdict.
enum FlowActiveRenderRejectionReason {
  /// The active document expands or alters the client-observable contract —
  /// a declared action, a reachable terminal-result shape, an outbound field,
  /// the flow graph, flow-state, or any breaking/forwarding change.
  contractSurfaceExpanded,

  /// An existing screen artifact's capability floor rose above what the client
  /// can honor (`minClient` raised above the client document's floor, or
  /// `schemaVersion` changed).
  capabilityFloorRaised,

  /// The client or active document failed validation; the gate fails closed.
  documentInvalid,
}

bool _changesEqual(
  List<FlowDocumentCompatibilityChange> a,
  List<FlowDocumentCompatibilityChange> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i].code != b[i].code ||
        a[i].path != b[i].path ||
        a[i].classification != b[i].classification) {
      return false;
    }
  }
  return true;
}
