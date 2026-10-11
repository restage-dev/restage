These test-only RFW blobs and capability sidecars come from the normal codegen
pipeline, rather than assets packaged with the app.

- `original_paywall.*` compiles `lib/revenuecat_upgrade.dart`.
- `featured_paywall.*` compiles `featured_paywall.dart.txt` temporarily as
  `lib/revenuecat_upgrade.dart`.

Run `dart run build_runner build` and extract the matching
`assets/paywalls/revenuecat_upgrade.rfw` and `.capability.json` entries from
`.restage/build/bundles/lib/revenuecat_upgrade.rsbundle`. Restore the original
source and measurement state after compiling the featured version, then rebuild.
The tests read only the checked-in fixtures, so they run without tooling outputs
or Flutter paywall assets.
