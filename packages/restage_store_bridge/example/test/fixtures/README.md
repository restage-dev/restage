# Hosted paywall fixtures

`store_upgrade.rfw` and its capability sidecar were compiled from
`../../lib/store_upgrade.dart`. `featured_store_upgrade.rfw` and its sidecar were
compiled from `featured_store_upgrade.dart.txt` substituted at that same source
path. Both pairs were extracted from the default generator's
`.restage/build/bundles/lib/store_upgrade.rsbundle` after running
`dart run build_runner build`.

The tests send these frozen compiler outputs through the hosted HTTP response.
They check each blob against its capability sidecar hash and do not load app
assets or require `.restage/build` at test time. To refresh, regenerate and
extract each pair, then restore the original source and Measurement state before
regenerating the normal example outputs.
