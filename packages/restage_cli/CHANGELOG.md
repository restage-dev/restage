# Changelog

## 0.1.0 — unreleased

Initial release of the `restage` command-line interface.

`restage experiment`, `restage mutation` and `restage experiment-activation`
are **experimental** and are hidden from `--help` by default. They call
endpoints the hosted service does not serve yet, so running one without opting
in refuses with an explanation rather than failing against a missing route. Set
`RESTAGE_EXPERIMENTAL=1` to enable them; expect their interfaces to change
without a deprecation.

`restage experiment` has one subcommand per operation — `discover`, `create`,
`read-draft`, `save`, `copy`, `validate`, `review`, `activate`, `pause`,
`resume`, `conclude`, `list`, `read`, `results`, `archive`. They stay separate
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
- `restage preview` — launch the local desktop preview for a compiled blob.
- `restage doctor` — diagnose the local toolchain setup.

Global flags `--non-interactive` (alias `--yes` / `-y`) switch every prompt to
its non-interactive form for scripting and CI.
