# Changelog

## 2.0.0

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
- Re-export the pure-Dart A2UI and RFW customer target annotations from the
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
