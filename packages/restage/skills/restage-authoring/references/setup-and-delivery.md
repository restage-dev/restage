# Setup and delivery

## Packages

```sh
flutter pub add restage
flutter pub add --dev restage_codegen build_runner
```

Restage needs Flutter 3.41 or newer. The optional `restage` CLI can do this step with
`restage init`, which also writes `restage_config.yaml` and a starter paywall. Pass
`--no-starter` to skip the starter. After `init` edits `pubspec.yaml`, run
`flutter pub get` before generating code.

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

The build writes:

- `restage.generated/<file>.restage.g.dart` next to the source: the generated mount,
  the reference (`<name>Ref`), and event and result types;
- `.restage/build/bundles/.../<file>.rsbundle`: the compiled surface;
- `.restage/build/metadata/restage.publication.json`: what `restage surface push` reads;
- `lib/restage_surfaces.g.dart`: `restageSurfaces`, every surface the package compiles;
- `lib/user_factories.g.dart`: widget registration for the app;
- `lib/user_catalog.g.dart` when the package declares custom widgets.

Commit the generated Dart files, `.restage/measurement-state.json` and
`.restage/wire-ids.events.jsonl` and `.restage/library-contracts/` (written by a push);
these keep analytics and catalog identities/contracts stable
across clean builds. `.restage/build/` is build output; `restage init` adds it to
`.gitignore`.

For output paths, inspection reports and reusable-package setup, read
[build-configuration.md](build-configuration.md). For A2UI/GenUI and Widgetbook
outputs, their build order and how they connect to the app, read
[emitters.md](emitters.md). Neither emitter needs bundled surface assets.

## Dashboard preview builds

`restage build push` compiles and uploads the app's widget code for the hosted
dashboard preview. Run it before the first preview that needs app-specific
widgets, then after adding or changing native widgets, factories or library
code. The command runs code generation before compiling by default; keep that
step enabled so the preview uses the current catalog.

With an interactive login, this uploads your personal preview build:

```sh
restage build push
restage build list
```

Inspect the returned build and the list, then open a surface preview and select
that build. `restage build push --env staging` updates the shared environment
preview. Inspect the selected app and environment before replacing a shared
build; the `restage-operations` skill covers targets, permissions and recovery.
With secret-key authentication, the default target is the key's bound
environment instead; `--personal` is unavailable.

Changes to surface composition within an existing catalog generally need only
regeneration and `restage surface push`, followed by publication when ready.
A preview build does not activate surface delivery or distribute a new app
binary to devices. New native capabilities still need an app release. Local
A2UI/GenUI and Widgetbook output does not require a dashboard preview build.

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

<!-- skill-check: declarations -->
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
- `surfaces: restageSurfaces` prefetches known surfaces after the first frame.
  Prefetch can prepare later mounts, but does not create experiment assignments.
- Published content can appear on later mounts when eligible. Live refresh is
  opt-in and subject to swap-safety checks. A standalone screen already showing
  its compiled fallback needs a remount to show a later accepted response.

[configuration.md](configuration.md) covers build channels, catalog family
selection, refresh triggers, reporting controls and resolution diagnostics.

## When delivery fails

A mount waits up to the render deadline for fresh content: 300 ms by default,
set with `Restage.configure(renderDeadline: ...)`. It then uses an eligible local
candidate ready by that time: retained content or an optional bundle, otherwise
the generated mount's compiled fallback. Retained content must match the target,
installed build and identity, and remain unexpired. A slow local read can also
miss the deadline. Accepted background responses can be saved for later mounts.

Unassigned fallback does not record an experiment presentation. An assigned unit
can still be in the analysis when its assigned version never renders. If assignment
credentials miss the deadline, that request cannot create an assignment; a late
response to an already credentialed request or eligible cached content can retain one.

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
use any catalog widget. To derive the built-in set from the app's source and compiled
surfaces, set this in `build.yaml`:

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
Updates can then use the installed catalog, including
[widgets reserved for later updates](configuration.md#reserve-widgets-for-later-updates).
They can still use any icon: each surface carries the icons it names. Release
builds need no extra flags. Never pass `--no-tree-shake-icons`.

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

If A2UI or Widgetbook output is enabled, give those builders the same options
anchor. See [build-configuration.md](build-configuration.md) for the combined
example.

The source `lib/messages/recap.dart` produces
`assets/restage/bundles/lib/messages/recap.rsbundle`. List each bundle directory
under `flutter: assets:` in `pubspec.yaml`, since asset directories aren't
recursive, and commit the bundles.

Test that the bundled RFW path actually renders, and fail the test on resolution
or rendering errors. A passing compiled-widget fallback test does not prove
bundled rendering. Generated screens expose `onUnavailable`; have the callback
fail the test when exercising that path. Merely setting it does not prove which
content rendered, and a render-deadline fallback can occur without calling it.

Flutter does not hot-reload bundled assets. Hot-restart after regenerating them.
