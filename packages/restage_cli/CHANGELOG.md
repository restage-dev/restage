# Changelog

## 0.1.0 — unreleased

Initial release of the `restage` command-line interface.

`restage mutation` and `restage experiment-activation` are **experimental** and
are hidden from `--help` by default. They call endpoints the hosted service
does not serve yet, so running one without opting in refuses with an
explanation rather than failing against a missing route. Set
`RESTAGE_EXPERIMENTAL=1` to enable them; expect their interfaces to change
without a deprecation.

`package:restage_cli/api.dart` describes the mutation and activation wire in its
own types (`ProgrammaticMutationRequestWireV1` and its three siblings) rather
than importing the service's contract vocabulary. `ProgrammaticMutationApi` and
`ExperimentActivationApi` take and return those. What this package does with a
request is check its size, check it is the canonical byte representation rather
than an equivalent spelling, read the target it addresses, and forward it
unchanged, so that is what it describes.

Commands:

- `restage login` / `restage logout` / `restage whoami` — device-authorization
  sign-in, sign-out, and current-session identity.
- `restage paywall list` / `restage paywall publish` — list paywalls and publish
  a compiled paywall to an environment.
- `restage surface publish` — publish an engagement surface (onboarding,
  message, survey).
- `restage init` — bootstrap Restage into an existing Flutter project.
- `restage preview` — launch the local desktop preview for a compiled blob.
- `restage doctor` — diagnose the local toolchain setup.

Global flags `--non-interactive` (alias `--yes` / `-y`) switch every prompt to
its non-interactive form for scripting and CI.
