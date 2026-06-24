# Vendored `rfw` formats codec

`binary.dart`, `model.dart`, and `text.dart` are a verbatim, pure-Dart copy of
the `rfw` package's `lib/src/dart/{binary,model,text}.dart` (currently **1.1.3**,
see the `Vendored from package:rfw 1.1.3` header in each file). They are vendored
because `rfw`'s pubspec declares a Flutter SDK dependency, which blocks `pub get`
on a Dart-only build image; this subtree parses and (de/en)codes `.rfwtxt`/`.rfw`
without pulling in Flutter.

## The wire boundary this creates

The build-time toolchain encodes blobs with **this vendored copy**. The customer
app runtime — and the editor — decode/encode with the **published `package:rfw`**.
`restage_shared` carries no `rfw` dependency, so the two can drift independently.
They must produce and read **byte-identical** blobs. A breaking binary-format
change in a future `rfw` minor would otherwise let the runtime decode a server
blob differently than it was written.

Two guards keep them aligned:

- **`packages/restage_core/test/rfw_wire_parity_test.dart`** — encodes with the
  vendored codec and decodes with pub `rfw` (and the reverse), asserting parity.
  This is the gate.
- The `rfw` constraint in every package that depends on `rfw` (e.g.
  `packages/restage/pubspec.yaml`) is capped at `>=1.1.3 <1.2.0` so the runtime
  cannot float to a minor the vendored copy has not been verified against.

## Refreshing to a new `rfw` version

Do **not** bump the constraint ceiling without re-vendoring first. Steps:

1. Copy `lib/src/dart/{binary,model,text}.dart` from the target `rfw` release
   over the three files here. They are already pure-Dart in `rfw`'s `dart/`
   subtree, so no de-Fluttering is needed — but re-check the imports stay
   Flutter-free.
2. Update the `Vendored from package:rfw X.Y.Z` header in each file and in the
   barrel comments (`packages/restage_shared/lib/src/rfw_formats.dart`).
3. Bump the `rfw` constraint in every package that depends on `rfw` (e.g.
   `packages/restage/pubspec.yaml`) to `>=X.Y.Z <X.(Y+1).0`, then re-resolve
   dependencies.
4. Run the parity gate (`rfw_wire_parity_test.dart`) and the vendored round-trip
   smoke (`packages/restage_shared/test/rfw_formats_test.dart`). Both must pass against
   the new pub version before the refresh is considered complete.

`LICENSE-rfw` is the upstream BSD-3-Clause license and must be kept alongside the
vendored sources.
