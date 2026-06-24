# rfw_catalog_schema

[![pub package](https://img.shields.io/pub/v/rfw_catalog_schema.svg)](https://pub.dev/packages/rfw_catalog_schema) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The public schema, annotations, wire-identity types, and JSON codecs for a
[Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) catalog.

This package describes **what** a catalog looks like — the durable contract
shared between catalog producers (compilers, codegen builders), catalog
consumers (editors, SDK runtimes, backends), and any tooling that decodes
or transmits an RFW-targeted widget catalog.

## What this package contains

- **Catalog data types.** `Catalog`, `WidgetEntry`, `PropertyEntry`,
  `StructuredEntry`, `UnionEntry`, `FactoryVariant`, `DecompositionRecipe`,
  `DesignTokenEntry`, plus the enums and metadata structs they reference.
- **Wire identity.** `WireId` (kind-prefixed, library-scoped, monotonic),
  `WireIdKind`, and `WireIdRef` for cross-library references.
- **Default-value model.** `DefaultValueSource` sealed hierarchy
  (`LiteralDefault`, `TokenRefDefault`, `ThemeBindingDefault`,
  `FlutterCtorDefault`).
- **Annotations.** `@RestageWidget`, `@RestageProperty`,
  `@RestageBuiltinLibrary`, `@RestageLibrary`, `@RestageStructuredType`,
  `@RestageUnionVariant`, `@RestageFactoryVariant`, `@StableWidget`,
  `@StableProperty`, `@RfwIncompatible`, `@RestagePropertyPreview`.
- **Hand-written JSON codecs.** `encodeCatalog` and `decodeCatalog`.
- **Lifecycle types.** `DeprecationInfo` (two-layer: source vs catalog),
  `CompatRule` for forwarding/breaking changes, `ValidationExpr`.

Canonical v3 JSON is final-form only. Internal `WireId.unallocated*`
placeholders are available for transitional pre-allocator tooling, but
`WireId('w0000')` / `p0000` / etc. are not public IDs, `decodeCatalog`
rejects them, and `encodeCatalog` refuses to emit catalogs that still carry
those placeholders. Legacy v2 JSON is decoded into `LegacyCatalogV2` so a
baseline without wire IDs cannot masquerade as a canonical `Catalog`.

## What it does NOT contain

- **No compiler logic.** Analysis passes, IR types, the wire-ID allocator,
  and event-log replay live in the companion compiler package.
- **No runtime.** Theme resolution, wire-ID dispatching, and on-wire blob
  decoding live in the SDK runtime.
- **No Flutter dependency.** The package is pure Dart so it can be consumed
  by Dart-only backends and codegen pipelines.

## Stability

`1.0.0`: the public surface is stable. Semver is honoured from this
release; breaking changes require a major-version bump.
