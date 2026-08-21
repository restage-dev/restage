# Restage SDK examples

A small library of paywall and engagement surfaces built with the Restage
Flutter SDK. BSD-3-Clause; it ships with the public SDK. The fastest way from
zero to a shipped surface is to copy one of these, preview it, publish it, and
iterate.

Every surface here is plain Flutter and renders as real Flutter widgets. You
compose your own widgets (design-system components included), and a thin Dart
layer wires flow and events. The build-time codegen compiles each surface to a
small artifact that the SDK decodes at runtime. That same artifact is what
ships over the air.

Run it:

```sh
flutter run
```

Pick a surface from the gallery. The app-bar brightness toggle flips the whole
app between light and dark. The branded surfaces here are fixed-brand, so they
hold their palette; a theme-adaptive surface repaints.

## What is in here

### Starters

The fastest way in. Four bare surfaces, the smallest file per capability. They
use the system theme (no hard-coded palette), so they repaint when you flip the
gallery's light/dark toggle. Copy one, retitle it, restyle it, ship it. They
appear in the gallery's first section, "Starters".

| Starter | Files | Shows |
|---|---|---|
| **Minimal paywall** | `lib/paywalls/minimal_paywall.dart` | `@Paywall` with a two-plan tap-to-select, `paywallPriceFor(slot:)`, and `paywallPurchase(slot:)`. The selection and the purchase path compile into the artifact. |
| **Minimal onboarding** | `lib/onboarding/flows/minimal_onboarding.dart` + `screens/starter_{welcome,question,done_guided,done_explore}.dart` | A multi-screen flow that navigates, writes the captured answer, and routes the ending on it with a `decision()`. |
| **Minimal surface** | `lib/onboarding/flows/minimal_notice.dart` + `screens/starter_notice.dart` | The smallest flow: one screen, a notice. The CTA completes; the × is a host-handled `dismiss`. |
| **Custom widget** | `lib/widgets/minimal_custom_widget.dart` (+ `lib/onboarding/screens/starter_stats.dart`) | A `@RestageWidget` (`StatBadge`) whose pure-composition `build` codegen inlines into the artifact, so your own widget renders through RFW inside a delivered surface with no runtime factory. |

The gallery keeps paywall, screen, and flow sources in `lib/paywalls/`,
`lib/onboarding/screens/`, and `lib/onboarding/flows/`. That is a source
layout. The annotations declare what each file is, and the generated manifest
records each surface's identity and artifacts.

### Paywalls (`lib/paywalls/`)

Each paywall is a `@Paywall` `StatefulWidget` in plain Flutter. All six are
fixed-brand surfaces with literal-color palettes, and each presents a real plan
choice: tap a plan and its selection indicator updates, in that surface's own
visual language, while the purchase CTA re-targets to the selected plan. The
selection lives in widget `State` (`setState`). Codegen compiles those state
reads to state switches in the artifact, so the interaction travels inside the
delivered artifact with no host code.

| Source (`id`) | Archetype | Plan selection |
|---|---|---|
| `pulse_premium` (Pulse) | Dark, segmented tiers | Tri-state tier strip (`int` state) + tap-to-select plan cards |
| `ascend_premium` (Ascend) | Free-trial timeline | Tap "Start free trial" and a modal sheet rises; "See All Plans" swaps the content |
| `fluent_pro` (Fluent Pro) | Gradient-hero free trial | Two plan cards (Personal / Family); "View all plans" pushes a second screen (see below) |
| `sentinel_protection` (Sentinel) | Light savings-badge | Tap-to-select rows with a moving radio |
| `narrate_membership` (Narrate) | Expandable plan cards | Tap a plan and it expands with its benefits + CTA while the other collapses |
| `lumen_premium` (Lumen) | Calm meditation selector | Tap-to-select rows with a moving radio; also the last step of the meditation onboarding flow |

`fluent_pro` also shows screen navigation: its "VIEW ALL PLANS" control is a
real `Navigator.push` to a second `@Paywall` (`fluent_pro_choose_plan`). Codegen
compiles that to a two-screen flow (entry, then choose a plan), which
`RestagePaywall` hosts without extra code.

Each paywall appears in the gallery twice: a local widget mount (the authoring
preview, with placeholder prices) and the delivered artifact
(`RestagePaywall(id:)` decoding the bundled artifact, with live prices from the
example product config in `lib/stub_products.dart`). On the delivered tiles the
demo host wires `onEvent` to a SnackBar so every tap has a visible result:
purchases, and the Restore / Terms / Privacy actions that fire host events. A
real app performs the action there instead.

The gallery also includes a minimal `hello` artifact, rendered straight through
`RestagePaywall(id: "hello")`, to show the bare decode-and-render path.

### Engagement surfaces (`lib/onboarding/`)

The same pipeline drives multi-screen engagement surfaces. Flow sources use
`@FlowGraph(surface: Surface.<category>)`, and codegen emits a typed
`SurfaceFlowRef<R>`. The runtime mounts that ref with `RestageFlowGraph<R>`.
The gallery presents four:

- **Meditation onboarding to paywall** (`flows/lumen_onboarding.dart`): welcome,
  two personalization questions, an enable-reminders host-action gate, a
  recap, then the embedded Lumen paywall. Purchasing ends the flow.
- **Location permission primer** (`flows/crave_permission.dart`): a
  delivery-app location soft-ask. "Use current location" runs a host-action
  gate; "Not now" is a host-handled custom event that continues without the
  grant.
- **In-app message** (`flows/apex_drop.dart`): the smallest flow the runtime
  supports. A single-screen retail "drop" announcement whose CTA acts and
  whose × dismisses.
