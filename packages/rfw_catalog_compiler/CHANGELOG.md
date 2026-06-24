# 1.0.0

- Initial release of the analyzer-backed catalog compiler pipeline: the source
  walker (`walkRestageLibrary` / `walkStructuredType` / union resolution with
  value-shape and default-value resolution), the internal IR, IR-to-schema
  lowering (`lowerStructured` / `lowerUnion`), wire-ID allocation via an
  append-only event log with replay, backfill, and cross-reference linking, the
  catalog compatibility diff (change detection + compatibility classifier +
  `CompatRule` emission), the policy layer (deny-lists, heuristics, metadata
  inference, stability), and the reflector-integration adapter.
