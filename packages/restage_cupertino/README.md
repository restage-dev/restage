# restage_cupertino

[![pub package](https://img.shields.io/pub/v/restage_cupertino.svg)](https://pub.dev/packages/restage_cupertino) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

A curated [Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) catalog of Cupertino (Apple HIG) widgets
for server-driven Flutter UI — the `restage.cupertino` library
(`CupertinoButton` and `CupertinoButtonFilled`, navigation/page scaffolding,
switches, sliders, pickers, text fields, and more — 16 widgets). Sibling to
`restage_core` and `restage_material`.

The package provides catalog metadata (`lib/registry.dart` `kRegistry`, mirrored
to `lib/src/widget_catalog/catalog.json`) and an RFW `LocalWidgetBuilder`
registration map (`lib/src/registration.g.dart`); the standard Cupertino widgets
are mapped through the catalog. A surface that uses `CupertinoButton` renders
through the `restage.cupertino` library — it is registered and works.

The catalog is surface-general — the same widgets compose any server-driven UI
surface.

## Status

`1.0.0` — stable public release. The wire format is frozen at v1. Cupertino
coverage is the smallest of the three catalogs and grows demand-first.

## License

BSD-3-Clause — see `LICENSE`.
