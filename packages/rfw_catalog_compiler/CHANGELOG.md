# Unreleased — coordinated breaking release

- Carry open event properties through compiler IR without a closed event-name
  list or rename field, and lower canonical catalog schema v5.
- Allow wire-ID `rename` events to express source-only moves and opt into
  carrying an owning class's source move through its properties, fields,
  variants, and parameters. A later cascade can also normalize descendants
  left under an earlier source by a non-cascading rename, and fails atomically
  if that would collapse two live descendants onto one identity. Renames also
  fail atomically if the target itself would collide with another live entry.
  Source-only moves of unnamed constructor variants use a canonical event
  label, require exactly one trailing source delimiter, and cascade through
  their parameters from the most specific current or historical owner prefix
  with exactly one delimiter across named/unnamed changes.

# 1.2.0

- Preserve typed property constraints through compiler IR, linking, adapters,
  and schema lowering.
- Resolve deterministic nested field descriptions for structured catalog
  shapes.
- Require `rfw_catalog_schema` ^1.2.0.

# 1.1.0

- Resolve a property typed as a list of structured values to the opaque
  list-of-structured shape added in `rfw_catalog_schema` 1.1.0, so the item
  shape survives the walk instead of degrading to an unknown list.
- Require `rfw_catalog_schema` ^1.1.0.

# 1.0.3

- Documentation: README refresh.

# 1.0.2

- Export the element-FQN helpers (`elementFqn`, `interfaceFqn`, `typeFqn`,
  `classElementFor`, `interfaceFqnOrNull`) from the public API.

# 1.0.1

- Widen the `analyzer` dependency constraint to `>=10.0.0 <15.0.0`: raise the
  floor to a verified-compiling version and admit the latest stable analyzer
  (14.x). Update a test fake to implement the `nullabilitySuffix` member that
  analyzer 14 added to the element interface.
- Add an example.

# 1.0.0

- Initial release of the analyzer-backed catalog compiler pipeline: the source
  walker (`walkRestageLibrary` / `walkStructuredType` / union resolution with
  value-shape and default-value resolution), the internal IR, IR-to-schema
  lowering (`lowerStructured` / `lowerUnion`), wire-ID allocation via an
  append-only event log with replay, backfill, and cross-reference linking, the
  catalog compatibility diff (change detection + compatibility classifier +
  `CompatRule` emission), the policy layer (deny-lists, heuristics, metadata
  inference, stability), and the reflector-integration adapter.
