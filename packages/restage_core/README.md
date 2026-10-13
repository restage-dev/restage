# restage_core

[![pub package](https://img.shields.io/pub/v/restage_core.svg)](https://pub.dev/packages/restage_core) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

The `restage.core` widget catalog for [Remote Flutter Widgets](https://pub.dev/packages/rfw):
58 cross-platform layout, structure, and decoration widgets, including
Container, Column, Row, Stack, SizedBox, Padding, Center, Text, and Image.
Add your own design-system widgets to the catalog with `@RestageWidget`.

The package provides:

- **Catalog metadata** that authoring tools and the code generator read.
- **An RFW `LocalWidgetBuilder` map** that renders the catalog's widgets. Any
  RFW host can use it.
- **A few widgets compiled into your app** for behavior RFW can't express as
  data: the motion helpers (`RestageMotion`, `RestageFadeIn`, `RestagePulse`,
  `RestageStagger`, and the `RestageSpring` presets) and the number and price
  formatters (`RestagePrice`, `RestageFormattedNumber`).

You write surfaces in plain Flutter; standard widgets such as Container and
Text map to the catalog. The same widgets build onboarding, messages, surveys,
paywalls, or any other screen.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
