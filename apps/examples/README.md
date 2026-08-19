# Restage SDK examples

A small, curated library of paywall and engagement surfaces built with the
Restage Flutter SDK. BSD-3-Clause; it ships with the public SDK. The fastest way from
zero to a shipped surface is to copy one of these, preview it live, publish it,
and iterate.

Every surface here is authored in standard Flutter and renders as **real
Flutter widgets**: not a webview, and not a separate component dialect you redraw your UI in.
You compose your own Flutter widgets (design-system components included); a thin Dart layer wires
flow and events. The build-time codegen lowers each surface to a small render blob the SDK decodes
at runtime; that same blob is what ships over the air.

Run it:

```sh
flutter run
```

Pick a surface from the gallery. The app-bar brightness toggle flips the whole
app between light and dark. The example surfaces here are fixed-brand, so they
hold their palette; a theme-adaptive surface would repaint.

## What's in here

### Starters: minimal, copy-me

The fastest way in. Four barebones surfaces: the smallest file per capability,
the deliberate inverse of the polished branded library below. They lean on the
system theme (no hard-coded palette), so they repaint when you flip the
gallery's light/dark toggle; copy one, retitle it, restyle it, ship it. They
appear in the gallery's first "Starters" section.

| Starter | File(s) | Shows |
|---|---|---|
| **Minimal paywall** | `lib/paywalls/minimal_paywall.dart` | `@Paywall` with a two-plan tap-to-select, `paywallPriceFor(slot:)`, and `paywallPurchase(slot:)` — the selection + money path lower into the delivered blob. |
| **Minimal onboarding** | `lib/onboarding/flows/minimal_onboarding.dart` + `screens/starter_{welcome,question,done_guided,done_explore}.dart` | A multi-screen flow that navigates, `.write`s the captured answer, and routes the ending on it with a `decision()` — answer-driven branching. |
| **Minimal surface** | `lib/onboarding/flows/minimal_notice.dart` + `screens/starter_notice.dart` | The smallest flow — one screen (a notice / "any screen you render"): the CTA completes, the × is a host-handled `dismiss`. |
| **Custom widget** | `lib/widgets/minimal_custom_widget.dart` (+ `lib/onboarding/screens/starter_stats.dart`) | A `@RestageWidget` (`StatBadge`) whose pure-composition `build` is **inlined into the blob** by codegen, so your own widget renders through RFW inside a delivered surface — no runtime factory. |

> **Where files live.** The gallery keeps paywall, screen, and flow sources in
> readable `lib/paywalls/`, `lib/onboarding/screens/`, and `lib/onboarding/flows/`
> folders. Those are source-layout conventions, not publication selectors. The
> annotations declare source semantics and category; generated metadata records
> the resolved identity and publication artifact closure. The gallery's
> "Starters" section is what groups these files.

### Paywalls (`lib/paywalls/`)

