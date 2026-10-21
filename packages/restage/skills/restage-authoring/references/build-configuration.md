# Build configuration

Use [setup-and-delivery.md](setup-and-delivery.md) for the usual dependencies,
build commands, catalog size choice and optional bundled surfaces. Ordinary apps
can use the builder defaults. This reference covers custom output locations,
inspection reports and shared packages.

## Output options

Set these under `targets: $default: builders:` in the package's `build.yaml`.

| Option | Default | Effect |
| --- | --- | --- |
| `source_output_layout` | `generated_directory` | Writes each surface's generated part in a `restage.generated/` directory beside its source. `adjacent` puts the part beside the source file. |
| `dart_output_root` | Unset | Moves generated surface parts, Widgetbook stories and A2UI catalog Dart under a chosen `lib/` directory, overriding the source layout for those files. |
| `output_root` | `.restage/build` | Sets the root for portable bundles, reports, metadata and catalog data. Generated Dart has its own location. |
| `inspection_report` | `false` | Writes a readable `.restage.md` report for each compiled library, including its JSON and RFW text. |
| `bundled_runtime` | `false` | Places bundles under `assets/restage/bundles/` for the app to ship. Follow the asset setup in [setup-and-delivery.md](setup-and-delivery.md#optional-bundled-surfaces). |

An inspection report for `lib/messages/weekly_recap.dart` appears at
`.restage/build/reports/lib/messages/weekly_recap.restage.md` with the default
output root. Inspection works with unbundled output.

Roots must be package-relative paths without `.` or `..` segments or
`.dart_tool`. `dart_output_root` must be under `lib/` and cannot contain hidden
directories. It preserves source directories below `lib/`; for example,
`dart_output_root: lib/generated/restage` puts the part for
`lib/messages/weekly_recap.dart` at
`lib/generated/restage/messages/weekly_recap.restage.g.dart`.

When moving generated parts, update their authored `part` directives to the
relative paths the compiler reports. Aggregates such as
`lib/restage_surfaces.g.dart`, `lib/user_catalog.g.dart` and
`lib/user_factories.g.dart` keep their fixed locations.

With `bundled_runtime: true`, the same source produces
`assets/restage/bundles/lib/messages/weekly_recap.rsbundle`. `output_root` still
controls reports and metadata. Add each bundle directory to Flutter's asset list.

## Keep options consistent

Each surface builder reads these options independently. Repeat the same values
on all four builders below. Enabled A2UI and Widgetbook builders must receive
them too; mismatched values fail the build. Put the settings under the package's
target: root `global_options` overrides dependency packages' own choices.

This example enables inspection reports. It also shows both optional emitters;
keep only the emitter entries you use, after adding their dependencies from
[emitters.md](emitters.md).

```yaml
targets:
  $default:
    builders:
      restage_codegen:restage_source_roster:
        options: &restage_output
          inspection_report: true
      restage_codegen:restage_package_surface_compiler:
        options: *restage_output
      restage_codegen:generated_dart:
        options: *restage_output
      restage_codegen:outputs:
        options: *restage_output
      restage_codegen:user_a2ui_catalog:
        enabled: true
        options: *restage_output
      restage_codegen:widgetbook_stories:
        enabled: true
        options: *restage_output
```

Defaults need no options block or anchor. Emitter authoring settings belong on
annotations; see [emitters.md](emitters.md) for their options and generation steps.

## Reusable packages and workspaces

For a package that exports custom widgets, add `restage` to `dependencies` and
`restage_codegen` and `build_runner` to `dev_dependencies`. Build the package
before publishing, then run `restage library record` (MCP:
`restage_record_libraries`) to record its library versions in
`.restage/library-contracts/`. Commit and publish `.restage/wire-ids.events.jsonl` and
`.restage/library-contracts/` so consuming apps use the same identities and
library contracts.

Expose this state to consumer builds in the package's `build.yaml`:

```yaml
additional_public_assets:
  - .restage/**
```

If a target restricts `sources`, include `.restage/**` there too. Apply this to
each package that owns Restage state, including members built with
`dart run build_runner build --workspace`. The app declares the shared package
in `dependencies`, imports its library and runs its usual build.

## Package-wide builders

Several builders scan a package through a placeholder input. `generate_for`
cannot select individual widget or surface files for these builders: a glob
either excludes the placeholder entirely or leaves the whole scan enabled.

For a package that intentionally declares no custom widgets or surfaces, use
`enabled: false` on `restage_codegen:user_catalog`, `user_catalog_json`,
`user_factories`, `restage_source_roster`, `restage_package_surface_compiler` and
`restage_surfaces`, each with the `restage_codegen:` prefix.

After adding, removing or renaming an annotated class, restart
`dart run build_runner watch`. A fresh `dart run build_runner build` discovers
the current declarations.
