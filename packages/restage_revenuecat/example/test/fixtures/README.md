These test-only RFW blobs and capability sidecars come from the normal codegen
pipeline, rather than assets packaged with the app.

- `original_paywall.*` compiles `lib/revenuecat_upgrade.dart`.
- `featured_paywall.*` is a frozen alternate layout used to test updates and
  rollback. Its authored source is not retained in this directory.

To refresh the original pair, run `dart run build_runner build` and extract the matching
`assets/paywalls/revenuecat_upgrade.rfw` and `.capability.json` entries from
`.restage/build/bundles/lib/revenuecat_upgrade.rsbundle`. Updating the alternate
fixture requires authoring and compiling a replacement layout at the same path;
restore the normal source and measurement state afterwards.
The tests read only the checked-in fixtures, so they run without tooling outputs
or Flutter paywall assets.
