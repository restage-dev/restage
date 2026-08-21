# Changelog

## 0.1.0

- Establish the deterministic measurement and experiment contract surface an
  app compiles against: the measurement targets and identifiers, the canonical
  JSON codec and its digests, the publication bindings, drafts, candidates,
  routes and bundled registries, the published identity and manifest records,
  the lineage entries, the ingest envelopes, and the governed-subject request
  and result types the SDK uses to link, reset, and withdraw consent for a
  subject. Purpose and subject policies appear as revision references (the
  exact revision and the accepted-set hash) rather than as policy bodies.
- These contracts are inert data. They describe what is measured and how a
  subject is governed. They compute nothing and reach no network.
- The policy bodies, the audience and eligibility vocabulary, the metric and
  metric-binding definitions, the layer and activation vocabulary, and
  statistical inference and result reporting are deliberately not part of this
  package. The service evaluates them, so that vocabulary is platform-internal
  and is not published here.
