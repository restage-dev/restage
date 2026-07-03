---
title: Custom widget catalog resolution + docs refresh
headline_tag: restage_codegen-v1.1.0
---
## Registered custom widgets now resolve in authored surfaces

`restage_codegen` emits your widget catalog (`catalog.json`) at build time, so a
surface that references one of your `@RestageWidget` custom widgets resolves it
correctly. If you author surfaces with your own registered widgets, upgrade
`restage_codegen` to pick this up.

## Also in this release

- **Documentation refresh** across the published packages — the READMEs and the
  quickstart now match the current authoring model.
- Internal groundwork and additional test coverage. Additive only, no breaking changes.

**Versions:** `restage_codegen` 1.1.0 · `restage` 1.2.0 · `restage_shared` 1.1.0 ·
`restage_core` / `restage_material` / `restage_cupertino` 1.0.2 ·
`rfw_catalog_schema` / `rfw_catalog_compiler` 1.0.3 · `restage_a2ui` 0.1.4
