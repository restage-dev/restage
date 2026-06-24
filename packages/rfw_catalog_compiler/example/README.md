# rfw_catalog_compiler example

`rfw_catalog_compiler` is the analyzer-backed pipeline that turns annotated Dart
widget libraries into an RFW widget catalog. It walks a library's
`@RestageLibrary` / `@RestageWidget` source, builds an internal IR, allocates
stable wire IDs, and lowers the result to the public `rfw_catalog_schema` wire
shape.

## The pipeline

The compiler composes a sequence of passes, exposed through the package barrel:

1. **Walk** — `walkRestageLibrary` reads a barrel's `@RestageLibrary`
   declaration and collects its exported `@RestageWidget` classes; companion
   passes (`walkStructuredType`, `resolveUnion`) decompose structured types and
   discriminated unions.
2. **Build IR** — typed intermediate-representation nodes for widgets,
   properties, structured types, unions, factory variants, and diagnostics.
3. **Lower** — `lowerStructured`, `lowerUnion`, and the catalog-level lowering
   translate the IR to `rfw_catalog_schema` types (`Catalog`, `WidgetEntry`,
   `StructuredEntry`, `UnionEntry`, …).
4. **Allocate wire IDs** — an append-only event log mints stable, monotonic
   `WireId`s and re-uses the recorded ID for an entry that already exists, so
   identity survives across regenerations.

A compatibility-diff pass then classifies a regenerated catalog as a safe
forwarding change or a breaking one.

In practice the compiler is driven through the reflector adapter the barrel
re-exports, which runs the walk → IR → lowering → wire-ID resolution as one
step from a build. See the [package README](../README.md) for the full barrel
surface.
