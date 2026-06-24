# restage_material

[![pub package](https://img.shields.io/pub/v/restage_material.svg)](https://pub.dev/packages/restage_material) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

A curated [Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) catalog of Material Design widgets for
server-driven Flutter UI — the `restage.material` library (buttons, Scaffold,
AppBar, Card, ListTile, chips, selection controls, and more — 45 widgets).
Sibling to `restage_core` and `restage_cupertino`.

The package provides catalog metadata (`lib/registry.dart` `kRegistry`, mirrored
to `lib/src/widget_catalog/catalog.json`), an RFW `LocalWidgetBuilder`
registration map (`lib/src/registration.g.dart`), and a set of compiled-in
catalog widgets it ships as real classes:

- **Interactive composites** that own gesture/animation logic RFW can't express
  declaratively — `RestageModalSheet`, `RestageDraggableSheet`, `RestagePager`,
  `RestageDropdown`, `RestageRadioGroup`, `RestageSegmentedButton`,
  `RestageToggleButtons`.
- **Domain widgets** — `Package` (a product/plan card) and
  `ExpressCheckoutButton`.

Standard Material widgets are mapped through the catalog, not re-declared here.
The catalog is surface-general — the same widgets compose any server-driven UI
surface.

## License

BSD-3-Clause — see `LICENSE`.
