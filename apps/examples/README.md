# Restage SDK examples

Onboarding flows, in-app messages, surveys, permission prompts, paywalls, and
other screens, each written in ordinary Flutter with one Restage annotation.
Copy one, preview it, publish it, and change it without shipping an app update.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

Each screen is a normal Flutter widget built from your own widgets and design
system, marked with `@Screen` or `@Paywall`. Multi-screen journeys can use a Dart
flow definition; supported `Navigator.push` calls between paywalls also compile
into flows. At build time Restage generates a `*Surface` mount and a delivery
artifact. Mount the generated widget in your app and publish the artifact to
Restage Cloud.

Run the gallery:

```sh
flutter run
```

Pick a surface from the gallery. The app-bar toggle switches between light and
dark. Starters follow the theme; branded surfaces keep their own colors.

## What is in here

### Starters

Small, copy-ready files, one per capability. They use the app theme, so they
repaint when you flip light and dark. They are the gallery's first section.

| Starter | Files | Shows |
|---|---|---|
| **Minimal onboarding** | `lib/onboarding/flows/minimal_onboarding.dart` + `screens/starter_{welcome,question,done_guided,done_explore}.dart` | A multi-screen flow that saves the user's answer and picks the ending from it with a `decision()`. |
| **Minimal surface** | `lib/onboarding/flows/minimal_notice.dart` + `screens/starter_notice.dart` | One screen, a notice. The button completes the flow; the × is a `dismiss` event your app handles. |
| **Bare surface** | `lib/onboarding/flows/bare_surface.dart` + `screens/starter_bare_surface.dart` | One delivered screen with no required event and no forced ending. |
| **Custom widget** | `lib/widgets/minimal_custom_widget.dart` (+ `lib/onboarding/screens/starter_stats.dart`) | Your own `@RestageWidget` (`StatBadge`) inlined into a delivered surface, so the app registers nothing for it. |
| **Host data** | `lib/surfaces/starter_host_data.dart` + `starter_host_data_demo.dart` | A `@Screen` whose rows come from your app. The build generates `StarterChecklistSurface`, which takes them as ordinary arguments; the `for` loop over them compiles, and a tap reaches your app as a typed event. |
| **Minimal paywall** | `lib/paywalls/minimal_paywall.dart` | A two-plan picker whose `continue` event carries the selected plan. The selection logic compiles into the surface. |

Folder names are only a source layout. The annotations decide what each file
is, and the build records each surface's ID and artifacts.

### Onboarding, messages, and surveys

Flows use `@FlowGraph(surface: ...)`. Mount the generated widget, such as
`MinimalOnboardingFlowSurface`, and supply completion callbacks and host actions.
Each generated mount is a placement by default. Use `.atPlacement(...)` when
you want to give it another placement name. Generated mounts support hosted
updates and fall back to compiled Flutter widgets, so app integrations can
leave bundling off.

`RestageFlowGraph`, `RestageFlowController`, and `RestageScreenView` remain
available for custom hosting and resolver diagnostics. The standalone map and
record decoder demos use these lower-level APIs to inspect bundled RFW.

The gallery has:

- **Meditation onboarding** (`lib/onboarding/flows/lumen_onboarding.dart`):
  welcome, two questions, a step that asks your app to turn on reminders,
  a recap, then an offer.
- **Trial-ending message** (`lib/surfaces/lumen_trial_ending_flow.dart`): a
  sheet shown before a trial ends, leading to an offer.
- **Exit survey** (`lib/surfaces/lumen_cancel_flow.dart`): one question with
  five reasons; the answer reaches your app when the flow completes.
- **Location permission primer** (`lib/onboarding/flows/crave_permission.dart`):
  "Use current location" asks your app for the permission; "Not now" continues
  without it.
- **In-app message** (`lib/onboarding/flows/apex_drop.dart`): one screen whose
  button acts and whose × dismisses.
- **Cancellation survey** (`lib/onboarding/flows/reel_cancel.dart`): two
  questions, then a save offer. "Keep my discount" asks your app to apply it;
  "No thanks" sends a cancel event.
- **Goal-based onboarding** (`lib/onboarding/flows/tally_onboarding.dart`):
  the setup screens change with the goal the user picks.

### Paywalls (`lib/paywalls/`)

Each paywall is a `@Paywall` `StatefulWidget` with a real plan choice: tap a
plan and its selection updates, and the main button reports the selected plan
in a `continue` event. Prices are placeholder text.

| Source (`id`) | Style | Plan selection |
|---|---|---|
| `pulse_premium` | Dark, segmented tiers | Three-way tier strip plus plan cards |
| `ascend_premium` | Free-trial timeline | "Start free trial" opens a sheet; "See All Plans" swaps its content |
| `fluent_pro` | Gradient hero | Two plan cards; "View all plans" opens a second screen |
| `sentinel_protection` | Light, savings badge | Rows with a radio button |
| `narrate_membership` | Expandable cards | The tapped plan expands with its benefits |
| `lumen_premium` | Calm meditation | Rows with a radio button |
| `lumen_welcome_offer`, `lumen_annual_upgrade`, `lumen_holiday_promo` | Offer variants | Plan cards or a single plan |

`fluent_pro`'s "View all plans" is a real `Navigator.push` to a second
`@Paywall` (`fluent_pro_choose_plan`). The build turns it into a two-screen
flow.

