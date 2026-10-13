# Analytics and interpretation

Resolve the [exact target](targets-and-tools.md) before comparing results.
Use `--json` to preserve the service's figures and disclosure metadata. TUI
commands use the same CLI syntax after `/`, including the `restage` prefix.

## Choose the read

| CLI command | MCP tool | Question |
| --- | --- | --- |
| `analytics overview` | `restage_read_analytics_overview` | How is this app performing? |
| `analytics overview --all-apps` | Same tool with `allApps: true` | How do apps compare in this environment and plane? |
| `analytics explore --dimension platform --surface SURFACE_ID` | `restage_read_explore` | How is this surface's traffic distributed? |
| `analytics surface --surface SURFACE_ID` | `restage_read_surface_analytics` | Which versions, metrics and steps explain one surface? |
| `analytics taps --surface SURFACE_ID --version 4` | `restage_read_surface_taps` | Which elements received taps on this version? |
| `surface results SURFACE_ID` | `restage_read_surface_funnel` | Where do eligible presentations progress or drop off? |
| `analytics health` | `restage_read_data_health` | What is the app sending, and what coverage is missing? |
| `experiment list` | `restage_read_experiments` | Which experiments exist and need attention? |
| `experiment results --experiment EXPERIMENT_ID` | `restage_read_experiment` | What decision, effects and safety metrics are reported? |
| `delivery map` | `restage_read_delivery_map` | What is routed where, and what actually painted? |
| `where welcome_flow@v4` | `restage_where` | Where does one surface version serve across environments? |

Prefix CLI entries with `restage`. Use discovered surface and experiment ids;
an analytics surface identity is not interchangeable with an authored slug.
`analytics surface --version` takes published-version identities and can repeat;
`analytics taps --version` takes a positive version ordinal. MCP uses
`surfaceRevisionIds` and `revisionOrdinal`, respectively.

Explore dimensions are `arm`, `publishedVersion`, `sdkVersion`, `country`,
`platform`, `appBuildOrdinal`, `deviceClass` and `countryPlatform`.

## Keep windows comparable

Most reads default to the previous 30 days. Experiment results default to the
accepted run. Their date filters narrow descriptive traffic breakdowns; the
statistical result remains tied to the retained experiment epoch and design.
Specify `--from` and `--until` for comparable descriptive periods:

```sh
restage analytics overview --from 2026-10-01T00:00:00Z \
  --until 2026-10-08T00:00:00Z --json
restage analytics health --from 2026-10-01T00:00:00Z \
  --until 2026-10-08T00:00:00Z --json
```

Windows are half-open: start included, end excluded. Use UTC day boundaries
and inspect the window returned by the service; day-based readings can align
inputs to whole days. MCP uses `windowStartMicros` and
`windowEndExclusiveMicros`, in microseconds since the Unix epoch. The funnel
tool requires both bounds even though the CLI offers defaults.

## Investigate a weak onboarding step

1. Read overview and data health for the same target and window. Check collection
   compatibility, reported loss and disclosure restrictions before interpreting
   a low count.
2. Read the surface metrics and funnel. Identify the served version, eligible
   presentations and authored step where progress falls. Keep completions,
   dismissals and skips distinct.
3. Read that version's taps. Use `analytics explore --dimension platform
   --surface SURFACE_ID` to inspect the surface's views and users across
   versions; SDK or app-build dimensions can also explain its traffic mix.
   Explore has no version filter or completion-rate breakdown. Check the
   delivery map for incompatible builds or older rendered versions.
4. State the evidence and a testable explanation. A before/after change across
   different populations does not establish causation. For an experiment, read
   its decision state, epoch, intervals, safety metrics and excluded builds.
5. Propose a focused surface change, define the comparison period and success
   metric, then use the publication workflow. Report what is observed separately
   from what still needs evaluation.

## Preserve meaning

- Views are presentations; users are anonymous sessions, not verified people.
  Experiment figures use users assigned to a variant. These populations are
  not interchangeable.
- Counts below the disclosure floor of five may be held. Withheld, unavailable,
  unknown and zero are distinct. Preserve the stated reason; do not replace a
  missing figure with zero or infer hidden counts from totals.
- Rates include exact numerator and denominator pairs. Retain them and the
  eligible population when comparing percentages. Keep approximate and lower-bound
  figures labeled as returned.
- Delivery resolutions and rendered paints measure different events. A policy's
  configured percentage does not establish its observed rendering share.
- Experiment result families report availability separately. A withheld
  statistical result can coexist with available descriptive figures. Preserve
  each family's status and use the decision reported by the service.

Use [Experiments](experiments.md) for experiment design and decision semantics.
Report the service's refusal or unavailable state when the selected target has
no usable data.
