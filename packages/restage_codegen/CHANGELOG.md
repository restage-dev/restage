# Changelog

## 1.0.1

- Widen the `analyzer` dependency constraint to `>=10.0.0 <14.0.0`: raise the
  floor to a verified-compiling version and admit analyzer 13.x. The ceiling
  stays below 14.0.0 because analyzer 14 removed `NamedExpression` and reshaped
  argument lists, which this package's lowering relies on; the `build_runner`
  toolchain (`build`) likewise does not yet support analyzer 14.
- Add an example.

## 1.0.0

- Initial release of the Restage build-time code generator: the `build_runner`
  builders that compile Flutter-authored surfaces (annotated source classes and
  hand-authored `.rfwtxt`) into `.rfwtxt` / `.rfw` blobs, capability manifests,
  flow documents, and generated screen/flow descriptors. Includes
  structured-type decomposition, constant folding, theme-binding lowering,
  capability derivation, and the optional A2UI (genui) emit target.
