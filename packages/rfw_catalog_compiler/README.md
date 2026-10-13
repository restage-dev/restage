# rfw_catalog_compiler

[![pub package](https://img.shields.io/pub/v/rfw_catalog_compiler.svg)](https://pub.dev/packages/rfw_catalog_compiler) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

A compiler that turns annotated Dart widget libraries into a
[Remote Flutter Widgets (RFW)](https://pub.dev/packages/rfw) widget catalog.
It reads your `@RestageLibrary` and `@RestageWidget` source with the Dart
analyzer, assigns each widget and property a stable catalog ID, and writes the
result in the
[`rfw_catalog_schema`](https://pub.dev/packages/rfw_catalog_schema) format
that editors, SDK runtimes, and servers read.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

A catalog describes the widgets any surface can use, whichever surface is
being rendered.

## What this package contains

- **Source walker.** Reads annotated Dart libraries with the analyzer.
  `walkRestageLibrary` reads a library's `@RestageLibrary` declaration and
  collects the `@RestageWidget` classes it exports. `walkStructuredType`
  breaks structured types (records, named-constructor variants) into fields,
  and `resolveUnion` resolves tagged unions. Default values are worked out
  from constants and theme reads.
- **Catalog output.** `lowerStructured` and `lowerUnion`, and the catalog-level
  step built on them, turn the compiler's internal model into
  `rfw_catalog_schema` types: `Catalog`, `WidgetEntry`, `StructuredEntry`,
  `UnionEntry`, and the rest.
- **Catalog IDs.** An append-only event log assigns each widget, property, and
  structured type a stable ID that survives regeneration. `rename` events keep
  IDs across renames and file moves; `deprecate` retires one. If the log would
  produce two live entries with the same identity, replay fails and nothing is
  changed.
- **Compatibility check.** Compares two versions of a catalog entry by entry
  and reports whether the new one is compatible with the old or a breaking
  change.
- **Built-in rules.** Defaults for which widgets and properties are included
  and how they are categorized.
- **Build integration.** Entry points the Restage code generator uses to run
  the whole pipeline in a build step.

## API

The main library exports the walker, catalog output, catalog ID, compatibility,
and build-integration entry points. The compiler's internal model stays
private.

## License

FSL-1.1-ALv2. See [LICENSE](LICENSE).
