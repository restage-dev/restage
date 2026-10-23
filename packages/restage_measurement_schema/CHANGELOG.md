# Changelog

## Unreleased

- The disclosure floor is not a constant in this package. The service states the
  floor it applied in each response (`disclosureFloor`), and a client shows a
  held count as less than that number.
- `MeasurementDeliveryDiagnosticsV1` and `SurfaceFunnelViewV1` accept any
  positive floor. A stated reason count must clear the floor its reading
  carries.
- `publicationLineDigestV1`, `artifactDefinitionDigestV1` and
  `declaredArtifactBytesDigestV1` compute the publication identity digests the
  compiler, the CLI and the server share. `kMintedArtifactIdPrefix` is the
  prefix of a minted artifact identity.
- An ordered capture route can name the drop-off band it contributes to.
  `MeasurementOrderedCaptureDeclarationV1` carries an optional
  `breakdownPointV1`, and the canonical JSON gains the same optional key. A
  route that names no band encodes exactly as before.
- A breakdown point must describe the route that declares it. A question names
  its own answer route, a page index names the screen whose presentation it
  observes, and a named interaction names one non-presentation callback on an
  exact screen. Anything else is refused at construction.
- One band has one route in a capture. Two routes carrying the same point are
  refused.
- `MeasurementBreakdownPointV1.identity` publishes what makes a point one band:
  its kind and its reference, as a single string, exact within one published
  version.
- `kMeasurementBreakdownPointReferenceLimitV1` publishes the length bound a
  point's reference and label already carried, so a caller can check a value
  before constructing one.

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
  package. The service evaluates them, so that vocabulary belongs to the service
  and is not published here.