Each paywall appears twice in the gallery: once as a local widget and once
rendered from its compiled artifact. On the compiled versions, the gallery
shows events and Terms / Privacy taps in a SnackBar. The `hello` tile renders
`assets/paywalls/hello.rfw`, a hand-written artifact that shows what the format
looks like.

### Capabilities

Standalone demos in the gallery's "Capabilities" section. Each also runs on its
own with `flutter run -t`:

- **Modal sheet** (`lib/main_modal_sheet_demo.dart`): a bottom sheet you drag
  to dismiss.
- **Draggable sheet** (`lib/main_draggable_sheet_demo.dart`): a sheet that
  snaps between peek, middle, and full height.
- **Hosted delivery** (`lib/main_hosted_surface_demo.dart`): a paywall fetched
  over the air (from an in-app fake server here), with the fallback used when
  the fetch fails. See [Render a published surface](#render-a-published-surface)
  to point it at your own server.

The other `lib/main_*.dart` files are standalone demos that are not in the
gallery. Run any of them with `flutter run -t lib/<file>.dart`.

### Custom widgets (`lib/widgets/`)

`@RestageWidget` custom widgets such as `AcmeBorder`, `AcmeStack`, and
`PromoBadge`. `registerRestageWidgets()`, generated into
`lib/user_factories.g.dart`, registers them with the SDK.

## Build, preview, publish

The build compiles each annotated file:

```text
lib/onboarding/screens/<screen>.dart  ──(dart run build_runner build)──▶  screens/restage.generated/<screen>.restage.g.dart
                                                                           assets/restage/bundles/lib/onboarding/screens/<screen>.rsbundle
lib/onboarding/flows/<flow>.dart      ──▶  flows/restage.generated/<flow>.restage.g.dart
lib/paywalls/<name>.dart              ──▶  paywalls/restage.generated/<name>.restage.g.dart
```

The gallery enables bundling to compare source widgets with RFW artifact
rendering. Ordinary app integrations should leave bundling off and use generated
`*Surface(...)` mounts, whose compiled-widget fallbacks work offline.

The generated Dart part holds the surface mount and typed reference. The
`.rsbundle` holds the delivery artifacts used by this gallery. The bundles are
committed so the gallery runs from a fresh clone.

The subset icon fonts in the bundles come from the Flutter SDK that ran the
build, so a Flutter upgrade changes their bytes. Rebuild the example after
one.

Flutter does not hot-reload bundled assets. After a rebuild, hot-restart the
app (press `R` in `flutter run`).

Before pushing, point the example at your own project. `restage init` lists
the projects and apps in your organization and writes `restage_config.yaml`
(ignored by git here, since it names your project):

```sh
restage init --no-starter --no-add-deps
```

Push a surface to Restage Cloud, then publish it:

```sh
restage surface push minimal_onboarding
restage surface publish minimal_onboarding
```

A push uploads a new version. A publish makes a pushed version live.

### Render a published surface

`lib/main_hosted_surface_demo.dart` renders any published paywall by slug,
using your publishable key:

```sh
flutter run -t lib/main_hosted_surface_demo.dart \
  --dart-define=RESTAGE_BASE_URL=https://your-backend.example \
  --dart-define=RESTAGE_API_KEY=rs_pk_... \
  --dart-define=RESTAGE_SURFACE=pulse_paywall \
  --dart-define=RESTAGE_SURFACE_TYPE=paywall
```

Onboarding, message, survey and general surfaces render through the generated
`<Name>Surface` mount compiled into the app, such as `FirstRunFlowSurface` in
`lib/onboarding/flows/restage.generated/first_run.restage.g.dart`.

## Interactive state

Selection state lives in the widget's `State` as a plain field: a `bool` for a
two-way choice, an `int` for a three-way strip. Tapping calls `setState`, and
reading the field in `build` drives both the highlight and the event the button
sends. The build compiles this logic into the surface, so it works over the air
with no app code. See `lib/paywalls/fluent_pro.dart` (`bool personalSelected`)
or `lib/paywalls/pulse_premium.dart` (`int selectedTier`).

```dart
GestureDetector(
  onTap: paywallEvent(
    'continue',
    args: {
      'plan': personalSelected ? 'personal' : 'family',
    },
  ),
  child: /* the styled button */,
)
```

Surfaces send events; they never start a purchase. Your app handles the event
and runs its own purchase code. For store-connected paywalls, see the
[RevenueCat example](../../packages/restage_revenuecat/example) or the
[native store example](../../packages/restage_store_bridge/example).

## Authoring limits

- **Don't mix plain and interpolated adjacent strings.** `'a' 'b'` compiles;
  `'Hi ' '$name'` does not. Write one interpolated string instead.
- **No `double.infinity`.** The build rejects it. For a full-width child, use
  `Row(children: [Expanded(child: ...)])`, or set
  `crossAxisAlignment: CrossAxisAlignment.stretch` on the column.

## Generated files

`.restage/wire-ids.events.jsonl` keeps the catalog IDs for your custom widgets,
and `.restage/measurement-state.json` keeps the event IDs. Commit both so IDs
stay stable between builds. The `additional_public_assets` entries in
`build.yaml` make the build notice when either file changes. Everything under
`.restage/build/` is build output and can be deleted.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
