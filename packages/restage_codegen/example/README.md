# restage_codegen example

`restage_codegen` is the build-time code generator that translates idiomatic
Flutter widget source — annotated source classes and hand-authored `.rfwtxt`
files — into the `.rfwtxt` / `.rfw` render artifacts, capability manifests, and
catalogs that drive server-driven UI.

## How it's wired

You do not import this package's library API in app code. It is a set of
`build_runner` builders applied automatically to dependents. Add it as a
`dev_dependency` alongside `build_runner`:

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  restage_codegen: any
```

Then run the build from your package root:

```sh
dart run build_runner build
```

The builders pick up the right inputs by file location and write their outputs
alongside the source. From a single surface source they emit:

- `.rfwtxt` — the human-readable Remote Flutter Widget text form.
- `.rfw` — the compiled binary blob that gets decoded and rendered.
- `.capability.json` — the capability floor the blob declares, so an older
  reader fails closed rather than misrendering.
- A flow document / navigation plan and typed Dart descriptors for surfaces
  that move across multiple screens.

See the [package README](../README.md) for the full builder list, and
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples)
for surfaces wired up end to end.
