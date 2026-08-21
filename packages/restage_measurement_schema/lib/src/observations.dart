/// Closed observation-state algebra preserved by every reducer.
enum ObservationState {
  observedZero('observedZero'),
  observedValue('observedValue'),
  observedNoValue('observedNoValue'),
  semanticNull('semanticNull'),
  structurallyInapplicable('structurallyInapplicable'),
  sourceUnavailable('sourceUnavailable'),
  transportTruncated('transportTruncated'),
  domainRejected('domainRejected'),
  rightCensored('rightCensored'),
  latePending('latePending'),
  observedCapped('observedCapped');

  const ObservationState(this.wireName);
  final String wireName;
}
