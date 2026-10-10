# restage_cli

[![pub package](https://img.shields.io/pub/v/restage_cli.svg)](https://pub.dev/packages/restage_cli) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The `restage` command line. Use it to set up a project, push surfaces, and
manage what is live. It works the same for a person at a terminal, a CI job,
and an agent.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

## Status

Pre-release. The commands and the on-disk credential format can still change.

## Install

The package is not on pub.dev yet. Until it is, build the native binary from
the repo:

```sh
git clone https://github.com/restage-dev/restage.git
cd restage
melos run cli:install
```

That compiles the CLI and installs it at `$PUB_CACHE/bin/restage`. Make sure
`$HOME/.pub-cache/bin` is on your `PATH`.

Once published, `dart pub global activate restage_cli` installs a shell
wrapper at the same location. You can use either one. The native binary starts
faster because it skips the wrapper's snapshot rebuild on each run.

## Usage

```sh
restage --help

# Sign in and out (device-authorization flow).
restage login
restage whoami
restage logout
restage status

# Set up a Flutter project for Restage.
restage init

# See what you have access to.
restage orgs
restage projects
restage apps
restage envs
restage targets

# List and push the surfaces the build generated.
restage surface list
restage surface push <id>
restage surface push lib/screens/welcome.dart
restage surface push lib/screens/onboarding.dart --all

# Make a pushed revision live.
restage surface publish <id>
restage surface publish <id> --revision <revision>

# Manage one surface.
restage surface status <id>
restage surface history <id>
restage surface results <id>
restage surface rollback <id> --to-version <version> --reason "<reason>"
restage surface freeze <id> --reason "<reason>"
restage surface unfreeze <id> --reason "<reason>"
restage surface kill <id> --reason "<reason>"
restage surface audit <id>

# Work with a draft saved in the dashboard.
restage surface draft pull <id> --out <file>
restage surface draft push <id>

# App configuration, store products, and API keys.
restage app-config show
restage app-config platforms
restage app-config set --ios-bundle-id <id>
restage products list
restage products import --store appStore
restage slots list
restage slots set <name> --entitlement <e> --ios-product-id <id> --android-product-id none
restage stores list
restage keys list
restage keys revoke <id>
restage keys resolve <key>

# Decide which published version each request receives (beta).
restage surface routing --help

# Push the widget catalog or an app build.
restage catalog push
restage build push

# Read the audit log.
restage audit log
restage audit export
restage audit verdict

# Open the full-screen console.
restage console

# Check the local toolchain.
restage doctor
```

`init` works offline. `doctor` also checks `restage_config.yaml` against the
server when you are signed in. `login` and the other commands talk to
Restage Cloud, or to the backend URL you configure.

`surface kill` turns a surface off in an environment, so apps fall back to
the version bundled with them. `surface freeze` stops new publishes to a
surface until you unfreeze it. `surface results` reads the surface's funnel:
views, steps, drop-off, and completions per published version.

In the console, `p` pushes the selected surface and `l` publishes its latest
pushed revision after asking for a reason. On the live plane, kill, publish,
freeze, and unfreeze also ask you to type `confirm`; rollback always does. Type `/` and then any command, such as
`restage surface history welcome`, to run it there and read its output. Pushes,
publishes and other actions show their full output there too, with next steps
written as console commands.

Every command accepts `--non-interactive` (or `--yes` / `-y`) to suppress
prompts. A required value with no default then exits non-zero with a
`required: --foo <value>` message.

Commands that change what the live plane serves ask first. `surface publish`,
`surface freeze`, `surface unfreeze`, `surface routing publish` and
`rollback`, `experiment activate`, `pause`, `resume`, `conclude`, and
`rebuild-serving-records` (except `--readiness-only`), `mutation`, and
`experiment-activation` take `--yes` as consent. `surface kill` and `surface rollback`
refuse `--yes` on the live plane and need an interactive confirmation. On a
sandbox target the first group does not ask, and kill and rollback accept
`--yes`.

List commands such as `restage apps` and `restage targets` print a table with a
header row. Scripts should pass `--json`.

Discovery commands and the console read the current admitted organization
scope. After the CLI confirms a configured organization, app, or environment
target, it saves the corresponding numeric IDs in `restage_config.yaml` for
later selection. A Git-recorded push leaves the tracked config untouched so
its source stays clean for the receipt. Each later command checks saved IDs
against a fresh scope;
editing a slug or plane can require selecting and saving a new target.

## Pushing and publishing

A push uploads a version and changes nothing that is running. A publish makes
one of those versions live. Push ten variants; publish one.

After `dart run build_runner build`, the CLI reads the generated manifest at
`.restage/build/metadata/restage.publication.json` and uploads the artifacts it
lists for the surface you name. `--type` is optional; when you pass it, the CLI
checks that the surface has that type.

You can name the surface by id or by its `.dart` file:

```sh
restage surface push welcome
restage surface push lib/screens/welcome.dart
```

A file is looked up in the same manifest, so it selects what the build
produced for that file. A screen that belongs to a flow selects the flow,
since the flow is what ships it. If a file produced more than one surface, the
CLI lists them and asks, or pushes all of them with `--all`. A file that
produced nothing is an error. A run over several surfaces stops at the first
failure and reports what was pushed and what was not attempted.

Surface types are `onboarding`, `message`, `survey`, `paywall`, and `general`.

`restage surface publish <id>` makes a pushed revision live. Without
`--revision` it publishes the latest revision pushed to the target
environment and prints which one that was. Pass `--revision <n>` to publish an
older one. `--reason` is optional and is recorded in the audit trail.
`restage surface history <id>` lists what has been pushed and marks which
revision is live.

`restage paywall push <name>` still works for a `@Paywall` surface. New scripts
should use `restage surface push` for every surface type.

A push of a surface with measurement writes the app's measurement profile to
`assets/restage/measurement/target-profile.v1.json` and names it in the
output. The app ships it only when `pubspec.yaml` lists it under
`flutter.assets`. The CLI leaves `pubspec.yaml` alone and tells you when the
line is missing; pass `--declare-assets`, or set `declareAssets: true` in
`restage_config.yaml`, to have it added with your comments kept. The console's
push uses the same setting and shows the full output of a push or a build.

### Release receipts

`--record-git` records a push or a publish in your repository. The CLI writes a
small JSON file under `.restage/receipts/` and commits that one file.

```sh
restage surface push welcome --record-git
restage surface publish welcome --record-git
```

Set `recordGit: true` in `restage_config.yaml` to make it the default for the
project, and pass `--no-record-git` to skip it for one run.

A recorded push checks your source before it calls the server:

- Your app package, and the packages it depends on inside the repository, must
  be committed. Untracked files count; ignored files do not. If the package
  graph has not been resolved, the push stops and asks you to run
  `dart pub get`.
- The code generator runs and the check repeats, so generated files your
  repository tracks must be committed too.
- The receipt records the revision, the artifact hashes, and the commit the
  output was built from.

Two commits are involved:

- The source commit is yours, made with your normal Git workflow.
- The receipt commit is the CLI's. It holds only the receipt and points at the
  source commit. Anything else you have staged or modified stays where it is.

Revision numbers count per organization, project, and environment, so `r17` in
staging and `r17` in production are different content. Receipts are filed the
same way:

```
.restage/receipts/acme/storefront/mobile/surface/onboarding/welcome/staging/push-r17.json
.restage/receipts/acme/storefront/mobile/surface/onboarding/welcome/staging/publish-20260917T195237.412Z-r17.json
```

A publish receipt reads the push receipt for that revision. That way it names
the commit the revision was built from, even if your `HEAD` has moved since. If
no push receipt exists, the publish receipt says the source is unknown and the
publish goes ahead.

If the server call succeeds but the commit fails (for example because of a hook
or a signing key), the receipt file is already written. The CLI reports both
results, shows what Git said, and prints the two commands that commit the file:

```
Published "welcome" at r17 in production (contract v2).
Git receipt pending: the operation is recorded in app/.restage/receipts/...
error: cannot run .git/hooks/pre-commit: No such file or directory
Commit it with:
  git -C '/path/to/repo' add -- 'app/.restage/receipts/...'
  git -C '/path/to/repo' commit --only -m 'restage: publish welcome r17 to production' -- 'app/.restage/receipts/...'
```

Running them commits the same file. Nothing is pushed or published again.

The CLI never pushes Git commits to a remote and never creates a branch or a
pull request. Receipt commits land on your current branch.

## Builds (pre-release)

When a surface uses widgets from your app, the dashboard needs a build of your
app to display it. `restage build push` builds those widgets for the web and
uploads the build:

```sh
restage build push               # your personal build
restage build push --env staging # the build for an environment
```

Each app has one build per environment plus one personal build per user. A
personal build shows only in your own dashboard preview. An environment's build
is what everyone in your organization sees. The preview opens on the
environment's build when it has every widget the surface uses, and on your
personal build otherwise; the build menu above the preview switches between
them. Moving an environment's build needs an admin account or an API key. The
command builds twice, checks that both builds are identical, and uploads only
the files the service does not already have:

```
Pushed mobile staging version 4. Moved 3 of 41 app files. Built from a91f2c3.
```

`restage build push` runs the code generator first. Pass `--no-generate` to
build from what the last run produced. `--record-git` writes a release receipt
for the build.

The build uses the Flutter your app uses, whatever version it is. The CLI
takes the SDK from `--flutter-root`, then `flutterRoot` in
`restage_config.yaml` (relative to that file), then the project's FVM link or
the version its `.fvmrc` or `.flutter-version` names in the FVM cache, then
the SDK its last `flutter pub get` used, then `FLUTTER_ROOT`, then `PATH`. The push prints which Flutter it used and where
it found it:

```
Building with Flutter 3.44.8 at /Users/me/fvm/versions/3.44.8 (.fvmrc at /Users/me/app).
```

When you push a surface that uses your app's widgets and the environment has no
build that includes them, the CLI tells you which command to run.
`restage surface push welcome --build` pushes the environment's build first.
The build only feeds dashboard previews: devices render surfaces with the
widgets compiled into the app. So a build that fails does not stop the
surfaces; the push reports the failure and exits non-zero.

For CI, set `RESTAGE_API_KEY` to a secret key with the bundle-push scope. A key
belongs to one organization, app, and environment, so give each environment
its own key and its own job:

```sh
RESTAGE_API_KEY=… restage build push
```

The key is read from the environment only. It cannot be passed as a flag or
in `restage_config.yaml`, and it is never written to the credentials file.

## Analytics and experiment reads

The Analytics pages and the experiment pages are readable from the terminal.
Each command reads one page for one target and window (`--from`, `--until`; the
last 30 days by default). `--json` prints the service's reply unchanged.

```sh
restage analytics overview
restage analytics overview --all-apps
restage analytics explore --dimension platform
restage analytics surface --surface <id>
restage analytics taps --surface <id> --version <ordinal>
restage analytics health
restage experiment list
restage experiment results --experiment <id>
```

## Experiments (beta)

`restage experiment` has one subcommand per experiment operation: drafting,
validation, review, activation, pausing, concluding, and reading. The write
subcommands are hidden until you set `RESTAGE_EXPERIMENTAL=1`, because
Restage Cloud does not serve these operations yet. `list` and `results` are
always available. Run `restage experiment --help` for the full list.

```sh
restage experiment discover
restage experiment create
restage experiment save --draft-id <id> --draft-revision-id <rev> \
  --expected-cas <token> --replacement choices.json
restage experiment validate --draft-id <id> --draft-revision-id <rev> \
  --expected-cas <token>
restage experiment review --draft-id <id> --draft-revision-id <rev> \
  --expected-cas <token>
restage experiment activate --draft-id <id> --draft-revision-id <rev> \
  --expected-cas <token> --review-id <id> --review-digest <digest> --yes

restage experiment read --experiment-id <id>
restage experiment pause --experiment-id <id> --expected-lifecycle-ordinal <n>
```

`--json` prints the service's response unchanged. A write that changes live
state needs `--yes` or an interactive confirmation. Writes send an idempotency
key (one per run, or pass `--idempotency-key`), so a retry never applies an
operation twice.

## Generated files

`restage init` adds `.restage/build/` to your ignore rules. Commit
`.restage/measurement-state.json` and `.restage/wire-ids.events.jsonl`: they
keep analytics IDs and catalog IDs stable across clean builds.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
