/// A host-supplied set of initial flow-state values.
///
/// Generated seed builders implement this; the flow runtime validates the
/// returned map against the flow's declared seedable keys before use.
abstract interface class FlowSeed {
  /// The initial flow-state values to overlay, keyed by flow-state key.
  Map<String, Object?> toFlowState();
}
