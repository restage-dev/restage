# `material_ui` / `cupertino_ui` compat fixture

These sources are the standalone probe that established, empirically, how the
toolchain behaves when a customer authors against the new design packages
(`package:material_ui/`, `package:cupertino_ui/`) instead of
`package:flutter/material.dart`.

They are **fixture data, not workspace code** — `analysis_options.yaml` excludes
them from analysis, and `pubspec.template.yaml` is a template rather than a
live `pubspec.yaml` so the probe package is never a workspace member.

## Why a throwaway package rather than a permanent one

The probe package cannot live in the workspace permanently: `material_ui`
depends on `flutter_localizations`, which SDK-pins `intl`, and that pin can
conflict with what a workspace sibling requires. Reproducing the probe therefore
needs a temporary `dependency_overrides:` entry for `intl` at the workspace
root, which is exactly the kind of change that must not be committed.

The permanent regression tests take a different route: they synthesise the two
design-package libraries directly into the analyzer's asset space using the
library URIs verified below, so they need no new dependency at all.

## Reproducing

1. Copy `probe/` to the repository root and rename `pubspec.template.yaml` to
   `pubspec.yaml`. Its `path:` dependencies are written relative to that
   location, so it will not resolve anywhere else.
2. Add the directory to the workspace `pubspec.yaml`'s `workspace:` list, and
   pin `intl` under `dependency_overrides:` to whatever `flutter_localizations`
   requires.
3. `flutter pub get` at the workspace root, then `dart run build_runner build`
   inside the probe directory.
4. Revert the root `pubspec.yaml` edits and delete the copy.

## What the probe established

`evidence/` holds the captured outputs.

- `migrated.rfwtxt` / `baseline.rfwtxt` — the same surface authored against
  `package:material_ui/material_ui.dart` and `package:flutter/material.dart`.
  The emitted text is character-identical and the two screen blobs share one
  SHA-256, which is the whole point: the design-package surface bound silently
  to catalog entries that construct legacy widgets.
- `user_factories.g.dart.emitted` — generated customer code emitting a private
  `lib/src` import of a third-party package.

Established against `material_ui 1.0.0` / `cupertino_ui 1.0.0` under Flutter
3.44.8. The identity join it motivated is covered by the permanent regression
tests, which run on the current pinned toolchain.
