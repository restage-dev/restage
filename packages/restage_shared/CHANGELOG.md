# Changelog

## Unreleased

Flow documents gain the `always` and `matches` host-action result predicates,
and `actionResultPredicateSchemaIssue` checks a predicate against a result
schema. `kJoinedStringClientFloor` is the client capability for text joined
from parts.

**Breaking:** the `legacy_analytics.dart` entrypoint is removed. Measure
through `package:restage_measurement_schema/restage_measurement_schema.dart`.

**Breaking:** the `meter.dart` entrypoint is removed, with `FoldUsd`,
`FoldUsdValue`, `FoldUsdOverflow`, `foldEntryUsd` and `isPositiveDecimalRate`.

**Breaking:** catalog occurrence resolution moves to `restage_compiler_core`.
`rfw_formats.dart` no longer exports `ResolvedRfwCatalogOccurrenceSet`,
`ResolvedRfwCatalogOccurrenceRebinding`, `RfwCatalogOccurrence`,
`RfwCatalogOccurrenceDescriptor`, `RfwCatalogOccurrenceFinalBinding`,
`RfwCatalogOccurrenceHandle` or `RfwCatalogOccurrenceLocalDeclarationAnchor`.
The resolution input (`RfwCatalogOccurrenceResolutionInput`,
`RfwCatalogConstructorProvenance`, `RfwCatalogLocalSymbol`) stays here, with
its JSON unchanged.

`PlacementBatchUseFallbackV1` carries the service's signed `fallbackReceipt`,
the `selectedSurface` the build cannot show, and the `routeId` of the rule that
selected it. `fallbackReceiptReason` gives the reason a fallback receipt
states. `receiptsDirectory` and `receiptPathSegment` name where release
receipts are written.

`PlacementBatchRefusalReasonV1.decodeFailed` reports a placement response the
client could not read. Only the client produces it: the codecs refuse it in a
response body.

`SurfacePublicationArtifactClosure` exposes its verified `screenBlobs` and
`sidecarCapabilities`. `capabilityManifestUnion` combines capability
manifests. `rfw_formats.dart` exports `literalIconCodePoints` and
`kMaximumRfwCatalogOccurrenceCount`.

`SurfacePayload` carries an optional editor-state section (`SurfaceEditorState`)
with a draft. A published payload never carries it; `publishableDraftPayload`
strips it and trims each library to the declarations its root widget reaches.
`surfaceRootWidgetName` names that root.

`canonicalizeLibrary` returns a library with its declarations and every map's
keys in one canonical order, so the same content always encodes to the same
bytes.

`flowScreenEventGaps` lists the events a flow's screens emit that the state
showing them does not handle.

Publishing refuses a surface that emits a reserved purchase or restore event,
such as `purchase`, `restore` or a `restage.purchase.*` name. The runtime drops
those events, so the control would do nothing.

`sampleHostContext` builds sample host data from a screen's declared inputs.

New library `package:restage_shared/catalog.dart`, the catalog names generated code
needs.

The render bundle channel helpers (`isValidRenderBundleChannel`,
`validateRenderBundleChannel`, `renderBundleMainChannel`,
`renderBundleUserHandleMaxLength`) are removed; builds are addressed by
environment and person.

## 2.0.0

- The `data.device.*` contract publishes `viewPaddingTop`,
  `viewPaddingBottom`, `viewPaddingLeft` and `viewPaddingRight` — the insets
  the operating system applies regardless of what covers the screen.
- The `data.theme.*` contract publishes `brightness`, a `light` / `dark` token
  for the ambient theme's brightness.
- The `data.theme.*` contract publishes `textTheme.<style>.<field>` for the
  fifteen Material text-theme styles. Each style, and `defaultTextStyle`,
  carries every `TextStyle` field a slot holds as a scalar or a list of
  scalars: `color`, `backgroundColor`, `fontFamily`, `fontFamilyFallback`,
  `fontSize`, `fontWeight`, `fontStyle`, `letterSpacing`, `wordSpacing`,
  `height`, `leadingDistribution`, `textBaseline`, `overflow`, `decoration`,
  `decorationColor`, `decorationStyle`, and `decorationThickness`. `shadows`,
  `fontFeatures`, `fontVariations`, `foreground`, `background`, `locale`,
  `debugLabel`, and `inherit` are not carried.
- The published `data.device.*` contract is shared as `kDeviceContractPaths`
  and `kDeviceContractPathKinds`, and gains the `languageCode` and
  `countryCode` locale subtags. It also gains `shortestSide`,
  `longestSide`, and `orientation`.

- **Breaking:** `SurfaceExperimentAssignment` and assignment fields on
  standalone-screen delivery types are removed. Purchase-intent and analytics
  envelopes no longer include experiment assignment metadata.
- **Breaking:** the default `restage_shared.dart` export no longer exposes the
  former commerce types: purchase intents, entitlement synchronization,
  transaction reporting, offer signatures, `RestageProduct`,
  `RestageEntitlement`, and `EntitlementSource`. For new provider-neutral
  requests and responses, import `package:restage/commerce.dart`.
- **Breaking:** flow documents now support schema version 2 for typed survey
  declarations. Version 2 carries the ordered `surveyQuestionOrder` field;
  version 1 remains accepted without that field.
- **Breaking:** the legacy behavioral-analytics event and wire vocabulary
  (`AnalyticsEvent`, `AnalyticsAppContext`, the reserved-key and clock-skew
  helpers, the taxonomy registry, and the wire enums) moves behind the
  `legacy_analytics.dart` entrypoint and leaves the default export. Import
  `package:restage_shared/legacy_analytics.dart` to keep using it. It retires
  with the legacy analytics runtime. New code should measure through
  `package:restage_measurement_schema/restage_measurement_schema.dart`.
- **Breaking:** re-export catalog schema v5, where callback property names are
  open event identities and the closed event-name enum is removed. Decoding a
  v4 catalog still works.
- Re-export the pure-Dart A2UI and RFW custom target annotations from the
  new `a2ui.dart` and `rfw.dart` entrypoints.

## 1.2.0

- Re-export the typed constraint model and nested-data annotations from
  `rfw_catalog_schema` 1.2.0.

## 1.1.0

- Additive schema support for upcoming surface work; no breaking changes.

## 1.0.2

- Add flow predicate sugar: the `FlowPredicateOperator` /
  `FlowPredicateValueArity` vocabulary and related flow-document support for
  decision-state authoring.

## 1.0.1

- Add a usage example.

## 1.0.0

- Initial public release: the Restage paywall/surface format, schemas, validation,
  and shared catalog types.
- Vendor `package:rfw` 1.1.3's `formats` sublibrary into `lib/src/rfw_formats/`
  (`binary.dart`, `model.dart`, `text.dart`) so the Restage backend can parse
  `.rfwtxt` and round-trip `.rfw` blobs from pure-Dart server images without taking a
  Flutter SDK dependency.
- Add `lib/src/rfw_formats.dart` barrel mirroring upstream `package:rfw/formats.dart`.
- Re-export the rfw formats API from the package barrel (`lib/restage_shared.dart`).
- Reproduce upstream BSD-3-Clause license verbatim at `lib/src/rfw_formats/LICENSE-rfw`
  for attribution.
