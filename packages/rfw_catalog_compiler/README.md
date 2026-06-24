# rfw_catalog_compiler

[![pub package](https://img.shields.io/pub/v/rfw_catalog_compiler.svg)](https://pub.dev/packages/rfw_catalog_compiler) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

Analyzer-backed compiler pipeline that turns annotated Dart widget libraries
into a [Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) catalog. It walks a customer's
`@RestageLibrary` / `@RestageWidget` source with the Dart analyzer, builds an
internal IR, allocates stable wire IDs, and lowers the result to the public
`rfw_catalog_schema` wire shape — the durable contract that editors, SDK
runtimes, and backends decode.

A catalog produced here describes the widget vocabulary available to any
server-driven UI surface, independent of which surface is being rendered.

## What this package contains

- **Source walker.** Analyzer-backed passes over annotated Dart libraries.
  `walkRestageLibrary` reads a barrel's `@RestageLibrary` declaration and
  collects its exported `@RestageWidget` classes; `walkStructuredType`
  decomposes structured types (records, named-constructor variants) and
  `resolveUnion` resolves discriminated unions. `classifyStructured`,
  the value-shape resolver, the default-value resolver (constant evaluation,
  theme-binding and static-const member resolution), and a stable set of
  walker issue codes back these passes.
- **Internal IR.** Typed intermediate-representation nodes for widgets,
  properties, structured types, unions, design tokens, factory variants,
  decomposition recipes, provenance, policy decisions, and diagnostics.
- **Lowering.** `lowerStructured` and `lowerUnion` (and the catalog-level
  lowering they compose into) translate compiler IR to the canonical
  `rfw_catalog_schema` types — `Catalog`, `WidgetEntry`, `StructuredEntry`,
  `UnionEntry`, and the rest.
- **Wire-ID allocation.** An append-only event log, replay, and current-state
  materialization that mints stable, monotonic `WireId`s and re-uses the
  recorded ID for an entry that already exists, so identity survives across
  regenerations. Backfill helpers re-attach recorded IDs to a freshly walked
  catalog, and a cross-reference linker applies allocated IDs to
  post-allocation reference sites with explicit duplicate-key detection.
- **Compatibility diff.** Per-entry change detection between two catalog
  versions, a forwarding/breaking compatibility classifier, and `CompatRule`
  emission — the tooling that decides whether a regenerated catalog is a safe
  forwarding change.
- **Policy layer.** Deny-lists, category and design-token heuristics, mutex
  rules, metadata inference, stability classification, and the structured-walk
  policy, with the built-in default content the compiler ships with, recorded
  through a policy ledger.
- **Reflector adapter.** An integration surface that drives the walk, IR build,
  lowering, and wire-ID resolution from the reflector/codegen build step,
  including resolver hooks for widget, property, structured, union, and
  deprecation identity.

## Status

The package is at `1.0.0`. The barrel re-exports the walker, lowering,
wire-ID, diff, link, policy, and adapter entry points used for reflector
integration; the full IR remains internal under `src/ir`.

## License

Licensed under the Functional Source License, Version 1.1, ALv2 Future License
(FSL-1.1-ALv2): free for all use except building a competing product; each
release automatically becomes Apache-2.0 two years after publication. See
`LICENSE` for the full terms.
