# Changelog

## 0.1.0 — unreleased

Commerce commands manage slot key sets and exact Google plans. `slots set`
maps products with `--add`, `--remove` and `--move` at a `--catalog-revision`;
`products map` is removed. Offering saves patch supplied packages, with explicit
`--retired-package-ids`.
`offerings retire --revive` reactivates the offering and packages retired with it;
earlier individual retirements remain unless that package is explicitly upserted.

Initial release of the `restage` command-line interface.

`restage build push` names each live version that shows the app's compiled
screen on the pushed build, because widget app code it draws is gone or
changed, until it is republished. Render bundles build each surface's
app-rendered widgets outside its screen.

Reads that name a surface by its slug, such as `restage analytics surface
--surface <slug>` and `restage surface results <slug>`, look the slug up in the
target's surface list. A value that can't be a slug is refused before the
lookup. When the service refuses the lookup, the error gives its reason; when
the list changes during the lookup, the error asks you to run the command
again.

`restage init` adds `restage`, `restage_material` and `rfw_catalog_schema` as
dependency overrides from the main branch, so packages added later that ask
for them by version resolve to the same commit. With `--sdk-key` in an app
with an `ios/Runner` folder, it lists `ios/Runner/restage_early.json` under
`flutter: assets:` in `pubspec.yaml`, with or without `--add-deps`.

After a publish, `restage surface publish` says how to show the surface in an
app: put the environment's publishable key in `build.yaml` with
`restage init --sdk-key`, call
`Restage.configure(registerWidgets: kRestageWidgetRegistration)` once at
startup, and mount the generated widget.

`restage keys delivery` prints the public keys an app passes to
`Restage.configure(deliveryKeys: ...)`.

`restage login` signs in to Restage Cloud (`https://api.restage.dev/`) unless
`--endpoint` or `RESTAGE_BACKEND_URL` names another backend.

`restage surface draft push --accept-unhandled-events` pushes a flow draft whose
screens emit events the flow does not handle. Without the flag the push is
refused, and the refusal lists each flow, state, screen and event.
`restage surface push` and `restage paywall push` print a warning for the same
events and push anyway.

`restage surface status` prints a `draft:` line, `code` or `editor`, and notes
when the draft was edited after the latest publish from code. The console shows
the same.

`restage docs search` finds sections of the Restage documentation with their
URLs; `restage docs read` prints a page, or one section, as Markdown.

`restage mutation` and `restage experiment-activation` are **experimental**
and are hidden from `--help` by default. They call endpoints the hosted service
does not serve yet, so running one without opting in refuses with an
explanation rather than failing against a missing route. Set
`RESTAGE_EXPERIMENTAL=1` to enable them; expect their interfaces to change
without a deprecation. `restage experiment` is available by default.

`restage experiment` has one subcommand per operation — `discover`, `create`,
`read-draft`, `save`, `copy`, `validate`, `review`, `activate`, `pause`,
`resume`, `conclude`, `list`, `read`, `results`, `archive`, `readiness`. They stay separate
because the operations are separate: reading a draft, reading an experiment,
and reading its results are three different requests with three different
results, and no flag turns one into another. `--json` prints the exact result
document rather than a shape this tool invents, so what a script reads is what
the service said. `--yes` is required before a write that changes live state.
A write carries an idempotency key, generated per run unless `--idempotency-key`
supplies one; a retry inside a single run resends byte-identical content under
that same key.

`package:restage_cli/api.dart` describes the mutation and activation wire in its
own types (`ProgrammaticMutationRequestWireV1` and its three siblings) rather
than importing the service's contract vocabulary. `ProgrammaticMutationApi` and
`ExperimentActivationApi` take and return those. What this package does with a
request is check its size, check it is the canonical byte representation rather
than an equivalent spelling, read the target it addresses, and forward it
unchanged, so that is what it describes.

`ExperimentApi` is the exception, deliberately. It takes and returns the
published experiment contracts themselves, because the whole point is that this
tool and the dashboard read one contract: a request either decodes as that
contract or it never leaves the machine. `discoverEveryPage` and `listEveryPage`
follow the cursor to the end, tolerate an empty page in the middle, and keep
each section in the order the service sent it. Surfaces are kept by identity and
revision together, so one surface with two revisions is two entries.

`RestageConfig.project` and `RestageConfig.app` are nullable. A
`restage_config.yaml` may leave either out; commands then take it from
`--project` / `--app` or discovery, and name the missing key when neither
supplies it. `restage init --force` updates an existing config without asking.
`restage init` with a `--organization`, `--project`, `--app`, `--env` or
`--plane` value the existing config does not hold updates the config without
`--force`. It changes only the target and keeps every other setting.

`restage init` adds `restage`, `restage_material` and `restage_codegen` from the
`main` branch of the public repository, with the two overrides that keep every
Restage package on that commit, and lists `.restage/**` under
`additional_public_assets` in `build.yaml`, in place of the older
`.restage/...` entries it covers. A Restage package the pubspec already takes
from pub.dev moves to the same `main`, so `flutter pub get` resolves. It says
what it wrote to `build.yaml`. Without a key, builds work offline.

**Breaking:** `--sdk-key` writes `api_key` and `base_url` under the
`restage_codegen:user_factories` options, where the build reads them, instead
of under `restage_codegen:restage_early_template`; options already under the old
builder move there and `early_request` is dropped. The service URL is the
sign-in's, else the backend every other command uses (`RESTAGE_BACKEND_URL`,
then Restage Cloud), without a trailing slash; init says when it isn't the
sign-in's. With a key and an `ios/Runner` directory, init lists
`ios/Runner/restage_early.json` under `flutter: assets:` and writes it as `{}`
until the first build fills it, so the app builds before `build_runner` runs.
`--no-early-request` is removed.

`restage init` adds `build_runner` at `>=2.7.0`, fills an empty
`dependency_overrides:` key instead of adding a second one, and changes nothing
when `pubspec.yaml` does not parse.

Commands:

- `restage login` / `restage logout` / `restage whoami` — device-authorization
  sign-in, sign-out, and current-session identity.
- `restage paywall list` / `restage paywall push` — list paywalls and push a
  compiled paywall to an environment.
- `restage surface push` — push a surface version to an environment.
- `restage surface publish` — make one pushed revision live.
- `restage experiment <operation>` — author, review, activate, and read
  experiments at one target (experimental).
- `restage init` — bootstrap Restage into an existing Flutter project.
- `restage doctor` — diagnose the local toolchain setup.

Global flags `--non-interactive` (alias `--yes` / `-y`) switch every prompt to
its non-interactive form for scripting and CI.
