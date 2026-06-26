# Changelog

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
