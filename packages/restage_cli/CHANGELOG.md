# Changelog

## 0.1.0 — unreleased

Initial release of the `restage` command-line interface.

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