- **Cancellation survey** (`flows/reel_cancel.dart`): a streaming retention
  flow. Two questions, then a save-offer host-action gate ("Keep my discount"
  advances on a redemption; "No thanks" fires a host-handled cancel).

### Capabilities and reference (`lib/`)

Standalone SDK-mechanic demos, listed in the gallery's "Capabilities" and
"Reference" sections and runnable directly with `flutter run -t`:

- **Modal sheet** (`lib/main_modal_sheet_demo.dart`): the declarative
  drag-to-dismiss bottom sheet.
- **Draggable sheet** (`lib/main_draggable_sheet_demo.dart`): the persistent
  detent sheet (peek, mid, full, with snap physics).
- **Hosted delivery** (`lib/main_hosted_paywall_demo.dart`): a paywall fetched
  through the hosted-delivery resolver (served here by an in-app fake server),
  with the fail-closed fallback. The over-the-air path, end to end.
- **Chrome customization ladder** (`lib/onboarding/chrome_ladder_demo.dart`):
  one flow shown at the five chrome-customization levels (Default, Theme,
  Slots, Layout, DIY).

Three more `lib/main_*.dart` entrypoints run with `flutter run -t` but are not
listed in the gallery: `main_plan_board_demo.dart`,
`main_section_header_demo.dart`, and `main_render_bundle.dart`.

### Custom widgets (`lib/widgets/`)

Three `@RestageWidget` custom widgets (`AcmeBorder`, `AcmeStack`, `PromoBadge`)
show the custom-widget registration path. `registerRestageCustomerWidgets()`
(generated into `lib/user_factories.g.dart`) registers them with the SDK. They
are standalone capability demos; the paywalls above do not use them.

## The author, build, preview loop

A paywall is a `StatefulWidget` annotated `@Paywall`, in plain Flutter. The
build-time codegen compiles it:

```
lib/paywalls/<name>.dart  ──(dart run build_runner build)──▶  lib/paywalls/restage.generated/<name>.restage.g.dart
                                                              assets/restage/bundles/lib/paywalls/<name>.rsbundle
```

The generated part carries the typed descriptor. The `.rsbundle` carries the
exact delivery bytes the runtime decodes, so one surface is one addressable
artifact. The manifest at `lib/generated/restage.publication.json` records the
artifacts for each surface. Both are build outputs. The bundles are committed
here so the gallery runs from a fresh clone; the manifest is not.

`assets/paywalls/hello.rfw` is the one exception: a hand-written artifact kept
to show what the format looks like. The build does not produce it.

Publish a surface and iterate over the air:

```sh
restage surface publish fluent_pro
```

Flutter does not hot-reload bundled assets. After a rebuild, hot-restart the
running app (press `R` in `flutter run`).

### Onboarding and messages

Flows use `@FlowGraph(surface: ...)`. The gallery keeps them under
`lib/onboarding/`:

```
lib/onboarding/screens/<screen>.dart  ──▶  screens/restage.generated/<screen>.restage.g.dart
lib/onboarding/flows/<flow>.dart      ──▶  flows/restage.generated/<flow>.restage.g.dart
```

The manifest at `lib/generated/restage.publication.json` records each flow and
the screen artifacts it uses.

A message is the smallest flow (one screen, one terminal state), so it lives
here too. See `flows/apex_drop.dart`.


## Authoring an interactive paywall

A `@Paywall` is a `StatefulWidget`, so selection state lives in the widget's
`State` as a plain field: a `bool` for a two-plan choice, an `int` for a tier
strip. Tapping a plan calls `setState` to update that field. Reading the field
in `build` drives both the selection indicator and which plan the purchase CTA
buys. See `lib/paywalls/fluent_pro.dart` for the two-plan
(`bool personalSelected`) shape, or `lib/paywalls/pulse_premium.dart` for the
tri-state tier strip (`int selectedTier`).

The CTA targets the selected plan's product slot:

```dart
GestureDetector(
  onTap: paywallPurchase(
    slot: personalSelected ? 'monthly' : 'family',
  ),
  child: /* the styled button face */,
)
```

`paywallPurchase(slot:)` references a slot configured with
`Restage.configure(products:)` (see `lib/stub_products.dart`), so the same
source drives the local authoring preview (real `setState`) and the delivered
artifact (the conditional compiles to a state switch). The displayed price and
the charged slot must match. That mapping is the one thing a copy-paste must
get right: the Family card shows the family product, so its CTA charges the
`family` slot.

For prices, read the slot's price with `paywallPriceFor(slot:)`. The runtime
fills it from the host app's resolved store prices.

## Authoring constraints

These keep a surface compilable. They apply to paywalls and onboarding screens
alike:

- **Keep adjacent interpolation in one literal.** Adjacent plain string
  literals fold correctly. A group that mixes plain and interpolated segments
  does not compile yet, so write one interpolated string instead.
- **Full width without `double.infinity`.** `SizedBox(width: double.infinity)`
  does not survive compilation (a non-finite double has no literal in the
  artifact), so the element hugs its content once delivered. For a full-width
  child in a centered column, wrap it as `Row(children: [Expanded(child: ...)])`.
  For a column that is full width throughout, set
  `crossAxisAlignment: CrossAxisAlignment.stretch`.
- **Keep the build tree flat.** Do not extract helper widgets or methods. Write
  the surface inline so the compiler can follow it.
- **Write theme reads inline.** If a surface reads the ambient theme, use the
  full `Theme.of(context).colorScheme.<role>` chain where you use it. Hoisting
  it into a local (`final scheme = Theme.of(context).colorScheme;`) is a form
  the compiler cannot follow.
