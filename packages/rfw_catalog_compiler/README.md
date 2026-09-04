# rfw_catalog_compiler

[![pub package](https://img.shields.io/pub/v/rfw_catalog_compiler.svg)](https://pub.dev/packages/rfw_catalog_compiler) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

Analyzer-backed compiler pipeline that turns annotated Dart widget libraries
into a [Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) catalog. It walks an app's
`@RestageLibrary` / `@RestageWidget` source with the Dart analyzer, builds an
internal IR, allocates stable wire IDs, and lowers the result to the public
`rfw_catalog_schema` wire shape: the durable contract that authoring tools, SDK
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
  `rfw_catalog_schema` types: `Catalog`, `WidgetEntry`, `StructuredEntry`,
  `UnionEntry`, and the rest.
- **Wire-ID allocation.** An append-only event log, replay, and current-state
  materialization that mints stable, monotonic `WireId`s and re-uses the
  recorded ID for an entry that already exists, so identity survives across
  regenerations. `rename` events preserve identity across label changes and
  source moves; a cascading class move also moves the recorded source
  identities of its owned properties, fields, variants, and parameters. A
  later cascade also normalizes descendants left under an earlier source by a
  non-cascading event when that would keep live descendant identities unique;
  otherwise replay fails atomically so the duplicate can be explicitly
  deprecated or reconciled first. Every rename also preflights the target's
  projected allocation identity against other live entries of the same kind.
  Unnamed constructor variants use `<unnamed>` as the event's canonical
  `from`/`to` label while retaining `namedConstructor: null` in state; their
  projected source must end in exactly one canonical `.` delimiter. Cascades
  use the most specific matching current or historical owner prefix and join
  owner and parameter sources with exactly one delimiter across named ↔ unnamed
  constructor transitions.
  `deprecate` records an intentional retirement. Backfill helpers re-attach
  recorded IDs to a freshly walked catalog, and a cross-reference linker
  applies allocated IDs to post-allocation reference sites with explicit
  duplicate-key detection.
- **Compatibility diff.** Per-entry change detection between two catalog
  versions, a forwarding/breaking compatibility classifier, and `CompatRule`
  emission: the tooling that decides whether a regenerated catalog is a safe
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

The barrel re-exports the walker, lowering, wire-ID, diff, link, policy, and
adapter entry points used for reflector integration; the full IR remains
internal under `src/ir`.

## License

Licensed under the Functional Source License, Version 1.1, ALv2 Future License
(FSL-1.1-ALv2): free for all use except building a competing product; each
release automatically becomes Apache-2.0 two years after publication. See
`LICENSE` for the full terms.
