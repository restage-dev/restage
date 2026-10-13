# restage_cupertino

[![pub package](https://img.shields.io/pub/v/restage_cupertino.svg)](https://pub.dev/packages/restage_cupertino) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

The `restage.cupertino` widget catalog for [Remote Flutter Widgets](https://pub.dev/packages/rfw):
16 Cupertino (Apple-style) widgets, including `CupertinoButton` (and
`CupertinoButton.filled`), navigation and page scaffolding, switches,
sliders, pickers, and text fields. It sits alongside `restage_core` and
`restage_material`. Add your own design-system widgets to the catalog with
`@RestageWidget`.

The package provides catalog metadata for authoring tools and the code
generator, and an RFW `LocalWidgetBuilder` map that renders the catalog's
widgets. You write surfaces in plain Flutter; standard Cupertino widgets map to
the catalog. The same widgets build onboarding, messages, surveys, paywalls, or
any other screen.

Cupertino has the fewest widgets of the three catalogs.
[Open an issue](https://github.com/restage-dev/restage/issues) for any widget
you need.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