Each paywall is a `@Paywall`-annotated `StatefulWidget` written in
ordinary Flutter. All six are fixed-brand surfaces (deliberate literal-color
palettes) and present a real plan *choice*: tap a plan and its selection
indicator updates (in that surface's own visual language) while the purchase
CTA re-targets to the selected plan. The selection lives in widget `State`
(`setState`); the codegen lowers those state reads to render-blob state
switches, so the interaction also travels inside the delivered blob with no
host code.

| Source (`id`) | Archetype | Plan selection |
|---|---|---|
| `pulse_premium` (Pulse) | Dark, segmented tiers | Tri-state tier strip (`int` state) + tap-to-select plan cards |
| `ascend_premium` (Ascend) | Free-trial timeline | Tap "Start free trial" → a modal sheet rises; "See All Plans" swaps the content |
| `fluent_pro` (Fluent Pro) | Gradient-hero free trial | Two plan cards (Personal / Family); "View all plans" pushes a second screen (see below) |
| `sentinel_protection` (Sentinel) | Light savings-badge | Tap-to-select rows with a moving radio |
| `narrate_membership` (Narrate) | Expandable plan cards | Tap a plan — it expands with its benefits + CTA while the other collapses |
| `lumen_premium` (Lumen) | Calm meditation selector | Tap-to-select rows with a moving radio; also the subscription climax of the meditation onboarding flow |

`fluent_pro` additionally demonstrates **screen navigation**: its "VIEW ALL
PLANS" control is a real `Navigator.push` to a second `@Paywall`
(`fluent_pro_choose_plan`), which the build-time codegen lowers to a 2-screen
flow (entry → choose-a-plan), hosted transparently by `RestagePaywall`.

Each paywall appears in the gallery twice: a local widget mount (the authoring
preview, with placeholder prices) and the delivered render blob
(`RestagePaywall(id:)` decoding the bundled generated artifact, with live prices from the
example product config in `lib/stub_products.dart`). On the delivered tiles the
demo host wires `onEvent` to a small SnackBar so every tap has a visible
result: purchases, and the Restore / Terms / Privacy actions that fire host
events; a real app performs the actual action there instead.

The gallery also includes a minimal `hello` blob (rendered straight through
`RestagePaywall(id: "hello")`) to show the bare runtime decode + render path.

### Engagement surfaces (`lib/onboarding/`)

The same pipeline drives multi-screen engagement surfaces, not just paywalls.
Flow sources use `@FlowGraph(surface: Surface.<category>)`, and codegen emits a
typed `SurfaceFlowRef<R>` for the generated flow. The runtime mounts that ref
with `RestageSurfaceFlow<R>`; `RestageOnboarding` is the onboarding-only
compatibility facade.
The gallery presents four:

- **Meditation onboarding → paywall** (`flows/lumen_onboarding.dart`), a calm
  multi-screen flow: welcome → two personalization questions → an enable-
  reminders host-action gate → recap → the embedded Lumen paywall. Purchasing
  ends the flow.
- **Location permission primer** (`flows/crave_permission.dart`), a delivery-
  app location soft-ask: "Use current location" runs a host-action gate; "Not
  now" is a host-handled custom event that carries on without the grant.
- **In-app message** (`flows/apex_drop.dart`), the smallest flow the runtime
  supports: a single-screen retail "drop" announcement whose CTA acts and whose
  × dismisses.
- **Cancellation survey** (`flows/reel_cancel.dart`), a streaming retention
  flow: two questions → a save-offer host-action gate ("Keep my discount"
  advances on a redemption; "No thanks" fires a host-handled cancel).

### Capabilities & reference (`lib/`)

Standalone SDK-mechanic demos, curated into the gallery's "Capabilities" and
"Reference" sections (and also runnable directly with `flutter run -t`):

- **Modal sheet** (`lib/main_modal_sheet_demo.dart`), the declarative drag-to-
  dismiss bottom sheet.
- **Draggable sheet** (`lib/main_draggable_sheet_demo.dart`), the persistent,
  non-closeable detent sheet (peek ↔ mid ↔ full with snap physics).
- **Hosted delivery** (`lib/main_hosted_paywall_demo.dart`), a paywall fetched
  through the hosted-delivery resolver (served here by an in-app fake server),
  with the fail-closed fallback: the over-the-air path, end to end.
- **Chrome customization ladder** (`lib/onboarding/chrome_ladder_demo.dart`),
  a dev how-to: one flow shown at the five chrome-customization levels (Default
  / Theme / Slots / Layout / DIY).

Three further `lib/main_*.dart` entrypoints are runnable with `flutter run -t`
but are not listed in the gallery: `main_plan_board_demo.dart`,
`main_section_header_demo.dart`, and `main_render_bundle.dart`.

### Custom widgets (`lib/widgets/`)

Three `@RestageWidget`-annotated custom widgets (`AcmeBorder`, `AcmeStack`,
`PromoBadge`) show the custom-widget registration path. They are registered
with the SDK via `registerRestageCustomerWidgets()` (generated into
`lib/user_factories.g.dart`) and demonstrate how a developer's own widget joins
the catalog; they are standalone capability demos, not used by the paywalls
above.

## The author → build → preview loop

A paywall is a `StatefulWidget` annotated `@Paywall`, written in ordinary
Flutter. The build-time codegen lowers it:

```
lib/paywalls/<name>.dart  ──(dart run build_runner build)──▶  lib/paywalls/restage.generated/<name>.restage.g.dart
                                                              assets/restage/bundles/lib/paywalls/<name>.rsbundle
```

The generated part carries the typed descriptor; the `.rsbundle` carries the
exact delivery bytes the runtime decodes, so one surface is one addressable
artifact rather than a set of loose blobs. The manifest at
`lib/generated/restage.publication.json` records the exact closure for each
surface. Both are build outputs; the bundles are committed here so the gallery
runs from a fresh clone, and the manifest is not.

`assets/paywalls/hello.rfw` is the one exception: a hand-authored blob kept to
show what the format looks like, not something the build produces.

Publish a surface and iterate over the air:

```sh
restage surface publish fluent_pro
```

Flutter doesn't hot-reload bundled assets; after a rebuild, hot-restart the
running app (press `R` in `flutter run`).

### Onboarding & messages

Flows are authored with `@FlowGraph(surface: ...)`. The gallery keeps them under
`lib/onboarding/` as a readable source layout:

```
lib/onboarding/screens/<screen>.dart  ──▶  screens/restage.generated/<screen>.restage.g.dart
lib/onboarding/flows/<flow>.dart      ──▶  flows/restage.generated/<flow>.restage.g.dart
```

The generated artifact paths are outputs of the declared surface category. The
fixed manifest at `lib/generated/restage.publication.json` is the
publication authority, including the flow document's screen-artifact closure.

A message is just the smallest flow (one screen, one terminal state), so it
lives here too (see `flows/apex_drop.dart`).

> **Build note:** the generated flow descriptor is not yet auto-formatted by the
> codegen, so after a `build_runner` regen, run `dart format` over it before
> committing. (The generated screen descriptors are already format-clean; this is
> a known gap on the flow descriptor only.)

## Authoring an interactive paywall

A `@Paywall` is a `StatefulWidget`, so selection state lives directly in
the widget's `State` as a plain field: a `bool` for a two-plan choice, an `int`
for a tier strip. Tapping a plan calls `setState` to update that field; the
selection indicator and which plan the purchase CTA buys are both driven by
reading the field in `build`. See `lib/paywalls/fluent_pro.dart` for the
two-plan (`bool personalSelected`) shape, or `lib/paywalls/pulse_premium.dart`
for the tri-state tier strip (`int selectedTier`).

The CTA targets the selected plan's product **slot**:

```dart
GestureDetector(
  onTap: paywallPurchase(
    slot: personalSelected ? 'monthly' : 'family',
  ),
  child: /* the styled button face */,
)
```

`paywallPurchase(slot:)` references a slot configured via
`Restage.configure(products:)` (see `lib/stub_products.dart`), so the same
source drives the local authoring preview (real `setState`) and the delivered
blob (the conditional lowers to a render-blob state switch). The displayed price
and the charged slot must match; that mapping is the one thing a copy-paste
must get right (the Family card shows the family product, so its CTA charges the
`family` slot).

For prices, read the slot's price with `paywallPriceFor(slot:)`; the runtime
fills it from the host app's resolved store prices.

## Authoring constraints

These keep a surface transpilable. They apply to paywalls and onboarding screens
alike:

- **Keep adjacent interpolation in one literal.** Adjacent plain string literals
  are folded correctly. A group that mixes plain and interpolated segments is
  not currently lowerable, so write one interpolated string instead.
- **Full-width without `double.infinity`.** `SizedBox(width: double.infinity)`
  does not survive lowering (a non-finite double has no render-blob literal), so
  the element ends up hugging its content once delivered. For a full-width child
  in a centered column, wrap it as `Row(children: [Expanded(child: ...)])`; for a
  column that is full-width throughout, set `crossAxisAlignment:
  CrossAxisAlignment.stretch`.
- **Keep the build tree flat.** Don't extract helper widgets or methods; author
  the surface inline so the transpiler can follow it.
- **Write theme reads inline.** If a surface reads the ambient theme, use the
  full `Theme.of(context).colorScheme.<role>` chain at the point of use;
  hoisting it into a local (`final scheme = Theme.of(context).colorScheme;`) is a
  form the transpiler can't follow.
