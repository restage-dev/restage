import 'package:restage_shared/src/flow_document/flow_active_render_gate.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';

/// Structural-permissive active-render predicate for general delivery mode.
///
/// [FlowActiveRenderGate] is the content-only gate for typed flow documents: it
/// rejects changes to the client-observable contract, including topology,
/// terminal-result shape, actions, outbound fields, and capability floors. This
/// gate is its sibling for general flow documents: structural changes are
/// permitted because the release-gated boundary is capability, not topology.
///
/// This gate does not re-implement floor, required-library, validity, or
/// action-contract checks. Those checks remain binding downstream dependencies
/// of the consumer that resolves and renders the active document. This gate
/// adds only marker integrity: the permissive path accepts exactly a general
/// client paired with a general active document.
///
/// The delivery-mode marker is a forward-contract capability requirement for
/// general-mode rendering. Refusing any non-general client or active document
/// is part of that capability gate by design: a client that does not implement
/// general-mode rendering fails closed instead of being evaluated under this
/// permissive predicate.
///
/// Pure and total: never throws to the caller. Any error rejects with
/// [FlowActiveRenderRejectionReason.documentInvalid].
abstract final class GeneralFlowRenderGate {
  /// Evaluates whether [active] renders under [client] on the general path.
  static FlowActiveRenderVerdict evaluate({
    required FlowDocument client,
    required FlowDocument active,
  }) {
    try {
      if (client.deliveryMode != FlowDeliveryMode.general ||
          active.deliveryMode != FlowDeliveryMode.general) {
        return FlowActiveRenderRejected(
          reason: FlowActiveRenderRejectionReason.documentInvalid,
          message: 'General render gate requires general delivery mode for '
              'both documents; got client=${client.deliveryMode.wireName}, '
              'active=${active.deliveryMode.wireName}.',
        );
      }

      return const FlowActiveRenderAccepted();
    } on Object catch (error) {
      return FlowActiveRenderRejected(
        reason: FlowActiveRenderRejectionReason.documentInvalid,
        message: 'General render gate evaluation failed: $error',
      );
    }
  }
}
