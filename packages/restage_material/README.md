# restage_material

[![pub package](https://img.shields.io/pub/v/restage_material.svg)](https://pub.dev/packages/restage_material) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

[Restage](https://restage.dev) is server-driven UI for Flutter: it lets a team
change any screen of a shipped Flutter app without a release.

This README describes the `main` branch. For a released version, see its page on pub.dev.

The `restage.material` widget catalog for [Remote Flutter Widgets](https://pub.dev/packages/rfw):
47 Material Design widgets, including buttons, Scaffold, AppBar, Card,
ListTile, chips, and selection controls. It sits alongside `restage_core` and
`restage_cupertino`. Add your own design-system widgets to the catalog with
`@RestageWidget`.

The package provides catalog metadata for authoring tools and the code
generator, and an RFW `LocalWidgetBuilder` map that renders the catalog's
widgets. It also ships interactive widgets whose gesture and animation logic
is compiled into your app: `RestageModalSheet`, `RestageDraggableSheet`,
`RestagePager`, `RestageDropdown`, `RestageRadioGroup`,
`RestageSegmentedButton`, and `RestageToggleButtons`. Surfaces set their
properties and receive their events.

You write surfaces in plain Flutter; standard Material widgets map to the
catalog. The same widgets build onboarding, messages, surveys, paywalls, or any
other screen.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
