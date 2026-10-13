# Setup and delivery

## Packages

```sh
flutter pub add restage
flutter pub add --dev restage_codegen build_runner
```

Restage needs Flutter 3.41 or newer. The optional `restage` CLI can do this step with
`restage init`, which also writes `restage_config.yaml` and a starter paywall. Pass
`--no-starter` to skip the starter.

`restage init` adds the Restage state files to `build.yaml` so an edit to them
triggers a rebuild. If you set up without `init`, add them yourself:

```yaml
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
```

Generated mounts keep the widget you wrote as their fallback, so nothing has to be
bundled as an asset. Leave `bundled_runtime` at its default, `false`, for ordinary
examples and integrations. No generated surface assets are needed in `pubspec.yaml`.

## Build

```sh
dart run build_runner build   # once
dart run build_runner watch   # while editing
```

Run the build with the Dart that comes with Flutter, or set `FLUTTER_ROOT`: a surface
that draws icons ships a subset of their icon font, cut with a Flutter SDK tool.

Restart `watch` after adding, removing or renaming an annotated class. The
compiled-widget fallback follows Flutter's normal hot-reload rules.

The build writes, per annotated file:

- `restage.generated/<file>.restage.g.dart` next to the source: the generated mount,
  the reference (`<name>Ref`), and event and result types;
- `.restage/build/bundles/.../<file>.rsbundle`: the compiled surface;
- `.restage/build/metadata/restage.publication.json`: what `restage surface push` reads;
- `lib/restage_surfaces.g.dart`: `restageSurfaces`, every surface the package compiles;
- `lib/user_catalog.g.dart` and `lib/user_factories.g.dart` when the package declares
  custom widgets.

Commit the generated Dart files, `.restage/measurement-state.json` and
`.restage/wire-ids.events.jsonl` and `.restage/library-contracts/` when generated;
these keep analytics and catalog identities/contracts stable
across clean builds. `.restage/build/` is build output; `restage init` adds it to
`.gitignore`.

## Mounts

Prefer the generated mounts. Each falls back to the widget you wrote when nothing is
published, the network fails, or a version can't render on this app:

| Surface | Generated mount | Lower-level mount |
| --- | --- | --- |
| `@Screen(surface: ...)` | `<Class>Surface(...)` | `RestageScreen<E>(screen: <name>Ref, unavailable: ...)` |
| `@Paywall()` | `<Class>Surface(...)` | `RestagePaywall(id: '...')` |
| `@FlowGraph` | `<FlowName>Surface(onComplete: ...)` | `RestageFlowGraph<R>(flow: <name>Ref, unavailable: ...)` |

Every generated mount is an implicit placement. Use its ordinary constructor;
`.atPlacement('name', ...)` is an optional naming override.

Lower-level mounts require you to supply the fallback setup, such as an
`unavailable` policy, `fallbackBuilder` or bundled assets. Use them when you need
to manage that setup yourself.

`RestagePaywall(id: ...)` in an app with no generated mounts needs
`registerRestageWidgets()` (from the generated `user_factories.g.dart`) once at startup.

## Hosted delivery

```dart
const baseUrl = 'https://api.restage.dev';
const apiKey = String.fromEnvironment('RESTAGE_API_KEY'); // rs_pk_...

void main() {
  if (apiKey.isEmpty) {
    Restage.configure(); // renders what the app contains
  } else {
    Restage.configure(
      apiKey: apiKey,
      baseUrl: baseUrl,
      surfaces: restageSurfaces, // from 'restage_surfaces.g.dart'
    );
  }
  runApp(const MyApp());
}
```

- The key is the public SDK key (`rs_pk_...`) for one environment. The prefix names its
  side and environment, such as `rs_pk_sandbox_dev_` or `rs_pk_live_prod_`. Never put a
  secret key (`rs_sk_...`) in app code.
- `baseUrl` must be HTTPS, except `localhost`, `127.0.0.1` and `::1`.
- With the key and base URL configured, default hosted resolution covers screens,
  paywalls and flows. Do not add an explicit `flowResolver` for ordinary setup: a
  custom resolver overrides normal placement-aware flow resolution.
- Call `Restage.configure()` with no key to render only what the app contains.
- `surfaces: restageSurfaces` fetches every surface in the background as the app
  starts, so a surface's first mount can show its published version.
- A published version shows the next time the surface mounts. Live refresh, which
  updates a surface already on screen, is opt-in through the `liveRefresh` parameter.

## When delivery fails

A mount waits up to the render deadline for the published version: 300 ms by default,
set with `Restage.configure(renderDeadline: ...)`. If the version hasn't arrived by
then, the mount shows the best copy it has: the last published version saved on the
device, then the bundled copy, then the widget you wrote. The fetch keeps going and
saves what it receives for the next mount. When a user's experiment assignment isn't
ready by the deadline, they see the fallback and aren't counted in the experiment on
that mount.

A generated mount shows the widget you wrote when nothing is published, the network
fails, or a published version can't render on this app. Its events still reach `onEvent`
as the same typed classes, so app code handles both cases the same way.

## Measurement

Measurement is on when hosted delivery is configured. Views, steps, events and
completions are recorded per published version automatically. Don't add tracking
calls for surface interactions.

- `measurementEnabled: false` switches it off. It must be a constant.
- `analyticsEnabled: false` also switches it off and creates no install id, while
  hosted delivery keeps working.

## App size

By default the app includes the whole built-in widget catalog, so any later update can
use any catalog widget. To keep only the widgets the app's code draws, set this in
`build.yaml`:

```yaml
targets:
  $default:
    builders:
      restage_codegen:user_factories:
        options:
          catalog: derived
```

Then call the generated `registerRestageWidgets()` followed by
`Restage.configureWithInstalledCatalog(...)` in place of `Restage.configure(...)`.
Updates can then only use widgets the app draws somewhere. They can still use any icon:
each surface carries the icons it names. Release builds need no extra flags. Never pass
`--no-tree-shake-icons`.

## Optional bundled surfaces

To ship RFW artifacts for offline loading, set `bundled_runtime: true` on each
surface builder in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      restage_codegen:restage_source_roster:
        options: &restage_placement
          bundled_runtime: true
      restage_codegen:restage_package_surface_compiler:
        options: *restage_placement
      restage_codegen:generated_dart:
        options: *restage_placement
      restage_codegen:outputs:
        options: *restage_placement
```

The build then writes each surface to `assets/restage/bundles/<path under lib>/`. List
each of those directories under `flutter: assets:` in `pubspec.yaml`, since asset
directories aren't recursive, and commit the bundles. A widget test that mounts the
generated surface with `onUnavailable` set now fails if the compiled copy can't render.

Flutter does not hot-reload bundled assets. Hot-restart after regenerating them.
