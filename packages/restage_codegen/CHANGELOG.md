# Changelog

## 1.0.1

- Widen the `analyzer` dependency constraint to admit the latest stable
  analyzer and raise the floor to a supported version.

## 1.0.0

- Initial release of the Restage build-time code generator: the `build_runner`
  builders that compile Flutter-authored surfaces (annotated source classes and
  hand-authored `.rfwtxt`) into `.rfwtxt` / `.rfw` blobs, capability manifests,
  flow documents, and generated screen/flow descriptors. Includes
  structured-type decomposition, constant folding, theme-binding lowering,
  capability derivation, and the optional A2UI (genui) emit target.
