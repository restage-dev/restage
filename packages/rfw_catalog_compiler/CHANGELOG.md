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
