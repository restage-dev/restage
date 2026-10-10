# Setup and delivery

## Packages

```sh
flutter pub add restage
flutter pub add --dev restage_codegen build_runner
```

Restage needs Flutter 3.41 or newer. The optional `restage` CLI can do this step with
`restage init`, which also writes `restage_config.yaml` and a starter paywall. Pass
`--no-starter` to skip the starter.

No `build.yaml` is needed for the default setup. Generated mounts keep the widget you
wrote as their fallback, so nothing has to be bundled as an asset.

## Build

```sh
dart run build_runner build   # once
dart run build_runner watch   # while editing
```

Restart `watch` after adding, removing or renaming an annotated class. Hot reload
doesn't replace a compiled surface that the app loads as an asset; hot restart (`R`)
does.

The build writes, per annotated file:

- `restage.generated/<file>.restage.g.dart` next to the source: the generated mount,
  the reference (`<name>Ref`), and event and result types;
- `.restage/build/bundles/.../<file>.rsbundle`: the compiled surface;
- `.restage/build/metadata/restage.publication.json`: what `restage surface push` reads;
- `lib/user_catalog.g.dart` and `lib/user_factories.g.dart` when the package declares
  custom widgets.

Commit the generated Dart files, `.restage/measurement-state.json` and
`.restage/wire-ids.events.jsonl`; the last two keep analytics and catalog ids stable
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

The lower-level mounts don't fall back to your widget. They need an `unavailable`
policy, an `errorBuilder`, or bundled assets. Use them only when you need that control.

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
      flowResolver: ServerFlowResolver(
        baseUrl: baseUrl,
        apiKey: apiKey,
        active: true,
      ),
    );
  }
  runApp(const MyApp());
}
```

- The key is the public SDK key (`rs_pk_...`) for one environment. The prefix names its
  side and environment, such as `rs_pk_sandbox_dev_` or `rs_pk_live_prod_`. Never put a
  secret key (`rs_sk_...`) in app code.
- `baseUrl` must be HTTPS, except `localhost`, `127.0.0.1` and `::1`.
- Without `flowResolver`, flows render the version built into the app.
- Call `Restage.configure()` with no key to render only what the app contains.
- A published version shows the next time the surface mounts. Live refresh, which
  updates a surface already on screen, is opt-in through the `liveRefresh` parameter.

## When delivery fails

A generated mount shows the widget you wrote when nothing is published, the network
fails, or a published version can't render on this app. Its events still reach `onEvent`
as the same typed classes, so app code handles both cases the same way. The one
exception: with two copies of the same screen on screen at once, the SDK can't tell
which copy an event came from, so it refuses the event.

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
Updates can then only use widgets the app draws somewhere. Release builds need no extra
flags. Never pass `--no-tree-shake-icons`.
