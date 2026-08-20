# restage_core

[![pub package](https://img.shields.io/pub/v/restage_core.svg)](https://pub.dev/packages/restage_core) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

A curated [Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) catalog of cross-platform widget
primitives for server-driven Flutter UI: the `restage.core` library (layout,
structure, and decoration: Container, Column, Row, Stack, SizedBox, Padding,
Center, Text, Image, and more; 57 widgets in all).

Part of [Restage](https://restage.dev), server-driven UI for Flutter. Extend this
catalog with your own design-system widgets via `@RestageWidget`.

The package provides:

- **Catalog metadata.** The curated widget set + per-widget metadata, authored
  in `lib/registry.dart` (`kRegistry`) and mirrored to
  `lib/src/widget_catalog/catalog.json`. Authoring tools read the registry; the
  build-time code generator reads the JSON.
- **RFW registration.** `lib/src/registration.g.dart` is a plain `rfw`
  `LocalWidgetBuilder` map that renders the catalog's widgets; any RFW host can
  use it.
- **A few compiled-in catalog widgets.** Small composites the package ships as
  real classes for behavior RFW can't express declaratively: the motion helpers
  (`RestageMotion`, `RestageFadeIn`, `RestagePulse`, `RestageStagger`, and the
  `RestageSpring` substrate) and the number/price formatters (`RestagePrice`,
  `RestageFormattedNumber`). Standard Flutter widgets (Container, Text, …) are
  mapped through the catalog; you author surfaces in plain Flutter syntax.

The catalog is surface-general: the same primitives compose paywalls,
onboarding, in-app messages, surveys, or any other server-driven UI surface.

## Status

Stable: `1.0.0`.

## License

BSD-3-Clause. See `LICENSE`.
